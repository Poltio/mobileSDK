package com.poltio.sdk.ui

import org.junit.Assert.assertEquals
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
