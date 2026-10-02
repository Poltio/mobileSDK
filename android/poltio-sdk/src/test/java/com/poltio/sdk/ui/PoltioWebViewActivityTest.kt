package com.poltio.sdk.ui

import android.net.Uri
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

// `android.net.Uri`'s real implementation (not the "not mocked" stub) is only available under Robolectric.
@RunWith(RobolectricTestRunner::class)
class PoltioWebViewActivityTest {
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
        ).forEach { assertFalse(it, PoltioWebViewActivity.isTrustedWidgetUrl(Uri.parse(it))) }
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
