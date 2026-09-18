package com.poltio.sdk

import java.net.InetAddress
import java.net.ServerSocket
import java.util.concurrent.CompletableFuture

/** A single HTTP request captured by [startCapturingServer], parsed just enough for assertions. */
internal class CapturedRequest(val path: String, val headers: Map<String, String>, val body: String)

/**
 * Starts a `ServerSocket` on an ephemeral port that accepts exactly one connection, parses its
 * HTTP request line/headers/body, replies with [responseStatusLine], and completes the returned
 * future. Returns the bound port and that future.
 *
 * `PoltioAPIClient` is exercised against a real local socket rather than a mock, since Android's
 * unit-test compile classpath (android.jar) excludes `com.sun.net.httpserver` and the project has
 * no HTTP-mocking dependency (e.g. MockWebServer) — a raw `ServerSocket` keeps this dependency-free.
 */
internal fun startCapturingServer(
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
