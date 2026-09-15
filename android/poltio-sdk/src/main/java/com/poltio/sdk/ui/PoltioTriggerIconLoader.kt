package com.poltio.sdk.ui

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import android.widget.FrameLayout
import android.widget.ImageView
import com.poltio.sdk.PoltioExecutors
import com.poltio.sdk.PoltioOverlayOptions
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Future

/**
 * Loads a remote SVG or raster image (`floatingSvg`/`floatingImg`) into an icon-sized slot, used
 * by triggers that show an optional custom icon in place of their default sparkle mark. SVGs
 * render via a lightweight, JS-disabled `WebView` (there's no first-party SVG renderer on
 * Android either); it's created on demand since most triggers never load one.
 */
internal class PoltioTriggerIconLoader(private val container: ViewGroup, private val sizeDp: Float) {
    private var imageView: ImageView? = null
    private var svgWebView: WebView? = null
    private var inFlight: Future<*>? = null

    fun dispose() {
        inFlight?.cancel(true)
        svgWebView?.let { webView -> PoltioExecutors.runOnMain { webView.stopLoading() } }
    }

    /**
     * Attempts to load [overlayOptions]'s custom icon, overlaid exactly on [anchor]'s position.
     * Calls [onLoaded] (main thread) once an image/SVG successfully renders; the caller is
     * responsible for hiding its fallback icon there. A no-op if no icon URL is configured or the
     * download/decode fails.
     */
    fun load(overlayOptions: PoltioOverlayOptions, anchor: View, onLoaded: () -> Unit) {
        val urlString = overlayOptions.resolvedImageUrl() ?: return
        val hasSvg = !overlayOptions.floatingSvg?.trim().isNullOrEmpty()
        val isSvgFile = urlString.substringAfterLast('.', "").lowercase() == "svg" || hasSvg

        inFlight?.cancel(true)
        inFlight = PoltioExecutors.io.submit {
            val bytes = try {
                downloadBytes(urlString)
            } catch (error: Exception) {
                null
            } ?: return@submit

            val text = runCatching { String(bytes, Charsets.UTF_8) }.getOrNull()
            val isSvgContent = isSvgFile || (text?.contains("<svg") == true)

            if (isSvgContent && text != null) {
                PoltioExecutors.runOnMain { showSvg(text, anchor, onLoaded) }
            } else {
                val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                if (bitmap != null) {
                    PoltioExecutors.runOnMain { showImage(bitmap, anchor, onLoaded) }
                }
            }
        }
    }

    private fun downloadBytes(urlString: String): ByteArray? {
        val connection = URL(urlString).openConnection() as HttpURLConnection
        return try {
            connection.connectTimeout = 15_000
            connection.readTimeout = 15_000
            if (connection.responseCode !in 200..299) return null
            connection.inputStream.use { it.readBytes() }
        } finally {
            connection.disconnect()
        }
    }

    private fun showImage(bitmap: Bitmap, anchor: View, onLoaded: () -> Unit) {
        val iv = ensureImageView(anchor)
        iv.setImageBitmap(bitmap)
        iv.visibility = View.VISIBLE
        svgWebView?.visibility = View.GONE
        onLoaded()
    }

    private fun showSvg(svgMarkup: String, anchor: View, onLoaded: () -> Unit) {
        val webView = ensureSvgWebView(anchor)
        val sizePx = container.context.dp(sizeDp)
        val html = """
            <!DOCTYPE html>
            <html>
            <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            html, body {
                background: transparent;
                width: 100%;
                height: 100%;
                display: flex;
                align-items: center;
                justify-content: center;
                overflow: hidden;
            }
            svg {
                width: 100%;
                height: 100%;
                max-width: ${sizePx}px;
                max-height: ${sizePx}px;
            }
            </style>
            </head>
            <body>
            $svgMarkup
            </body>
            </html>
        """.trimIndent()
        webView.loadDataWithBaseURL(null, html, "text/html", "UTF-8", null)
        webView.visibility = View.VISIBLE
        imageView?.visibility = View.GONE
        onLoaded()
    }

    private fun overlayParamsMatching(anchor: View): FrameLayout.LayoutParams {
        val anchorParams = anchor.layoutParams as? FrameLayout.LayoutParams
            ?: FrameLayout.LayoutParams(anchor.width, anchor.height)
        return FrameLayout.LayoutParams(anchorParams)
    }

    private fun ensureImageView(anchor: View): ImageView {
        imageView?.let { return it }
        val iv = ImageView(container.context).apply {
            scaleType = ImageView.ScaleType.FIT_CENTER
            clipToOutline = true
        }
        container.addView(iv, overlayParamsMatching(anchor))
        imageView = iv
        return iv
    }

    private fun ensureSvgWebView(anchor: View): WebView {
        svgWebView?.let { return it }
        val webView = WebView(container.context).apply {
            setBackgroundColor(android.graphics.Color.TRANSPARENT)
            settings.javaScriptEnabled = false
            isVerticalScrollBarEnabled = false
            isHorizontalScrollBarEnabled = false
            isClickable = false
            isFocusable = false
        }
        container.addView(webView, overlayParamsMatching(anchor))
        svgWebView = webView
        return webView
    }
}
