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
import android.view.ViewOutlineProvider
import android.view.animation.AccelerateInterpolator
import android.view.animation.DecelerateInterpolator
import android.webkit.JavascriptInterface
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.ProgressBar
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.poltio.sdk.PoltioExecutors
import com.poltio.sdk.PoltioLogger
import com.poltio.sdk.PoltioOverlayOptions
import com.poltio.sdk.PoltioSDK
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
class PoltioWebViewActivity : Activity() {
    companion object {
        private const val EXTRA_PUBLIC_ID = "com.poltio.sdk.extra.PUBLIC_ID"
        private const val EXTRA_PUID = "com.poltio.sdk.extra.PUID"
        private const val EXTRA_DISCLAIMER = "com.poltio.sdk.extra.DISCLAIMER"
        private const val EXTRA_CONTENT = "com.poltio.sdk.extra.CONTENT"
        private const val EXTRA_CUSTOM_ID = "com.poltio.sdk.extra.CUSTOM_ID"
        private const val EXTRA_LOC = "com.poltio.sdk.extra.LOC"
        private const val EXTRA_RESULTFIT = "com.poltio.sdk.extra.RESULTFIT"
        private const val BRIDGE_NAME = "PoltioNativeBridge"

        /** Fraction of the sheet's height a downward drag must cross before it counts as a dismiss. */
        private const val DISMISS_DRAG_FRACTION = 0.35f

        /** Fling velocity (px/s) that dismisses the sheet regardless of how far it's been dragged. */
        private const val DISMISS_FLING_VELOCITY = 1200f

        fun newIntent(context: Context, publicId: String, puid: String?, overlayOptions: PoltioOverlayOptions?): Intent =
            Intent(context, PoltioWebViewActivity::class.java).apply {
                putExtra(EXTRA_PUBLIC_ID, publicId)
                putExtra(EXTRA_PUID, puid)
                putExtra(EXTRA_DISCLAIMER, overlayOptions?.disclaimer?.trim()?.takeIf { it.isNotEmpty() } ?: "off")
                putExtra(EXTRA_CONTENT, overlayOptions?.content)
                putExtra(EXTRA_CUSTOM_ID, overlayOptions?.customId)
                putExtra(EXTRA_LOC, overlayOptions?.loc)
                putExtra(EXTRA_RESULTFIT, overlayOptions?.resultfit)
            }

        /** Builds the widget WebView URL with pass-through query parameters. */
        fun buildWidgetUrl(
            publicId: String,
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

            appendIfPresent("puid", puid)
            appendIfPresent("content", content)
            appendIfPresent("custom_id", customId)
            appendIfPresent("loc", loc)
            appendIfPresent("resultfit", resultfit)
            builder.appendQueryParameter("disclaimer", disclaimer)
            return builder.build()
        }
    }

    private var webView: WebView? = null
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
                PoltioSDK.onWidgetEvent?.invoke(event, data)
                if (event == "close") dismissWithAnimation()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setupUI()
        loadWidgetUrl()
    }

    private fun setupUI() {
        val root = FrameLayout(this)

        scrim = View(this).apply {
            setBackgroundColor(Color.argb(140, 0, 0, 0))
            alpha = 0f
            isClickable = true
            setOnClickListener { dismissWithAnimation() }
        }
        root.addView(scrim, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))

        sheet = FrameLayout(this).apply {
            background = GradientDrawable().apply {
                setColor(Color.WHITE)
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
            insets
        }

        dragHandle = FrameLayout(this)
        val grabber = View(this).apply {
            background = GradientDrawable().apply {
                setColor(Color.LTGRAY)
                cornerRadius = dp(2f).toFloat()
            }
        }
        dragHandle.addView(grabber, FrameLayout.LayoutParams(dp(36f), dp(4f), Gravity.TOP or Gravity.CENTER_HORIZONTAL).apply {
            topMargin = dp(8f)
        })

        val closeButton = PoltioCloseGlyphView(this, Color.DKGRAY).apply {
            contentDescription = "Close"
            setOnClickListener { dismissWithAnimation() }
        }
        dragHandle.addView(closeButton, FrameLayout.LayoutParams(dp(32f), dp(32f), Gravity.CENTER_VERTICAL or Gravity.END).apply {
            rightMargin = dp(16f)
        })
        setupDragToDismiss(dragHandle)

        val headerHeightPx = dp(56f)
        sheet.addView(dragHandle, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, headerHeightPx, Gravity.TOP))

        val webView = WebView(this).apply {
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
                // navigation confined to Poltio's own domain and hand anything else to the
                // system browser instead of letting the WebView follow it.
                override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                    val url = request?.url ?: return false
                    val host = url.host
                    if (host != null && (host == "poltio.com" || host.endsWith(".poltio.com"))) {
                        return false
                    }
                    try {
                        view?.context?.startActivity(Intent(Intent.ACTION_VIEW, url))
                    } catch (error: Exception) {
                        PoltioLogger.error { "Failed to open external URL: ${error.message}" }
                    }
                    return true
                }
            }
        }
        this.webView = webView
        sheet.addView(webView, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT, Gravity.TOP).apply {
            topMargin = headerHeightPx
        })

        sheet.addView(progressBar, FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER))

        setContentView(root)
        animateIn()
    }

    private val progressBar: ProgressBar by lazy { ProgressBar(this) }

    /** Tracks vertical drags on [dragHandle] (the grabber + header strip) to swipe-dismiss the sheet. */
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

    /** Slides the sheet down and fades the scrim before finishing — the single path every dismiss goes through. */
    private fun dismissWithAnimation() {
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
        webView?.destroy()
        webView = null
        super.onDestroy()
        notifyDismiss()
    }

    private fun jsonObjectToMap(json: JSONObject): Map<String, Any?> {
        val map = LinkedHashMap<String, Any?>()
        val keys = json.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            map[key] = when (val value = json.opt(key)) {
                JSONObject.NULL -> null
                else -> value
            }
        }
        return map
    }
}
