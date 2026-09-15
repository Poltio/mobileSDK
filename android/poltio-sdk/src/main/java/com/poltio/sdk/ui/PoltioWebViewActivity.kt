package com.poltio.sdk.ui

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.webkit.JavascriptInterface
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.ProgressBar
import com.poltio.sdk.PoltioExecutors
import com.poltio.sdk.PoltioLogger
import com.poltio.sdk.PoltioOverlayOptions
import com.poltio.sdk.PoltioSDK
import org.json.JSONObject

/**
 * In-app browser modal presenting the interactive Poltio widget WebView. The Android analogue of
 * iOS's `PoltioWebViewController` — a full-screen Activity instead of a `pageSheet` modal, since
 * Android has no first-party bottom-sheet-modal Activity presentation style.
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
                if (event == "close") finish()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setupUI()
        loadWidgetUrl()
    }

    private fun setupUI() {
        val root = FrameLayout(this).apply { setBackgroundColor(Color.WHITE) }

        val headerHeightPx = dp(48f)
        val header = FrameLayout(this).apply { setBackgroundColor(Color.WHITE) }
        val closeButton = PoltioCloseGlyphView(this, Color.DKGRAY).apply {
            contentDescription = "Close"
            setOnClickListener { finish() }
        }
        header.addView(closeButton, FrameLayout.LayoutParams(dp(32f), dp(32f), Gravity.CENTER_VERTICAL or Gravity.END).apply {
            rightMargin = dp(16f)
        })
        root.addView(header, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, headerHeightPx, Gravity.TOP))

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
            }
        }
        this.webView = webView
        root.addView(webView, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT, Gravity.TOP).apply {
            topMargin = headerHeightPx
        })

        root.addView(progressBar, FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER))

        setContentView(root)
    }

    private val progressBar: ProgressBar by lazy { ProgressBar(this) }

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
        super.onBackPressed()
        notifyDismiss()
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
