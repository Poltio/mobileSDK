package com.poltio.sdk.ui

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.MotionEvent
import android.view.VelocityTracker
import android.view.View
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import android.view.animation.AccelerateInterpolator
import android.view.animation.DecelerateInterpolator
import android.view.WindowManager
import android.webkit.JavascriptInterface
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.ProgressBar
import androidx.annotation.VisibleForTesting
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import com.poltio.sdk.BuildConfig
import com.poltio.sdk.PoltioCartItem
import com.poltio.sdk.PoltioExecutors
import com.poltio.sdk.PoltioLogger
import com.poltio.sdk.PoltioOverlayOptions
import com.poltio.sdk.PoltioSDK
import org.json.JSONArray
import org.json.JSONObject

/**
 * In-app browser modal presenting the interactive Poltio widget WebView, styled as a bottom sheet
 * layered on top of the host screen — the Android analogue of iOS's `pageSheet` presentation.
 *
 * Backed by a translucent-themed `Activity` (see `Theme.Translucent.NoTitleBar` in the manifest)
 * rather than a `BottomSheetDialogFragment`, so it works with any host `Activity` (not just a
 * `FragmentActivity`) and needs no Material Components dependency — a plain `Activity` plus a
 * hand-drawn scrim, rounded sheet, and slide animation reproduces the same feel with zero extra
 * dependencies, matching AGENTS.md's "native platform components only" guidance. The host screen
 * stays visible (dimmed) behind it, and the sheet can be dismissed anytime via the close button,
 * a tap on the scrim, a swipe down, or the system back gesture — the app is never "left".
 *
 * The widget page communicates back to native code via
 * `window.PoltioNativeBridge.postMessage(JSON.stringify({ event, data }))` — the Android-side name
 * for the same bridge iOS exposes as `window.webkit.messageHandlers.poltioNative`.
 */
