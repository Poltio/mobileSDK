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
}
