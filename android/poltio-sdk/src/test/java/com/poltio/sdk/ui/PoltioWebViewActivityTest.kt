package com.poltio.sdk.ui

import android.content.Intent
import android.net.Uri
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.webkit.WebResourceRequest
import android.webkit.WebView
import androidx.test.core.app.ApplicationProvider
import com.poltio.sdk.PoltioSDK
import com.poltio.sdk.PoltioUrlHandler
import java.util.concurrent.TimeUnit
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf

// `android.net.Uri`'s real implementation (not the "not mocked" stub) is only available under Robolectric.
@RunWith(RobolectricTestRunner::class)
class PoltioWebViewActivityTest {
    @After
    fun tearDown() {
        PoltioSDK.onOpenUrl = null
    }

    private fun findWebView(view: View): WebView? = when (view) {
        is WebView -> view
        is ViewGroup -> (0 until view.childCount).firstNotNullOfOrNull { findWebView(view.getChildAt(it)) }
        else -> null
    }

    /** Simulates the user tapping [url] inside the widget; returns the Activity under test. */
    private fun tapLink(url: Uri): PoltioWebViewActivity {
        val intent = PoltioWebViewActivity.newIntent(ApplicationProvider.getApplicationContext(), "abc", null, null, null)
        val activity = Robolectric.buildActivity(PoltioWebViewActivity::class.java, intent).setup().get()
        val webView = findWebView(activity.window.decorView)!!
        val request = object : WebResourceRequest {
            override fun getUrl() = url
            override fun isForMainFrame() = true
            override fun isRedirect() = false
            override fun hasGesture() = true
            override fun getMethod() = "GET"
            override fun getRequestHeaders() = emptyMap<String, String>()
        }
        assertTrue(shadowOf(webView).webViewClient.shouldOverrideUrlLoading(webView, request))
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)
        return activity
    }

    @Test
    fun `external links close the widget and go to the host handler`() {
        val productUrl = Uri.parse("https://shop.example.com/product/1")
        val handled = mutableListOf<Uri>()
        PoltioSDK.onOpenUrl = PoltioUrlHandler { handled += it; true }

        val activity = tapLink(productUrl)

        assertEquals(listOf(productUrl), handled)
        assertNull(shadowOf(activity).nextStartedActivity)
        assertTrue(activity.isFinishing)
    }

    @Test
    fun `external links keep the widget open without a host handler`() {
        val activity = tapLink(Uri.parse("https://shop.example.com/product/1"))

        assertEquals(Intent.ACTION_VIEW, shadowOf(activity).nextStartedActivity.action)
        assertFalse(activity.isFinishing)
    }

    @Test
    fun `external links fall back to the system when the host declines`() {
        val productUrl = Uri.parse("https://shop.example.com/product/1")
        PoltioSDK.onOpenUrl = PoltioUrlHandler { false }

        val activity = tapLink(productUrl)

        val started = shadowOf(activity).nextStartedActivity
        assertEquals(Intent.ACTION_VIEW, started.action)
        assertEquals(productUrl, started.data)
        assertTrue(activity.isFinishing)
    }

    @Test
    fun `widgetId is appended as a query parameter when present`() {
        val url = PoltioWebViewActivity.buildWidgetUrl(
            publicId = "6c964c1d-6eb4-4c19-ad16-342bd59bdac3",
            widgetId = 42,
            puid = null,
        )
        assertEquals(
            "https://www.poltio.com/widget/6c964c1d-6eb4-4c19-ad16-342bd59bdac3?widget_id=42&disclaimer=off",
            url.toString(),
        )
    }

    @Test
    fun `navigation policy trusts only Poltio domains`() {
        listOf(
            "https://www.poltio.com/widget/abc",
            "https://poltio.com/x",
            "https://cdn.POLTIO.com/img.png",
            "about:blank",
        ).forEach { assertTrue(it, PoltioWebViewActivity.isTrustedWidgetUrl(Uri.parse(it))) }

        listOf(
            "https://shop.example.com/product/1",
            "https://poltio.com.evil.example/phish",
            "https://evilpoltio.com/",
            "myapp://checkout",
            "tel:+15555555555",
            "mailto:hello@example.com",
            "data:text/html,<script>alert(1)</script>",
            "blob:https://www.poltio.com/1234",
            "about:srcdoc",
            "http://www.poltio.com/widget/abc",
            "https://evil.com\\.poltio.com/",
            "https://evil.com%5C.poltio.com/",
        ).forEach { assertFalse(it, PoltioWebViewActivity.isTrustedWidgetUrl(Uri.parse(it))) }
    }

    @Test
    fun `navigation policy is locale-invariant`() {
        val original = java.util.Locale.getDefault()
        try {
            // Turkish lowercases 'I' to dotless 'ı' under locale-sensitive APIs.
            java.util.Locale.setDefault(java.util.Locale.forLanguageTag("tr-TR"))
            assertTrue(PoltioWebViewActivity.isTrustedWidgetUrl(Uri.parse("https://WWW.POLTIO.COM/widget/abc")))
        } finally {
            java.util.Locale.setDefault(original)
        }
    }

    @Test
    fun `trigger accessibility labels join visible text and fall back when empty`() {
        assertEquals("Try our PRODUCT FINDER", PoltioTriggerAccessibility.label("Try our", " PRODUCT\n", "FINDER"))
        assertEquals(PoltioTriggerAccessibility.FALLBACK_LABEL, PoltioTriggerAccessibility.label(null, "  "))
    }

    @Test
    fun `widgetId is omitted when absent`() {
        val url = PoltioWebViewActivity.buildWidgetUrl(
            publicId = "6c964c1d-6eb4-4c19-ad16-342bd59bdac3",
            widgetId = null,
            puid = null,
        )
        assertEquals(
            "https://www.poltio.com/widget/6c964c1d-6eb4-4c19-ad16-342bd59bdac3?disclaimer=off",
            url.toString(),
        )
    }
}
