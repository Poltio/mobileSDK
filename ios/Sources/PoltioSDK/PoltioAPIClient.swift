import Foundation

/// Internal network service responsible for sending API requests to Poltio servers.
final class PoltioAPIClient {
    /// Base URL for the Poltio SDK production API.
    static let productionBaseURL = "https://sdk.poltio.com"

    /// Base URL for the Poltio SDK stage API.
    static let stageBaseURL = "https://sdk-stage.poltio.com"

    /// Default base URL used when an API client is constructed without going through
    /// `PoltioSDK.configure(clientKey:)` (e.g. direct/unit-test usage).
    static let defaultBaseURL = stageBaseURL

    /// Endpoint path for resolving mobile widgets.
    static let widgetEndpointPath = "/sdk/mobile/v1/widget"

    /// Endpoint path for reporting a widget impression ("cta-view").
    static let ctaViewEndpointPath = "/sdk/mobile/v1/cta-view"

    /// Endpoint path for recording a purchase for conversion attribution.
    static let purchaseEndpointPath = "/sdk/mobile/v1/purchase"

    private let baseURL: String
    private let session: URLSession

    /// Exposes the resolved base URL. Used exclusively for unit testing.
    /// Not gated behind `#if DEBUG`: `PoltioAPIClient` is `internal`, so this never reaches the SDK's
    /// public API surface, and tests must still be able to access it when run in a Release configuration.
    var baseURLForTesting: String {
        baseURL
    }

