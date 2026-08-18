import Foundation

/// Main entry point for the Poltio iOS SDK.
public final class PoltioSDK {
    /// Shared singleton instance of `PoltioSDK`.
    public static let shared = PoltioSDK()

    private var _clientKey: String?
    private var _isInitialized: Bool = false
    private var _sdkId: String?
    private var _puid: String?
    private var _puidLoaded: Bool = false
    private var _currentViewRequestId: UInt64 = 0

    private let queue = DispatchQueue(label: "com.poltio.sdk", attributes: .concurrent)

    private static let sdkIdStorageKey = "com.poltio.sdk.sdk_id"
    private static let puidStorageKey = "com.poltio.sdk.puid"

    /// The client key configured for this SDK session.
    public var clientKey: String? {
        queue.sync { _clientKey }
    }

    /// Indicates whether the SDK has been configured.
    public var isInitialized: Bool {
        queue.sync { _isInitialized }
    }

    /// SDK-generated unique identifier (source of truth for device tracking).
    /// Generated automatically on first access and persisted in local storage.
    public var sdkId: String {
        if let existingId = queue.sync(execute: { _sdkId }) {
            return existingId
        }

        return queue.sync(flags: .barrier) {
            if let existingId = self._sdkId {
                return existingId
            }

            if let persistedId = UserDefaults.standard.string(forKey: PoltioSDK.sdkIdStorageKey), !persistedId.isEmpty {
                self._sdkId = persistedId
                return persistedId
            }

            let newId = UUID().uuidString
            UserDefaults.standard.set(newId, forKey: PoltioSDK.sdkIdStorageKey)
            self._sdkId = newId
            return newId
        }
    }

    /// Developer-provided optional user identifier (PUID).
    public var puid: String? {
        let (loaded, cached) = queue.sync { (self._puidLoaded, self._puid) }
        if loaded {
            return cached
        }

        return queue.sync(flags: .barrier) {
            if self._puidLoaded {
                return self._puid
            }

            let persisted = UserDefaults.standard.string(forKey: PoltioSDK.puidStorageKey)
            self._puid = persisted
            self._puidLoaded = true
            return persisted
        }
    }

    private var _apiClient: PoltioAPIClient?

    /// The API client instance used for backend requests.
    var apiClient: PoltioAPIClient {
        get {
            if let existing = queue.sync(execute: { _apiClient }) {
                return existing
            }
            return queue.sync(flags: .barrier) {
                if let existing = self._apiClient {
                    return existing
                }
                let client = PoltioAPIClient()
                self._apiClient = client
                return client
            }
        }
        set {
            queue.sync(flags: .barrier) {
                _apiClient = newValue
            }
        }
    }

    init() {}

    #if DEBUG
        /// Resets the SDK state. Used exclusively for unit testing to prevent state pollution.
        func reset() {
            queue.sync(flags: .barrier) {
                self._clientKey = nil
                self._isInitialized = false
                self._puid = nil
                self._puidLoaded = false
                self._sdkId = nil
                self._apiClient = nil
                UserDefaults.standard.removeObject(forKey: PoltioSDK.sdkIdStorageKey)
                UserDefaults.standard.removeObject(forKey: PoltioSDK.puidStorageKey)
            }
        }
    #endif

    // MARK: - Public Configuration API

    /// Configures the Poltio SDK with your publishable client key.
    /// - Parameter clientKey: Poltio client key (e.g. "poltio_test_pk...")
    /// - Returns: The configured shared instance.
    @discardableResult
    public static func configure(clientKey: String) -> PoltioSDK {
        shared.configure(clientKey: clientKey)
    }

    /// Instance method to configure the SDK.
    @discardableResult
    func configure(clientKey: String) -> PoltioSDK {
        let trimmedKey = clientKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedKey.isEmpty else {
            print("[PoltioSDK] Error: Client key cannot be empty.")
            return self
        }

        queue.sync(flags: .barrier) {
            self._clientKey = trimmedKey
            self._isInitialized = true
        }

        print("[PoltioSDK] Configured successfully (SDK ID: \(sdkId)).")
        return self
    }

    // MARK: - Public User Identification API

    /// Identifies the user with an optional developer-provided user identifier (PUID).
    /// - Parameter puid: Optional developer-provided unique user identifier (pass nil or empty string to clear).
    public static func identify(puid: String?) {
        shared.identify(puid: puid)
    }

