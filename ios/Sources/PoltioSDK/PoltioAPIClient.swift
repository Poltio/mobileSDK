import Foundation

/// Internal network service responsible for sending API requests to Poltio servers.
final class PoltioAPIClient {
    /// Default base URL for the Poltio SDK API.
    static let defaultBaseURL = "https://sdk-stage.poltio.com"

    /// Endpoint path for resolving mobile widgets.
    static let widgetEndpointPath = "/sdk/mobile/v1/widget"

    private let baseURL: String
    private let session: URLSession

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
    ///   - completion: Optional completion handler indicating success or failure (for testing / internal logging).
    func resolveMobileWidget(
        clientKey: String,
        deviceId: String,
        targetURL: String,
        completion: ((Result<HTTPURLResponse, Error>) -> Void)? = nil
    ) {
        let endpointString = "\(baseURL)\(PoltioAPIClient.widgetEndpointPath)"
        guard let requestURL = URL(string: endpointString) else {
            print("[PoltioSDK] Error: Invalid API endpoint URL '\(endpointString)'.")
            completion?(.failure(URLError(.badURL)))
            return
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
            print("[PoltioSDK] Error: Failed to serialize request payload: \(error.localizedDescription)")
            completion?(.failure(error))
            return
        }

        let task = session.dataTask(with: request) { _, response, error in
            if let error = error {
                print("[PoltioSDK] Network request failed for '\(targetURL)': \(error.localizedDescription)")
                completion?(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                let invalidRespErr = URLError(.cannotParseResponse)
                print("[PoltioSDK] Error: Received non-HTTP response from server.")
                completion?(.failure(invalidRespErr))
                return
            }

            if (200 ... 299).contains(httpResponse.statusCode) {
                print("[PoltioSDK] resolveMobileWidget succeeded (Status: \(httpResponse.statusCode)) for URL: '\(targetURL)'")
                completion?(.success(httpResponse))
            } else {
                print("[PoltioSDK] resolveMobileWidget server returned status \(httpResponse.statusCode) for URL: '\(targetURL)'")
                completion?(.failure(URLError(.badServerResponse)))
            }
        }

        task.resume()
    }
}