internal class PoltioWebViewActivity : Activity() {
    companion object {
        private const val EXTRA_PUBLIC_ID = "com.poltio.sdk.extra.PUBLIC_ID"
        private const val EXTRA_WIDGET_ID = "com.poltio.sdk.extra.WIDGET_ID"
        private const val EXTRA_PUID = "com.poltio.sdk.extra.PUID"
        private const val EXTRA_DISCLAIMER = "com.poltio.sdk.extra.DISCLAIMER"
        private const val EXTRA_CONTENT = "com.poltio.sdk.extra.CONTENT"
        private const val EXTRA_CUSTOM_ID = "com.poltio.sdk.extra.CUSTOM_ID"
        private const val EXTRA_LOC = "com.poltio.sdk.extra.LOC"
        private const val EXTRA_RESULTFIT = "com.poltio.sdk.extra.RESULTFIT"
        private const val EXTRA_WIDGET_BG_COLOR = "com.poltio.sdk.extra.WIDGET_BG_COLOR"
        private const val BRIDGE_NAME = "PoltioNativeBridge"

        /** Fraction of the sheet's height a downward drag must cross before it counts as a dismiss. */
        private const val DISMISS_DRAG_FRACTION = 0.35f

        /** Fling velocity (px/s) that dismisses the sheet regardless of how far it's been dragged. */
        private const val DISMISS_FLING_VELOCITY = 1200f

        fun newIntent(context: Context, publicId: String, widgetId: Int?, puid: String?, overlayOptions: PoltioOverlayOptions?): Intent =
            Intent(context, PoltioWebViewActivity::class.java).apply {
                putExtra(EXTRA_PUBLIC_ID, publicId)
                putExtra(EXTRA_WIDGET_ID, widgetId?.toString())
                putExtra(EXTRA_PUID, puid)
                putExtra(EXTRA_DISCLAIMER, overlayOptions?.disclaimer?.trim()?.takeIf { it.isNotEmpty() } ?: "off")
                putExtra(EXTRA_CONTENT, overlayOptions?.content)
                putExtra(EXTRA_CUSTOM_ID, overlayOptions?.customId)
                putExtra(EXTRA_LOC, overlayOptions?.loc)
                putExtra(EXTRA_RESULTFIT, overlayOptions?.resultfit)
                putExtra(EXTRA_WIDGET_BG_COLOR, overlayOptions?.resolvedWidgetBgColor ?: Color.WHITE)
            }

        /**
         * Whether [url] may load inside the widget WebView. The JS bridge
         * (`window.PoltioNativeBridge`) is exposed to whatever page is loaded, so main-frame
         * navigation stays confined to Poltio's own domain; anything else (product links, external
         * sites, `tel:`/`mailto:`, host-app deep links) is handed to the system instead. Mirrors iOS's
         * `PoltioWebViewController.isTrustedWidgetURL`.
         */
        fun isTrustedWidgetUrl(url: Uri): Boolean {
            val scheme = url.scheme?.lowercase() ?: return false
            // `data:`/`blob:` documents are deliberately not trusted: they'd run arbitrary script
            // with access to the bridge. Only the inert `about:blank` is let through.
            if (url.toString().lowercase() == "about:blank") return true
            // HTTPS only: a cleartext page could be modified in transit to reach the bridge.
            if (scheme != "https") return false
            val host = url.host?.lowercase() ?: return false
            // Only accept plain DNS hostnames. `android.net.Uri` and Chromium don't parse authorities
            // identically (e.g. Chromium treats `\` as `/`), so a host like `evil.com\.poltio.com`
            // would pass the suffix check here yet load `evil.com` — reject anything unusual outright.
            if (!host.all { it in 'a'..'z' || it in '0'..'9' || it == '.' || it == '-' }) return false
            return host == "poltio.com" || host.endsWith(".poltio.com")
        }

        /** Builds the widget WebView URL with pass-through query parameters. */
        fun buildWidgetUrl(
            publicId: String,
            widgetId: Int? = null,
            puid: String?,
            disclaimer: String = "off",
            content: String? = null,
            customId: String? = null,
            loc: String? = null,
            resultfit: String? = null,
        ): Uri {
            val builder = Uri.Builder()
                .scheme("https")
                .authority("www.poltio.com")
                .appendEncodedPath("widget/$publicId")

            fun appendIfPresent(name: String, value: String?) {
                val trimmed = value?.trim()
                if (!trimmed.isNullOrEmpty()) builder.appendQueryParameter(name, trimmed)
            }

            if (widgetId != null) builder.appendQueryParameter("widget_id", widgetId.toString())
            appendIfPresent("puid", puid)
            appendIfPresent("content", content)
            appendIfPresent("custom_id", customId)
            appendIfPresent("loc", loc)
            appendIfPresent("resultfit", resultfit)
            builder.appendQueryParameter("disclaimer", disclaimer)
            // Tells the widget it's running in an app through this SDK, like the web SDK's
            // `session_source=widget`; `sdk_platform`/`sdk_version` match the API's `X-Poltio-SDK-*` headers.
            builder.appendQueryParameter("session_source", "mobilesdk")
            builder.appendQueryParameter("sdk_platform", "android")
            builder.appendQueryParameter("sdk_version", BuildConfig.SDK_VERSION)
            return builder.build()
        }
    }

    @VisibleForTesting
    internal var webView: WebView? = null
    private var isDismissHandled = false
    private var isDismissing = false

    private lateinit var scrim: View
    private lateinit var sheet: FrameLayout
    private lateinit var dragHandle: FrameLayout

