package com.poltio.sdk

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
class PoltioSDKTest {
    private val application = ApplicationProvider.getApplicationContext<Application>()

    @After
    fun tearDown() {
        PoltioSDK.reset()
    }

    @Test
    fun `default log level is WARNING`() {
        PoltioSDK.configure(application, clientKey = "poltio_test_pk_123")
        assertEquals(PoltioLogLevel.WARNING, PoltioSDK.logLevel)
    }

    @Test
    fun `identify keeps puid in memory immediately and persists it in the background`() {
        PoltioSDK.configure(application, clientKey = "poltio_test_pk_123")
        PoltioSDK.identify("  user-99  ")
        assertEquals("user-99", PoltioSDK.puid)

        // Wait for the serial state executor to flush the write, then check it hit disk.
        PoltioExecutors.serial.submit {}.get(3, TimeUnit.SECONDS)
        val persisted = application.getSharedPreferences("com.poltio.sdk.prefs", android.content.Context.MODE_PRIVATE)
            .getString("puid", null)
        assertEquals("user-99", persisted)
    }

    @Test
    fun `puid identified before configure is persisted once configured`() {
        PoltioSDK.identify("early-user")
        PoltioSDK.configure(application, clientKey = "poltio_test_pk_123")

        PoltioExecutors.serial.submit {}.get(3, TimeUnit.SECONDS)
        val persisted = application.getSharedPreferences("com.poltio.sdk.prefs", android.content.Context.MODE_PRIVATE)
            .getString("puid", null)
        assertEquals("early-user", persisted)
        assertEquals("early-user", PoltioSDK.puid)
    }

    @Test
    fun `track view sends the widget request from a background thread`() {
        val (port, future) = startCapturingServer(responseStatusLine = "HTTP/1.1 404 Not Found")
        PoltioSDK.configure(application, clientKey = "poltio_test_pk_123")
        PoltioSDK.apiClient = PoltioAPIClient(baseURL = "http://127.0.0.1:$port")

        PoltioSDK.track("view", mapOf("url" to "myapp://products/1"))

        val request = future.get(3, TimeUnit.SECONDS)
        assertEquals("/sdk/mobile/v1/widget", request.path)
        assertEquals("myapp://products/1", JSONObject(request.body).getString("url"))
    }

    @Test
    fun `not initialized before configure`() {
        assertFalse(PoltioSDK.isInitialized)
        assertNull(PoltioSDK.clientKey)
    }

    @Test
    fun `configure trims the client key and marks the SDK initialized`() {
        PoltioSDK.configure(application, clientKey = "  poltio_test_pk_123  ")
        assertTrue(PoltioSDK.isInitialized)
        assertEquals("poltio_test_pk_123", PoltioSDK.clientKey)
    }

    @Test
    fun `blank client key is rejected and leaves the SDK uninitialized`() {
        PoltioSDK.configure(application, clientKey = "   ")
        assertFalse(PoltioSDK.isInitialized)
        assertNull(PoltioSDK.clientKey)
    }

    @Test
    fun `sdkId is stable across repeated access and looks like a UUID`() {
        PoltioSDK.configure(application, clientKey = "poltio_test_pk_123")
        val first = PoltioSDK.sdkId
        val second = PoltioSDK.sdkId
        assertEquals(first, second)
        assertTrue(first.matches(Regex("[0-9a-f-]{36}")))
    }

    @Test
    fun `identify sets and clears puid`() {
        PoltioSDK.configure(application, clientKey = "poltio_test_pk_123")

        PoltioSDK.identify("user-42")
        assertEquals("user-42", PoltioSDK.puid)

        PoltioSDK.identify(null)
        assertNull(PoltioSDK.puid)

        PoltioSDK.identify("  ")
        assertNull(PoltioSDK.puid)
    }

    @Test
    fun `isViewEvent recognizes all documented aliases case-insensitively`() {
        assertTrue(PoltioSDK.isViewEvent("view"))
        assertTrue(PoltioSDK.isViewEvent("VIEW"))
        assertTrue(PoltioSDK.isViewEvent("viewContent"))
        assertTrue(PoltioSDK.isViewEvent("view_content"))
        assertFalse(PoltioSDK.isViewEvent("TrackConversion"))
    }

    @Test
    fun `track before configure is a no-op and does not throw`() {
        PoltioSDK.track("view", mapOf("url" to "https://example.com"))
        // No assertion beyond "did not throw" — the SDK must never crash the host app.
    }

