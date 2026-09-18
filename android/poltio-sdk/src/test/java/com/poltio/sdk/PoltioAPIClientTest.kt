package com.poltio.sdk

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.util.concurrent.TimeUnit

// JSONObject's real implementation (not the "not mocked" stub) is only available under Robolectric.
// See `PoltioTestHttpCapture.kt` for why a raw socket (not a mock) is used to exercise `PoltioAPIClient`.
@RunWith(RobolectricTestRunner::class)
class PoltioAPIClientTest {
    @Test
    fun `reportCtaView sends public_id, device_id and widget_id to the correct endpoint`() {
        val (port, future) = startCapturingServer()

        val client = PoltioAPIClient(baseURL = "http://127.0.0.1:$port")
        client.reportCtaView(
            clientKey = "pk_test_cta",
            deviceId = "device_123",
            publicId = "widget_public_123",
            widgetId = 8802,
        )

        val request = future.get(3, TimeUnit.SECONDS)
        val body = JSONObject(request.body)

        assertEquals("/sdk/mobile/v1/cta-view", request.path)
        assertEquals("pk_test_cta", request.headers["X-Poltio-SDK-Key"])
        assertEquals("application/json", request.headers["Content-Type"])
        assertEquals("widget_public_123", body.getString("public_id"))
        assertEquals("device_123", body.getString("device_id"))
        assertEquals(8802, body.getInt("widget_id"))
    }

    @Test
    fun `reportCtaView omits widget_id when null rather than sending it as null`() {
        val (port, future) = startCapturingServer()

        val client = PoltioAPIClient(baseURL = "http://127.0.0.1:$port")
        client.reportCtaView(
            clientKey = "pk_test_cta",
            deviceId = "device_456",
            publicId = "widget_no_id",
            widgetId = null,
        )

        val body = JSONObject(future.get(3, TimeUnit.SECONDS).body)
        assertFalse(body.has("widget_id"))
    }

    @Test
    fun `reportCtaView does not throw when the server returns an error`() {
        val (port, future) = startCapturingServer(responseStatusLine = "HTTP/1.1 500 Internal Server Error")

        val client = PoltioAPIClient(baseURL = "http://127.0.0.1:$port")
        client.reportCtaView(clientKey = "pk_test_cta", deviceId = "device_err", publicId = "widget_err", widgetId = null)

        assertTrue("Request was not received in time", future.get(3, TimeUnit.SECONDS) != null)
    }

    @Test
    fun `reportCtaView does not throw when the server is unreachable`() {
        // Port 1 is a privileged port nothing is listening on in the test sandbox — connection refused.
        val client = PoltioAPIClient(baseURL = "http://127.0.0.1:1")
        client.reportCtaView(clientKey = "pk_test_cta", deviceId = "device_unreachable", publicId = "widget_unreachable", widgetId = null)
        // No assertion beyond "did not throw" on this calling thread — the failure happens
        // asynchronously on the background executor and must never propagate to the host app.
    }

    @Test
    fun `recordPurchase sends the full payload including contents to the correct endpoint`() {
        val (port, future) = startCapturingServer()

        val client = PoltioAPIClient(baseURL = "http://127.0.0.1:$port")
        client.recordPurchase(
            clientKey = "pk_test_purchase",
            deviceId = "device_purchase_1",
            url = "myapp://checkout/complete",
            orderId = "ORD-1",
            value = 249.9,
            currency = "TRY",
            eventTimeSeconds = 1_700_000_000L,
            items = listOf(PoltioPurchaseItem(id = "SKU-1", name = "Running Shoe", category = "footwear", quantity = 2, value = 124.95)),
        )

        val request = future.get(3, TimeUnit.SECONDS)
        val body = JSONObject(request.body)

        assertEquals("/sdk/mobile/v1/purchase", request.path)
        assertEquals("pk_test_purchase", request.headers["X-Poltio-SDK-Key"])
        assertEquals("application/json", request.headers["Content-Type"])
        assertEquals("myapp://checkout/complete", body.getString("url"))
        assertEquals("device_purchase_1", body.getString("device_id"))
        assertEquals("ORD-1", body.getString("order_id"))
        assertEquals(249.9, body.getDouble("value"), 0.0)
        assertEquals("TRY", body.getString("currency"))
        assertEquals(1_700_000_000L, body.getLong("event_time"))

        val firstItem = body.getJSONArray("contents").getJSONObject(0)
        assertEquals("SKU-1", firstItem.getString("id"))
        assertEquals("Running Shoe", firstItem.getString("name"))
        assertEquals("Running Shoe", firstItem.getString("productName"))
        assertEquals("footwear", firstItem.getString("category"))
        assertEquals(2, firstItem.getInt("quantity"))
        assertEquals(124.95, firstItem.getDouble("value"), 0.0)
        assertEquals(124.95, firstItem.getDouble("price"), 0.0)
    }

    @Test
    fun `recordPurchase omits optional fields when not provided`() {
        val (port, future) = startCapturingServer()

        val client = PoltioAPIClient(baseURL = "http://127.0.0.1:$port")
        client.recordPurchase(
            clientKey = "pk_test_purchase",
            deviceId = "device_purchase_2",
            url = "myapp://checkout/complete",
            orderId = "ORD-2",
            value = 10.0,
            currency = null,
            eventTimeSeconds = null,
            items = emptyList(),
        )

        val body = JSONObject(future.get(3, TimeUnit.SECONDS).body)
        assertFalse(body.has("currency"))
        assertFalse(body.has("event_time"))
        assertFalse(body.has("contents"))
    }

    @Test
    fun `recordPurchase does not throw when the server returns an error`() {
        val (port, future) = startCapturingServer(responseStatusLine = "HTTP/1.1 500 Internal Server Error")

        val client = PoltioAPIClient(baseURL = "http://127.0.0.1:$port")
        client.recordPurchase(
            clientKey = "pk_test_purchase",
            deviceId = "device_purchase_3",
            url = "myapp://checkout/complete",
            orderId = "ORD-3",
            value = 10.0,
            currency = null,
            eventTimeSeconds = null,
            items = emptyList(),
        )

        assertTrue("Request was not received in time", future.get(3, TimeUnit.SECONDS) != null)
    }

    @Test
    fun `recordPurchase does not throw when the server is unreachable`() {
        val client = PoltioAPIClient(baseURL = "http://127.0.0.1:1")
        client.recordPurchase(
            clientKey = "pk_test_purchase",
            deviceId = "device_purchase_unreachable",
            url = "myapp://checkout/complete",
            orderId = "ORD-unreachable",
            value = 10.0,
            currency = null,
            eventTimeSeconds = null,
            items = emptyList(),
        )
        // No assertion beyond "did not throw" on this calling thread.
    }

    @Test
    fun `a trailing slash on baseURL does not double up in the request path`() {
        val (port, future) = startCapturingServer()

        val client = PoltioAPIClient(baseURL = "http://127.0.0.1:$port/")
        client.recordPurchase(
            clientKey = "pk_test_purchase",
            deviceId = "device_trailing_slash",
            url = "myapp://checkout/complete",
            orderId = "ORD-trailing-slash",
            value = 10.0,
            currency = null,
            eventTimeSeconds = null,
            items = emptyList(),
        )

        val request = future.get(3, TimeUnit.SECONDS)
        assertEquals("/sdk/mobile/v1/purchase", request.path)
    }
}