    /** Proxy for the JS bridge; `@JavascriptInterface` methods run on a WebView-managed thread. */
    private inner class Bridge {
        @JavascriptInterface
        fun postMessage(json: String) {
            val body = try {
                JSONObject(json)
            } catch (error: Exception) {
                PoltioLogger.warning { "Received malformed widget bridge message: $json" }
                return
            }
            val event = body.optString("event", "")
            if (event.isEmpty()) {
                PoltioLogger.warning { "Received malformed widget bridge message: $json" }
                return
            }
            val data = body.optJSONObject("data")?.let(::jsonObjectToMap)

            PoltioExecutors.runOnMain {
                PoltioLogger.debug { "Received widget bridge event '$event'." }
                PoltioSDK.onWidgetEvent?.onWidgetEvent(event, data)
                when (event) {
                    "close" -> dismissWithAnimation()
                    // ponytail: `addJavascriptInterface` can't tell which frame called, so unlike iOS an
                    // embedded third-party iframe could send this too; switch the bridge to
                    // `WebViewCompat.addWebMessageListener` (androidx.webkit) to restrict it by origin.
                    "addToCart" -> addToCart(data)
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setupUI()
        loadWidgetUrl()
    }

    private fun setupUI() {
        // Lay out edge-to-edge on every API level and apply system-bar/keyboard insets ourselves
        // (below), so behaviour matches what Android 15+ enforces for apps targeting SDK 35 — and
        // so the sheet shrinks above the soft keyboard instead of hiding lead-form inputs behind it.
        WindowCompat.setDecorFitsSystemWindows(window, false)
        @Suppress("DEPRECATION")
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)

        val root = FrameLayout(this)

        scrim = View(this).apply {
            setBackgroundColor(Color.argb(140, 0, 0, 0))
            alpha = 0f
            isClickable = true
            setOnClickListener { dismissWithAnimation() }
        }
        root.addView(scrim, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))

        val panelBackgroundColor = intent.getIntExtra(EXTRA_WIDGET_BG_COLOR, Color.WHITE)
        sheet = FrameLayout(this).apply {
            background = GradientDrawable().apply {
                setColor(panelBackgroundColor)
                val r = dp(20f).toFloat()
                cornerRadii = floatArrayOf(r, r, r, r, 0f, 0f, 0f, 0f)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                outlineProvider = ViewOutlineProvider.BACKGROUND
                clipToOutline = true
                elevation = dp(8f).toFloat()
            }
        }
        val sheetParams = FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT, Gravity.BOTTOM).apply {
            topMargin = dp(32f)
        }
        root.addView(sheet, sheetParams)

        ViewCompat.setOnApplyWindowInsetsListener(root) { _, insets ->
            val statusBarInset = insets.getInsets(WindowInsetsCompat.Type.statusBars()).top
            sheetParams.topMargin = statusBarInset + dp(24f)
            sheet.layoutParams = sheetParams

            // The sheet's background keeps running behind the navigation bar, but its content
            // (the WebView) stops above whichever is taller: the nav bar or the soft keyboard.
            val navigationBarInset = insets.getInsets(WindowInsetsCompat.Type.navigationBars()).bottom
            val imeInset = insets.getInsets(WindowInsetsCompat.Type.ime()).bottom
            sheet.setPadding(sheet.paddingLeft, sheet.paddingTop, sheet.paddingRight, maxOf(navigationBarInset, imeInset))
            insets
        }

        val webView = WebView(this).apply {
            setBackgroundColor(panelBackgroundColor)
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.mediaPlaybackRequiresUserGesture = false
            addJavascriptInterface(Bridge(), BRIDGE_NAME)
            webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView?, url: String?) {
                    progressBar.visibility = View.GONE
                }

                override fun onReceivedError(view: WebView?, request: WebResourceRequest?, error: WebResourceError?) {
                    progressBar.visibility = View.GONE
                    PoltioLogger.error { "Webview navigation failed: ${error?.description}" }
                }

                // The JS bridge (`window.PoltioNativeBridge`) is exposed to whatever page is
                // currently loaded — an untrusted external site reached via a redirect or a
                // tapped link inside the widget would otherwise gain the same access. Keep
                // navigation confined to Poltio's own domain and hand anything else to the host
                // app (`PoltioSDK.onOpenUrl`) or the system instead of letting the WebView follow it.
                override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                    val url = request?.url ?: return false
                    if (isTrustedWidgetUrl(url)) return false
                    // Sub-frames (e.g. an embedded player's custom scheme) never close the widget.
                    if (request.isForMainFrame) openExternally(url) else openWithSystem(url)
                    return true
                }

