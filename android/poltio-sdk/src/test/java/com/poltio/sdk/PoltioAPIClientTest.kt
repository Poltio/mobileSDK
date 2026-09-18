package com.poltio.sdk

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.net.InetAddress
import java.net.ServerSocket
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit

/** A single HTTP request captured by [startCapturingServer], parsed just enough for assertions. */
private class CapturedRequest(val path: String, val headers: Map<String, String>, val body: String)

// JSONObject's real implementation (not the "not mocked" stub) is only available under Robolectric.
// `PoltioAPIClient` is exercised against a real local socket rather than a mock, since Android's
// unit-test compile classpath (android.jar) excludes `com.sun.net.httpserver` and the project has
// no HTTP-mocking dependency (e.g. MockWebServer) — a raw `ServerSocket` keeps this dependency-free.
@RunWith(RobolectricTestRunner::class)
class PoltioAPIClientTest {
    /**
     * Starts a `ServerSocket` on an ephemeral port that accepts exactly one connection, parses its
     * HTTP request line/headers/body, replies with [responseStatusLine], and completes the returned
     * future. Returns the bound port and that future.
     */
    private fun startCapturingServer(
        responseStatusLine: String = "HTTP/1.1 204 No Content",
    ): Pair<Int, CompletableFuture<CapturedRequest>> {
        val serverSocket = ServerSocket(0, 1, InetAddress.getByName("127.0.0.1"))
        val future = CompletableFuture<CapturedRequest>()
        Thread {
            try {
                serverSocket.accept().use { socket ->
                    val reader = socket.getInputStream().bufferedReader(Charsets.UTF_8)
                    val requestLine = reader.readLine() ?: ""
                    val path = requestLine.split(" ").getOrElse(1) { "" }

                    val headers = mutableMapOf<String, String>()
                    var line = reader.readLine()
                    while (!line.isNullOrEmpty()) {
                        val idx = line.indexOf(':')
                        if (idx > 0) headers[line.substring(0, idx).trim()] = line.substring(idx + 1).trim()
                        line = reader.readLine()
                    }

                    val contentLength = headers["Content-Length"]?.toIntOrNull() ?: 0
                    val bodyBuffer = CharArray(contentLength)
                    var read = 0
                    while (read < contentLength) {
                        val n = reader.read(bodyBuffer, read, contentLength - read)
                        if (n < 0) break
                        read += n
                    }

                    future.complete(CapturedRequest(path, headers, String(bodyBuffer, 0, read)))
                    socket.getOutputStream().write("$responseStatusLine\r\nContent-Length: 0\r\n\r\n".toByteArray())
                    socket.getOutputStream().flush()
                }
            } catch (error: Exception) {
                future.completeExceptionally(error)
            } finally {
                serverSocket.close()
            }
        }.apply { isDaemon = true }.start()
        return serverSocket.localPort to future
    }

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
}