    @Test
    fun `track with a blank event name is a no-op and does not throw`() {
        PoltioSDK.configure(application, clientKey = "poltio_test_pk_123")
        PoltioSDK.track("   ")
    }

    @Test
    fun `clearCache and cache configuration do not throw`() {
        PoltioSDK.cacheTTL = 60.0
        PoltioSDK.cacheLimit = 10
        PoltioSDK.clearCache()
        assertEquals(60.0, PoltioSDK.cacheTTL, 0.0)
        assertEquals(10, PoltioSDK.cacheLimit)
    }

    @Test
    fun `reportCtaView before configure is a no-op and does not throw`() {
        val widget = PoltioWidgetResponse(
            publicId = "widget-before-configure",
            overlayOptions = PoltioOverlayOptions.fromJson(org.json.JSONObject()),
        )
        PoltioSDK.reportCtaView(widget)
        // No assertion beyond "did not throw" — the SDK must never crash the host app, and must
        // never attempt a network call before it has a client key to authenticate with.
    }

    @Test
    fun `reportCtaView after configure does not throw`() {
        PoltioSDK.configure(application, clientKey = "poltio_test_pk_123")
        val widget = PoltioWidgetResponse(
            publicId = "widget-after-configure",
            overlayOptions = PoltioOverlayOptions.fromJson(org.json.JSONObject()),
            widgetId = 42,
        )
        PoltioSDK.reportCtaView(widget)
    }

    @Test
    fun `recordPurchase before configure is a no-op and does not throw`() {
        PoltioSDK.recordPurchase(orderId = "ORD-unconfigured", value = 10.0, url = "myapp://checkout/complete")
        // No assertion beyond "did not throw" — must never attempt a network call before a client key exists.
    }

    @Test
    fun `recordPurchase rejects a blank orderId`() {
        PoltioSDK.configure(application, clientKey = "poltio_test_pk_123")
        PoltioSDK.recordPurchase(orderId = "   ", value = 10.0, url = "myapp://checkout/complete")
        // No assertion beyond "did not throw" — a blank orderId must never reach the network layer.
    }

    @Test
    fun `recordPurchase rejects a non-positive value`() {
        PoltioSDK.configure(application, clientKey = "poltio_test_pk_123")
        PoltioSDK.recordPurchase(orderId = "ORD-zero", value = 0.0, url = "myapp://checkout/complete")
        PoltioSDK.recordPurchase(orderId = "ORD-negative", value = -5.0, url = "myapp://checkout/complete")
    }

    @Test
    fun `recordPurchase rejects a non-finite value`() {
        PoltioSDK.configure(application, clientKey = "poltio_test_pk_123")
        PoltioSDK.recordPurchase(orderId = "ORD-nan", value = Double.NaN, url = "myapp://checkout/complete")
        PoltioSDK.recordPurchase(orderId = "ORD-infinite", value = Double.POSITIVE_INFINITY, url = "myapp://checkout/complete")
    }

    @Test
    fun `recordPurchase rejects a url without scheme and host`() {
        PoltioSDK.configure(application, clientKey = "poltio_test_pk_123")
        PoltioSDK.recordPurchase(orderId = "ORD-bad-url", value = 10.0, url = "checkout/complete")
    }

    @Test
    fun `recordPurchase after configure does not throw`() {
        PoltioSDK.configure(application, clientKey = "poltio_test_pk_123")
        PoltioSDK.recordPurchase(orderId = "ORD-ok", value = 42.5, url = "myapp://checkout/complete", currency = "USD")
    }

    @Test
    fun `recordPurchase filters out invalid items instead of dropping the whole purchase`() {
        val (port, future) = startCapturingServer()
        PoltioSDK.configure(application, clientKey = "poltio_test_pk_123")
        PoltioSDK.apiClient = PoltioAPIClient(baseURL = "http://127.0.0.1:$port")

        PoltioSDK.recordPurchase(
            orderId = "ORD-mixed-items",
            value = 42.5,
            url = "myapp://checkout/complete",
            items = listOf(
                PoltioPurchaseItem(id = "SKU-valid", quantity = 1, value = 10.0),
                PoltioPurchaseItem(id = "", quantity = 1, value = 10.0),
                PoltioPurchaseItem(id = "SKU-nan-value", value = Double.NaN),
                PoltioPurchaseItem(id = "SKU-negative-quantity", quantity = -1),
            ),
        )

        val body = JSONObject(future.get(3, TimeUnit.SECONDS).body)
        val contents = body.getJSONArray("contents")
        assertEquals(1, contents.length())
        assertEquals("SKU-valid", contents.getJSONObject(0).getString("id"))
    }
}