                // Without this override, a crashed or OOM-killed WebView renderer process takes the
                // whole host app down with it (API 26+). Tear the sheet down instead and report the
                // event as handled, so only the widget is lost — never the host app.
                override fun onRenderProcessGone(view: WebView?, detail: RenderProcessGoneDetail?): Boolean {
                    val crashed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) detail?.didCrash() == true else false
                    PoltioLogger.warning { "Widget WebView renderer process gone (crashed: $crashed); closing the widget." }
                    view?.let { gone ->
                        (gone.parent as? ViewGroup)?.removeView(gone)
                        gone.destroy()
                    }
                    if (this@PoltioWebViewActivity.webView === view) {
                        this@PoltioWebViewActivity.webView = null
                    }
                    if (!isFinishing) finish()
                    return true
                }
            }
        }
        this.webView = webView
        // The widget fills the whole sheet; the grabber and close button float over it.
        sheet.addView(webView, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT, Gravity.TOP))

        sheet.addView(progressBar, FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER))

        // A small strip around the grabber stays draggable for swipe-to-dismiss, without covering
        // more of the widget than that. Translucent gray reads on light and dark content alike.
        dragHandle = FrameLayout(this)
        val grabber = View(this).apply {
            background = GradientDrawable().apply {
                setColor(Color.argb(150, 128, 128, 128))
                cornerRadius = dp(2f).toFloat()
            }
        }
        dragHandle.addView(grabber, FrameLayout.LayoutParams(dp(36f), dp(4f), Gravity.TOP or Gravity.CENTER_HORIZONTAL).apply {
            topMargin = dp(8f)
        })
        setupDragToDismiss(dragHandle)
        sheet.addView(dragHandle, FrameLayout.LayoutParams(dp(96f), dp(24f), Gravity.TOP or Gravity.CENTER_HORIZONTAL))

        // A white mark on a dark disc keeps the close button legible on any widget content; the
        // 48dp frame around the smaller disc is the tap target.
        val closeButton = FrameLayout(this).apply {
            contentDescription = "Close"
            isClickable = true
            setOnClickListener { dismissWithAnimation() }
            val disc = View(context).apply {
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(Color.argb(140, 0, 0, 0))
                }
            }
            addView(disc, FrameLayout.LayoutParams(dp(30f), dp(30f), Gravity.CENTER))
            addView(PoltioCloseGlyphView(context, Color.WHITE), FrameLayout.LayoutParams(dp(28f), dp(28f), Gravity.CENTER))
        }
        // Top-right in every locale, like the SDK's other physically placed chrome.
        sheet.addView(closeButton, FrameLayout.LayoutParams(dp(48f), dp(48f), Gravity.TOP or Gravity.RIGHT).apply {
            topMargin = dp(4f)
            rightMargin = dp(4f)
        })

        setContentView(root)
        animateIn()
    }

    private val progressBar: ProgressBar by lazy { ProgressBar(this) }

    /** Tracks vertical drags on [dragHandle] (the strip around the grabber) to swipe-dismiss the sheet. */
    private fun setupDragToDismiss(dragHandle: View) {
        var dragStartRawY = 0f
        var dragStartTranslationY = 0f
        var velocityTracker: VelocityTracker? = null

        dragHandle.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    dragStartRawY = event.rawY
                    dragStartTranslationY = sheet.translationY
                    velocityTracker = VelocityTracker.obtain().also { it.addMovement(event) }
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    velocityTracker?.addMovement(event)
                    val dy = event.rawY - dragStartRawY
                    val newTranslation = (dragStartTranslationY + dy).coerceAtLeast(0f)
                    sheet.translationY = newTranslation
                    val sheetHeight = sheet.height.takeIf { it > 0 } ?: 1
                    scrim.alpha = (1f - newTranslation / sheetHeight).coerceIn(0f, 1f)
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    velocityTracker?.addMovement(event)
                    velocityTracker?.computeCurrentVelocity(1000)
                    val velocityY = velocityTracker?.yVelocity ?: 0f
                    velocityTracker?.recycle()
                    velocityTracker = null

                    val sheetHeight = sheet.height.takeIf { it > 0 } ?: 1
                    val draggedFraction = sheet.translationY / sheetHeight
                    if (draggedFraction > DISMISS_DRAG_FRACTION || velocityY > DISMISS_FLING_VELOCITY) {
                        dismissWithAnimation()
                    } else {
                        snapBackOpen()
                    }
                    true
                }
                else -> false
            }
        }
    }

    private fun animateIn() {
        sheet.post {
            if (isFinishing) return@post
            val height = sheet.height
            sheet.translationY = height.toFloat()
            sheet.animate().translationY(0f).setDuration(300).setInterpolator(DecelerateInterpolator()).start()
            scrim.animate().alpha(1f).setDuration(300).start()
        }
    }

    private fun snapBackOpen() {
        sheet.animate().translationY(0f).setDuration(200).setInterpolator(DecelerateInterpolator()).start()
        scrim.animate().alpha(1f).setDuration(200).start()
    }

    /** Hands a URL leaving the widget to the host app's `onOpenUrl`, or else to the system. */
    private fun openExternally(url: Uri) {
        val handler = PoltioSDK.onOpenUrl ?: return openWithSystem(url)
        // Like iOS: close first, then hand over, so the host's UI lands on its own Activity.
        PoltioLogger.debug { "Closing the widget to hand URL '$url' to the host app." }
        dismissWithAnimation {
            // Host navigated away: drop the old trigger (inline, before anything its own
            // off-thread `track()` resolves).
            if (handler.onOpenUrl(url)) PoltioOverlayManager.hideTrigger() else openWithSystem(url)
        }
    }

    /** Offers the widget's add-to-cart tap to the host app, falling back to opening the product link. */
    @VisibleForTesting
    internal fun addToCart(data: Map<String, Any?>?) {
        val item = PoltioCartItem.from(data.orEmpty()) ?: run {
            PoltioLogger.warning { "Ignoring addToCart without a productId or an http(s) url." }
            return
        }
        if (PoltioSDK.onAddToCart?.onAddToCart(item) == true) return
        item.url?.let(::openExternally)
    }

    private fun openWithSystem(url: Uri) {
        try {
            startActivity(Intent(Intent.ACTION_VIEW, url))
        } catch (error: Exception) {
            PoltioLogger.error { "Failed to open external URL: ${error.message}" }
        }
    }

    /**
     * Slides the sheet down and fades the scrim before finishing — the single path every dismiss
     * goes through. [onFinished] runs right after `finish()`; it is dropped if a dismiss is
     * already underway.
     */
    private fun dismissWithAnimation(onFinished: (() -> Unit)? = null) {
        if (isDismissing || isFinishing) return
        isDismissing = true

        val height = sheet.height.takeIf { it > 0 } ?: dp(600f)
        sheet.animate()
            .translationY(height.toFloat())
            .setDuration(220)
            .setInterpolator(AccelerateInterpolator())
            .withEndAction {
                finish()
                overridePendingTransition(0, 0)
                onFinished?.invoke()
            }
            .start()
        scrim.animate().alpha(0f).setDuration(220).start()
    }

    private fun loadWidgetUrl() {
        val publicId = intent.getStringExtra(EXTRA_PUBLIC_ID)
        if (publicId.isNullOrEmpty()) {
            PoltioLogger.error { "PoltioWebViewActivity started without a publicId." }
            finish()
            return
        }

        val url = buildWidgetUrl(
            publicId = publicId,
            widgetId = intent.getStringExtra(EXTRA_WIDGET_ID)?.toIntOrNull(),
            puid = intent.getStringExtra(EXTRA_PUID),
            disclaimer = intent.getStringExtra(EXTRA_DISCLAIMER) ?: "off",
            content = intent.getStringExtra(EXTRA_CONTENT),
            customId = intent.getStringExtra(EXTRA_CUSTOM_ID),
            loc = intent.getStringExtra(EXTRA_LOC),
            resultfit = intent.getStringExtra(EXTRA_RESULTFIT),
        )

        PoltioLogger.debug { "Loading widget WebView: $url" }
        progressBar.visibility = View.VISIBLE
        webView?.loadUrl(url.toString())
    }

    private fun notifyDismiss() {
        if (isDismissHandled) return
        isDismissHandled = true
        cleanupWebView()
        PoltioOverlayManager.onWidgetWebViewDismissed()
    }

    private fun cleanupWebView() {
        val view = webView ?: return
        view.stopLoading()
        view.webViewClient = object : WebViewClient() {}
        view.removeJavascriptInterface(BRIDGE_NAME)
    }

    override fun onBackPressed() {
        dismissWithAnimation()
    }

    override fun onDestroy() {
        cleanupWebView()
        // Destroying a WebView while it's still attached to its parent can crash or leak on some
        // Android/WebView versions — detach it from the view hierarchy first.
        webView?.let { view ->
            (view.parent as? ViewGroup)?.removeView(view)
            view.destroy()
        }
        webView = null
        super.onDestroy()
        // A configuration change (e.g. rotation) destroys and recreates this Activity without
        // ever calling `presentWidgetWebView` again — `notifyDismiss()` must not fire here, or it
        // would tell the overlay manager to bring the floating trigger back while the sheet is
        // about to reappear right on top of it.
        if (!isChangingConfigurations) {
            notifyDismiss()
        }
    }

    private fun jsonObjectToMap(json: JSONObject): Map<String, Any?> {
        val map = LinkedHashMap<String, Any?>()
        val keys = json.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            map[key] = convertJsonValue(json.opt(key))
        }
        return map
    }

    private fun jsonArrayToList(array: JSONArray): List<Any?> =
        (0 until array.length()).map { convertJsonValue(array.opt(it)) }

    /** Recursively converts nested `org.json` types so host apps only ever see plain `Map`/`List`. */
    private fun convertJsonValue(value: Any?): Any? = when (value) {
        JSONObject.NULL -> null
        is JSONObject -> jsonObjectToMap(value)
        is JSONArray -> jsonArrayToList(value)
        else -> value
    }
}