    /// Initializes a new API client with custom base URL and URLSession configuration.
    /// - Parameters:
    ///   - baseURL: Base URL string (defaults to `https://sdk-stage.poltio.com`).
    ///   - session: Custom `URLSession` instance (defaults to background-optimized session).
    init(
        baseURL: String = PoltioAPIClient.defaultBaseURL,
        session: URLSession? = nil
    ) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if let customSession = session {
            self.session = customSession
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 15.0
            config.timeoutIntervalForResource = 30.0
            config.waitsForConnectivity = false
            self.session = URLSession(configuration: config)
        }
    }

    /// Resolves the mobile widget for a given screen URL asynchronously.
    /// Performs non-blocking network I/O in the background and suppresses all errors so the host app never crashes.
    /// - Parameters:
    ///   - clientKey: Publishable client key configured for the SDK session.
    ///   - deviceId: Unique SDK device identifier (`sdk_id`).
    ///   - targetURL: Absolute URL string representing the active screen or content.
    ///   - completion: Optional completion handler indicating success or failure with decoded PoltioWidgetResponse.
    /// - Returns: The in-flight `URLSessionDataTask` which can be cancelled if the user navigates away before completion.
    @discardableResult
    func resolveMobileWidget(
        clientKey: String,
        deviceId: String,
        targetURL: String,
        completion: ((Result<PoltioWidgetResponse, Error>) -> Void)? = nil
    ) -> URLSessionDataTask? {
        let endpointString = "\(baseURL)\(PoltioAPIClient.widgetEndpointPath)"
        guard let requestURL = URL(string: endpointString) else {
            PoltioLogger.error("Invalid API endpoint URL '\(endpointString)'.")
            completion?(.failure(URLError(.badURL)))
            return nil
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue(clientKey, forHTTPHeaderField: "X-Poltio-SDK-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: String] = [
            "url": targetURL,
            "device_id": deviceId,
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            PoltioLogger.error("Failed to serialize request payload: \(error.localizedDescription)")
            completion?(.failure(error))
            return nil
        }

        let task = session.dataTask(with: request) { data, response, error in
            if let error {
                if (error as? URLError)?.code == .cancelled || (error as NSError).code == NSURLErrorCancelled {
                    PoltioLogger.debug("Widget resolution request cancelled for '\(targetURL)' (navigated to newer screen).")
                } else {
                    PoltioLogger.error("Network request failed for '\(targetURL)': \(error.localizedDescription)")
                }
                completion?(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                let invalidRespErr = URLError(.cannotParseResponse)
                PoltioLogger.error("Received non-HTTP response from server.")
                completion?(.failure(invalidRespErr))
                return
            }

            if (200 ... 299).contains(httpResponse.statusCode) {
                guard let responseData = data, !responseData.isEmpty else {
                    PoltioLogger.warning("resolveMobileWidget succeeded (Status: \(httpResponse.statusCode)) but response body was empty.")
                    completion?(.failure(URLError(.cannotDecodeRawData)))
                    return
                }

                if let bodyString = String(data: responseData, encoding: .utf8) {
                    PoltioLogger.debug("resolveMobileWidget response body (Status \(httpResponse.statusCode)):\n\(bodyString)")
                }

                do {
                    let widgetResponse = try JSONDecoder().decode(PoltioWidgetResponse.self, from: responseData)
                    PoltioLogger.info("Successfully resolved widget '\(widgetResponse.publicId)' with trigger type '\(widgetResponse.overlayOptions.triggerType ?? "none")'.")
                    completion?(.success(widgetResponse))
                } catch {
                    PoltioLogger.error("Failed to decode widget response: \(error.localizedDescription)")
                    completion?(.failure(error))
                }
            } else if httpResponse.statusCode == 404 {
                PoltioLogger.debug("No widget configured for URL: '\(targetURL)' (404).")
                completion?(.failure(URLError(.resourceUnavailable)))
            } else {
                PoltioLogger.warning("resolveMobileWidget server returned status \(httpResponse.statusCode) for URL: '\(targetURL)'")
                completion?(.failure(URLError(.badServerResponse)))
            }
        }

        task.resume()
        return task
    }

    /// Reports a widget impression ("cta-view") for a trigger that was actually displayed on screen.
    /// Fire-and-forget: performs the request on a background queue, never blocks the caller, and
    /// suppresses/logs all errors instead of surfacing them — an impression report must never affect
    /// the trigger it's reporting on. The backend responds 204 and forwards the impression
    /// asynchronously, so there is nothing actionable to hand back to the caller either way.
    /// - Parameters:
    ///   - clientKey: Publishable client key configured for the SDK session.
    ///   - deviceId: Unique SDK device identifier (`sdk_id`).
    ///   - publicId: Public identifier of the widget that was displayed.
    ///   - widgetId: Optional numeric widget/arm identifier (omitted when not under A/B testing).
    func reportCtaView(
        clientKey: String,
        deviceId: String,
        publicId: String,
        widgetId: Int?
    ) {
        let endpointString = "\(baseURL)\(PoltioAPIClient.ctaViewEndpointPath)"
        guard let requestURL = URL(string: endpointString) else {
            PoltioLogger.debug("Invalid cta-view endpoint URL '\(endpointString)'.")
            return
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue(clientKey, forHTTPHeaderField: "X-Poltio-SDK-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: Any] = [
            "public_id": publicId,
            "device_id": deviceId,
        ]
        if let widgetId {
            payload["widget_id"] = widgetId
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            PoltioLogger.debug("Failed to serialize cta-view payload: \(error.localizedDescription)")
            return
        }

        session.dataTask(with: request) { _, response, error in
            if let error {
                if (error as? URLError)?.code != .cancelled, (error as NSError).code != NSURLErrorCancelled {
                    PoltioLogger.debug("cta-view report failed for widget '\(publicId)': \(error.localizedDescription)")
                }
                return
            }
            if let httpResponse = response as? HTTPURLResponse, !(200 ... 299).contains(httpResponse.statusCode) {
                PoltioLogger.debug("cta-view report for widget '\(publicId)' returned status \(httpResponse.statusCode).")
            }
        }.resume()
    }

    /// Records a completed purchase for conversion attribution ("recordMobilePurchase").
    /// Fire-and-forget: performs the request on a background queue, never blocks the caller, and
    /// suppresses/logs all errors instead of surfacing them. The backend responds 204 as soon as
    /// the request is accepted and writes the conversion afterwards, so there is nothing
    /// actionable to hand back to the caller beyond "the request was sent".
    /// - Parameters:
    ///   - clientKey: Publishable client key configured for the SDK session.
    ///   - deviceId: Unique SDK device identifier (`sdk_id`) — must match the `deviceId` sent to
    ///     `resolveMobileWidget`, or the purchase is recorded without attribution.
    ///   - url: The checkout/success screen URL or deep link, with scheme and host.
    ///   - orderId: Unique order identifier; the backend's deduplication key.
    ///   - value: Total monetary value of the purchase (must be positive).
    ///   - currency: Optional ISO 4217 currency code.
    ///   - eventTime: Optional time the purchase actually occurred (server defaults to receipt time when omitted).
    ///   - items: Optional line items included in the purchase.
    func recordPurchase(
        clientKey: String,
        deviceId: String,
        url: String,
        orderId: String,
        value: Double,
        currency: String?,
        eventTime: Date?,
        items: [PoltioPurchaseItem]
    ) {
        let endpointString = "\(baseURL)\(PoltioAPIClient.purchaseEndpointPath)"
        guard let requestURL = URL(string: endpointString) else {
            PoltioLogger.error("Invalid purchase endpoint URL '\(endpointString)'.")
            return
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue(clientKey, forHTTPHeaderField: "X-Poltio-SDK-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: Any] = [
            "url": url,
            "device_id": deviceId,
            "order_id": orderId,
            "value": value,
        ]
        if let currency, !currency.isEmpty {
            payload["currency"] = currency
        }
        if let eventTime {
            payload["event_time"] = Int(eventTime.timeIntervalSince1970)
        }
        if !items.isEmpty {
            payload["contents"] = items.map { item -> [String: Any] in
                var content: [String: Any] = ["id": item.id]
                if let name = item.name {
                    content["name"] = name
                    content["productName"] = name
                }
                if let category = item.category {
                    content["category"] = category
                }
                if let quantity = item.quantity {
                    content["quantity"] = quantity
                }
                if let value = item.value {
                    content["value"] = value
                    content["price"] = value
                }
                return content
            }
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            PoltioLogger.error("Failed to serialize purchase payload: \(error.localizedDescription)")
            return
        }

        session.dataTask(with: request) { _, response, error in
            if let error {
                if (error as? URLError)?.code != .cancelled, (error as NSError).code != NSURLErrorCancelled {
                    PoltioLogger.warning("recordPurchase failed for order '\(orderId)': \(error.localizedDescription)")
                }
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                return
            }
            if (200 ... 299).contains(httpResponse.statusCode) {
                PoltioLogger.info("recordPurchase accepted for order '\(orderId)' (Status: \(httpResponse.statusCode)).")
            } else {
                PoltioLogger.warning("recordPurchase for order '\(orderId)' returned status \(httpResponse.statusCode).")
            }
        }.resume()
    }
}
