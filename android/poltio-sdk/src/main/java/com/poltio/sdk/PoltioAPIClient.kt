package com.poltio.sdk

import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.atomic.AtomicBoolean

/** Thrown when the backend explicitly reports no widget configured for a URL (HTTP 404). */
internal class PoltioNoWidgetException : IOException("No widget configured for this URL.")

/**
 * Internal network service responsible for sending API requests to Poltio servers. Uses plain
 * `HttpURLConnection` on a dedicated background executor rather than pulling in an HTTP client
 * dependency, keeping the SDK's footprint minimal.
 */
internal class PoltioAPIClient(
    private val baseURL: String = DEFAULT_BASE_URL,
) {
    companion object {
        const val PRODUCTION_BASE_URL = "https://sdk.poltio.com"
        const val STAGE_BASE_URL = "https://sdk-stage.poltio.com"

        /** Default base URL used when a client is constructed without going through `configure()`. */
        const val DEFAULT_BASE_URL = STAGE_BASE_URL

        const val WIDGET_ENDPOINT_PATH = "/sdk/mobile/v1/widget"
        const val CTA_VIEW_ENDPOINT_PATH = "/sdk/mobile/v1/cta-view"
        const val PURCHASE_ENDPOINT_PATH = "/sdk/mobile/v1/purchase"
    }

    /** Exposes the resolved base URL. Used exclusively for unit testing. */
    val baseURLForTesting: String get() = baseURL

    /** A cancellable in-flight request handle, returned by [resolveMobileWidget]. */
    interface Call {
        fun cancel()
    }

    /**
     * Resolves the mobile widget for a given screen URL asynchronously on a background thread.
     * Suppresses all exceptions so the host app never crashes; every outcome is reported via
     * [completion] as a [Result] instead. [completion] is invoked on the calling background
     * thread, never on a cancelled call.
     *
     * @return a [Call] that can be used to cancel the in-flight request if the user navigates
     * away before it completes.
     */
    fun resolveMobileWidget(
        clientKey: String,
        deviceId: String,
        targetURL: String,
        completion: ((Result<PoltioWidgetResponse>) -> Unit)? = null,
    ): Call {
        val cancelled = AtomicBoolean(false)

        val future = PoltioExecutors.io.submit {
            if (cancelled.get()) return@submit
            var connection: HttpURLConnection? = null
            try {
                val endpoint = URL("$baseURL$WIDGET_ENDPOINT_PATH")
                connection = (endpoint.openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = 15_000
                    readTimeout = 15_000
                    doOutput = true
                    setRequestProperty("X-Poltio-SDK-Key", clientKey)
                    setRequestProperty("Content-Type", "application/json")
                }

                val payload = JSONObject().apply {
                    put("url", targetURL)
                    put("device_id", deviceId)
                }.toString()

                connection.outputStream.use { it.write(payload.toByteArray(Charsets.UTF_8)) }

                if (cancelled.get()) return@submit

                val statusCode = connection.responseCode
                when {
                    statusCode in 200..299 -> {
                        val body = connection.inputStream.bufferedReader().use { it.readText() }
                        if (cancelled.get()) return@submit

                        if (body.isBlank()) {
                            PoltioLogger.warning { "resolveMobileWidget succeeded (Status: $statusCode) but response body was empty." }
                            completion?.invoke(Result.failure(IOException("Empty response body")))
                            return@submit
                        }

                        PoltioLogger.debug { "resolveMobileWidget response body (Status $statusCode):\n$body" }

                        try {
                            val widget = PoltioWidgetResponse.fromJson(JSONObject(body))
                            PoltioLogger.info {
                                "Successfully resolved widget '${widget.publicId}' with trigger type '${widget.overlayOptions.triggerType ?: "none"}'."
                            }
                            completion?.invoke(Result.success(widget))
                        } catch (error: Exception) {
                            PoltioLogger.error { "Failed to decode widget response: ${error.message}" }
                            completion?.invoke(Result.failure(error))
                        }
                    }

                    statusCode == 404 -> {
                        PoltioLogger.debug { "No widget configured for URL: '$targetURL' (404)." }
                        completion?.invoke(Result.failure(PoltioNoWidgetException()))
                    }

                    else -> {
                        PoltioLogger.warning { "resolveMobileWidget server returned status $statusCode for URL: '$targetURL'" }
                        completion?.invoke(Result.failure(IOException("Server returned status $statusCode")))
                    }
                }
            } catch (error: Exception) {
                if (!cancelled.get()) {
                    PoltioLogger.error { "Network request failed for '$targetURL': ${error.message}" }
                    completion?.invoke(Result.failure(error))
                } else {
                    PoltioLogger.debug { "Widget resolution request cancelled for '$targetURL' (navigated to newer screen)." }
                }
            } finally {
                connection?.disconnect()
            }
        }

        return object : Call {
            override fun cancel() {
                cancelled.set(true)
                future.cancel(true)
            }
        }
    }

    /**
     * Reports a widget impression ("cta-view") for a trigger that was actually displayed on
     * screen. Fire-and-forget on a background thread: never blocks the caller, and suppresses/logs
     * all errors instead of surfacing them — an impression report must never affect the trigger
     * it's reporting on. The backend responds 204 and forwards the impression asynchronously, so
     * there is nothing actionable to hand back to the caller either way.
     *
     * @param widgetId Optional numeric widget/arm identifier (omitted when not under A/B testing).
     */
    fun reportCtaView(
        clientKey: String,
        deviceId: String,
        publicId: String,
        widgetId: Int?,
    ) {
        PoltioExecutors.io.submit {
            var connection: HttpURLConnection? = null
            try {
                val endpoint = URL("$baseURL$CTA_VIEW_ENDPOINT_PATH")
                connection = (endpoint.openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = 15_000
                    readTimeout = 15_000
                    doOutput = true
                    setRequestProperty("X-Poltio-SDK-Key", clientKey)
                    setRequestProperty("Content-Type", "application/json")
                }

                val payload = JSONObject().apply {
                    put("public_id", publicId)
                    put("device_id", deviceId)
                    if (widgetId != null) put("widget_id", widgetId)
                }.toString()

                connection.outputStream.use { it.write(payload.toByteArray(Charsets.UTF_8)) }

                val statusCode = connection.responseCode
                if (statusCode !in 200..299) {
                    PoltioLogger.debug { "cta-view report for widget '$publicId' returned status $statusCode." }
                }
            } catch (error: Exception) {
                PoltioLogger.debug { "cta-view report failed for widget '$publicId': ${error.message}" }
            } finally {
                connection?.disconnect()
            }
        }
    }

    /**
     * Records a completed purchase for conversion attribution ("recordMobilePurchase").
     * Fire-and-forget on a background thread: never blocks the caller, and suppresses/logs all
     * errors instead of surfacing them. The backend responds 204 as soon as the request is
     * accepted and writes the conversion afterwards, so there is nothing actionable to hand back
     * to the caller beyond "the request was sent".
     *
     * @param deviceId Must match the `deviceId` sent to [resolveMobileWidget], or the purchase is
     * recorded without attribution.
     * @param url The checkout/success screen URL or deep link, with scheme and host.
     * @param orderId Unique order identifier; the backend's deduplication key.
     * @param value Total monetary value of the purchase (must be positive).
     * @param eventTimeSeconds Optional unix timestamp (seconds) the purchase actually occurred.
     * @param items Optional line items included in the purchase.
     */
    fun recordPurchase(
        clientKey: String,
        deviceId: String,
        url: String,
        orderId: String,
        value: Double,
        currency: String?,
        eventTimeSeconds: Long?,
        items: List<PoltioPurchaseItem>,
    ) {
        PoltioExecutors.io.submit {
            var connection: HttpURLConnection? = null
            try {
                val endpoint = URL("$baseURL$PURCHASE_ENDPOINT_PATH")
                connection = (endpoint.openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = 15_000
                    readTimeout = 15_000
                    doOutput = true
                    setRequestProperty("X-Poltio-SDK-Key", clientKey)
                    setRequestProperty("Content-Type", "application/json")
                }

                val payload = JSONObject().apply {
                    put("url", url)
                    put("device_id", deviceId)
                    put("order_id", orderId)
                    put("value", value)
                    if (!currency.isNullOrEmpty()) put("currency", currency)
                    if (eventTimeSeconds != null) put("event_time", eventTimeSeconds)
                    if (items.isNotEmpty()) {
                        val contents = JSONArray()
                        items.forEach { item ->
                            val content = JSONObject().apply {
                                put("id", item.id)
                                item.name?.let {
                                    put("name", it)
                                    put("productName", it)
                                }
                                item.category?.let { put("category", it) }
                                item.quantity?.let { put("quantity", it) }
                                item.value?.let {
                                    put("value", it)
                                    put("price", it)
                                }
                            }
                            contents.put(content)
                        }
                        put("contents", contents)
                    }
                }.toString()

                connection.outputStream.use { it.write(payload.toByteArray(Charsets.UTF_8)) }

                val statusCode = connection.responseCode
                if (statusCode in 200..299) {
                    PoltioLogger.info { "recordPurchase accepted for order '$orderId' (Status: $statusCode)." }
                } else {
                    PoltioLogger.warning { "recordPurchase for order '$orderId' returned status $statusCode." }
                }
            } catch (error: Exception) {
                PoltioLogger.warning { "recordPurchase failed for order '$orderId': ${error.message}" }
            } finally {
                connection?.disconnect()
            }
        }
    }
}