    /// Instance method to set or clear developer-provided PUID.
    func identify(puid: String?) {
        let trimmedPuid = puid?.trimmingCharacters(in: .whitespacesAndNewlines)

        queue.sync(flags: .barrier) {
            if let validPuid = trimmedPuid, !validPuid.isEmpty {
                self._puid = validPuid
                UserDefaults.standard.set(validPuid, forKey: PoltioSDK.puidStorageKey)
                print("[PoltioSDK] Identified user with PUID: '\(validPuid)'.")
            } else {
                self._puid = nil
                UserDefaults.standard.removeObject(forKey: PoltioSDK.puidStorageKey)
                print("[PoltioSDK] Cleared PUID.")
            }
            self._puidLoaded = true
        }
    }

    // MARK: - Public Event Tracking API

    /// Tracks an in-app event with optional parameters.
    /// Automatically attaches `sdk_id` and `puid` (when available) to the event parameters.
    /// For `view` events, triggers backend widget resolution via `/sdk/mobile/v1/widget`.
    /// - Parameters:
    ///   - event: The event name (e.g. "view", "TrackConversion")
    ///   - params: Dictionary of event properties (e.g. ["url": "https://www.poltio.com/pdp"])
    public static func track(event: String, params: [String: Any]? = nil) {
        shared.track(event: event, params: params)
    }

    /// Instance method to track an in-app event.
    func track(event: String, params: [String: Any]? = nil) {
        let trimmedEvent = event.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEvent.isEmpty else {
            print("[PoltioSDK] Error: Event name cannot be empty.")
            return
        }

        guard isInitialized, let key = clientKey else {
            print("[PoltioSDK] Warning: track called before configuration. Call PoltioSDK.configure(clientKey:) first.")
            return
        }

        var enrichedParams: [String: Any] = params ?? [:]
        let currentSdkId = sdkId
        enrichedParams["sdk_id"] = currentSdkId
        if let currentPuid = puid {
            enrichedParams["puid"] = currentPuid
        }

        print("[PoltioSDK] Event tracked: '\(trimmedEvent)', params: \(enrichedParams)")

        if isViewEvent(trimmedEvent) {
            let rawUrl: String = if let value = params?["url"] ?? params?["screen"] ?? params?["page"] {
                (value as? String) ?? (value as? URL)?.absoluteString ?? ""
            } else {
                ""
            }
            let targetURL = PoltioSDK.sanitizeOrFormatURL(rawUrl)
            let activePuid = puid

            let thisRequestId: UInt64 = queue.sync(flags: .barrier) {
                self._currentViewRequestId &+= 1
                return self._currentViewRequestId
            }

            #if canImport(UIKit)
                PoltioOverlayManager.shared.hideTrigger()
            #endif

            apiClient.resolveMobileWidget(
                clientKey: key,
                deviceId: currentSdkId,
                targetURL: targetURL
            ) { [weak self] result in
                guard let self else { return }

                let isLatest: Bool = queue.sync {
                    thisRequestId == self._currentViewRequestId
                }

                guard isLatest else {
                    print("[PoltioSDK] Ignoring outdated widget resolution result for '\(targetURL)' (newer screen was already requested).")
                    return
                }

                switch result {
                case let .success(widgetResponse):
                    #if canImport(UIKit)
                        PoltioOverlayManager.shared.showTrigger(widget: widgetResponse, puid: activePuid)
                    #endif
                case let .failure(error):
                    #if canImport(UIKit)
                        PoltioOverlayManager.shared.hideTrigger()
                    #endif
                    print("[PoltioSDK] Widget resolution skipped/failed for '\(targetURL)': \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Internal Helpers

    /// Checks whether an event name corresponds to a view event.
    func isViewEvent(_ eventName: String) -> Bool {
        let lower = eventName.lowercased()
        return lower == "view" || lower == "viewcontent" || lower == "view_content"
    }

    /// Sanitizes or formats a raw URL string to guarantee it contains a scheme and host required by the API.
    static func sanitizeOrFormatURL(_ rawInput: String) -> String {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "https://app.poltio.com/default"
        }

        if trimmed.contains("://") {
            if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let parsed = URL(string: encoded), parsed.scheme != nil, parsed.host != nil
            {
                return encoded
            }
            return trimmed
        }

        if let parsed = URL(string: trimmed), parsed.scheme != nil, parsed.host != nil {
            return trimmed
        }

        let cleanPath = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "https://app.poltio.com/\(cleanPath)"
    }
}
