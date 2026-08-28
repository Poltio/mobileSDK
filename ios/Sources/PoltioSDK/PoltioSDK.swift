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

    private var _activeWidgetTask: URLSessionDataTask?
    private let _widgetCache = PoltioWidgetCache()

    private let queue = DispatchQueue(label: "com.poltio.sdk", attributes: .concurrent)

    private static let sdkIdStorageKey = "com.poltio.sdk.sdk_id"
    private static let puidStorageKey = "com.poltio.sdk.puid"

    /// The active log level for the SDK.
    public static var logLevel: PoltioLogLevel {
        get { PoltioLogger.logLevel }
        set { PoltioLogger.logLevel = newValue }
    }

    /// Time-to-live in seconds for widget resolution in-memory cache (default: 300 seconds / 5 minutes).
    public static var cacheTTL: TimeInterval {
        get { shared.cacheTTL }
        set { shared.cacheTTL = newValue }
    }

    /// Instance property for cache TTL.
    public var cacheTTL: TimeInterval {
        get { _widgetCache.defaultTTL }
        set { _widgetCache.defaultTTL = newValue }
    }

    /// Maximum number of widget responses retained in the in-memory cache (default: 100).
    public static var cacheLimit: Int {
        get { shared.cacheLimit }
        set { shared.cacheLimit = newValue }
    }

    /// Instance property for cache item limit.
    public var cacheLimit: Int {
        get { _widgetCache.countLimit }
        set { _widgetCache.countLimit = newValue }
    }

    /// Clears the in-memory widget resolution cache.
    public static func clearCache() {
        shared.clearCache()
    }

    /// Instance method to clear the in-memory widget cache.
    public func clearCache() {
        _widgetCache.clear()
    }

    /// Internal access to the widget cache (for unit testing).
    var widgetCache: PoltioWidgetCache {
        _widgetCache
    }

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
                self._activeWidgetTask?.cancel()
                self._activeWidgetTask = nil
                self._currentViewRequestId = 0
                self._widgetCache.clear()
                self._widgetCache.defaultTTL = 300.0
                self._widgetCache.countLimit = 100
                UserDefaults.standard.removeObject(forKey: PoltioSDK.sdkIdStorageKey)
                UserDefaults.standard.removeObject(forKey: PoltioSDK.puidStorageKey)
            }
            PoltioLogger.logLevel = .info
        }
    #endif

    // MARK: - Public Configuration API

    /// Configures the Poltio SDK with your publishable client key and optional log level.
    /// - Parameters:
    ///   - clientKey: Poltio client key (e.g. "poltio_test_pk...")
    ///   - logLevel: Verbosity level of console logging (defaults to `.info`).
    /// - Returns: The configured shared instance.
    @discardableResult
    public static func configure(
        clientKey: String,
        logLevel: PoltioLogLevel = .info
    ) -> PoltioSDK {
        shared.configure(clientKey: clientKey, logLevel: logLevel)
    }

    /// Instance method to configure the SDK.
    @discardableResult
    func configure(
        clientKey: String,
        logLevel: PoltioLogLevel = .info
    ) -> PoltioSDK {
        let trimmedKey = clientKey.trimmingCharacters(in: .whitespacesAndNewlines)
        PoltioLogger.logLevel = logLevel

        guard !trimmedKey.isEmpty else {
            PoltioLogger.error("Client key cannot be empty.")
            return self
        }

        queue.sync(flags: .barrier) {
            self._clientKey = trimmedKey
            self._isInitialized = true
        }

        PoltioLogger.info("Configured successfully (SDK ID: \(sdkId)).")
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
                PoltioLogger.info("Identified user with PUID: '\(validPuid)'.")
            } else {
                self._puid = nil
                UserDefaults.standard.removeObject(forKey: PoltioSDK.puidStorageKey)
                PoltioLogger.info("Cleared PUID.")
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
            PoltioLogger.error("Event name cannot be empty.")
            return
        }

        guard isInitialized, let key = clientKey else {
            PoltioLogger.warning("track called before configuration. Call PoltioSDK.configure(clientKey:) first.")
            return
        }

        var enrichedParams: [String: Any] = params ?? [:]
        let currentSdkId = sdkId
        enrichedParams["sdk_id"] = currentSdkId
        if let currentPuid = puid {
            enrichedParams["puid"] = currentPuid
        }

        PoltioLogger.info("Event tracked: '\(trimmedEvent)', params: \(enrichedParams)")

        if isViewEvent(trimmedEvent) {
            let rawUrl: String = if let value = params?["url"] ?? params?["screen"] ?? params?["page"] {
                (value as? String) ?? (value as? URL)?.absoluteString ?? ""
            } else {
                ""
            }
            let targetURL = PoltioSDK.sanitizeOrFormatURL(rawUrl)
            let activePuid = puid

            // Check in-memory cache first
            if let cachedResult = _widgetCache.get(for: targetURL) {
                queue.sync(flags: .barrier) {
                    self._activeWidgetTask?.cancel()
                    self._activeWidgetTask = nil
                    self._currentViewRequestId &+= 1
                }

                switch cachedResult {
                case let .widget(widgetResponse):
                    PoltioLogger.debug("Using cached widget response for '\(targetURL)' (public_id: \(widgetResponse.publicId)).")
                    #if canImport(UIKit)
                        PoltioOverlayManager.shared.showTrigger(widget: widgetResponse, puid: activePuid)
                    #endif
                case .noWidget:
                    PoltioLogger.debug("Using cached negative widget resolution for '\(targetURL)' (no widget).")
                    #if canImport(UIKit)
                        PoltioOverlayManager.shared.hideTrigger()
                    #endif
                }
                return
            }

            // Cancel any in-flight widget resolution task for previous screen
            queue.sync(flags: .barrier) {
                self._activeWidgetTask?.cancel()
                self._activeWidgetTask = nil
                self._currentViewRequestId &+= 1
            }

            let thisRequestId: UInt64 = queue.sync { self._currentViewRequestId }

            let task = apiClient.resolveMobileWidget(
                clientKey: key,
                deviceId: currentSdkId,
                targetURL: targetURL
            ) { [weak self] result in
                guard let self else { return }

                let isLatest: Bool = queue.sync {
                    thisRequestId == self._currentViewRequestId
                }

                guard isLatest else {
                    PoltioLogger.debug("Ignoring outdated widget resolution result for '\(targetURL)' (newer screen was already requested).")
                    return
                }

                switch result {
                case let .success(widgetResponse):
                    _widgetCache.set(result: .widget(widgetResponse), for: targetURL)
                    #if canImport(UIKit)
                        PoltioOverlayManager.shared.showTrigger(widget: widgetResponse, puid: activePuid)
                    #endif
                case let .failure(error):
                    #if canImport(UIKit)
                        PoltioOverlayManager.shared.hideTrigger()
                    #endif

                    if (error as? URLError)?.code == .resourceUnavailable {
                        _widgetCache.set(result: .noWidget, for: targetURL)
                    }

                    if (error as? URLError)?.code != .cancelled, (error as NSError).code != NSURLErrorCancelled {
                        PoltioLogger.warning("Widget resolution skipped/failed for '\(targetURL)': \(error.localizedDescription)")
                    }
                }
            }

            queue.sync(flags: .barrier) {
                if thisRequestId == self._currentViewRequestId {
                    self._activeWidgetTask = task
                } else {
                    // A newer screen already superseded this request before it could be stored;
                    // cancel it explicitly instead of letting it run to completion unused.
                    task?.cancel()
                }
            }
        }
    }

    // MARK: - Public Widget Event Bridge

    /// Optional callback invoked when the widget WebView emits a bridge event (e.g. "close", "complete",
    /// "leadSubmit"). The widget page communicates via
    /// `window.webkit.messageHandlers.poltioNative.postMessage({ event: "...", data: { ... } })`.
    /// Delivered on the main thread. Set this once, e.g. alongside `configure(clientKey:)`.
    public static var onWidgetEvent: ((_ event: String, _ data: [String: Any]?) -> Void)?

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
            // Decide whether encoding is needed by inspecting the actual characters present, not by
            // trusting `URL(string:)` to reject invalid input — Foundation's URL parser is lenient enough
            // to happily parse raw, unescaped spaces, so a "does it parse?" check can't distinguish
            // "already valid" from "needs encoding".
            let needsEncoding = trimmed.rangeOfCharacter(from: CharacterSet.poltioURLAllowed.inverted) != nil
            guard needsEncoding else {
                // Already well-formed (including already percent-encoded). Re-encoding here would
                // double-encode existing '%XX' sequences (turning "%20" into "%2520") and corrupt the
                // target URL sent to the widget resolution endpoint.
                return trimmed
            }

            // Encode only the characters that actually need it, leaving existing URL syntax
            // (scheme/path/query/fragment delimiters and already-escaped '%XX' sequences) untouched.
            if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .poltioURLAllowed),
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

private extension CharacterSet {
    /// Broader than `.urlQueryAllowed`: covers the full set of characters that are valid, unescaped,
    /// anywhere in a URL (scheme, path, query, or fragment), so a fallback encoding pass doesn't
    /// escape delimiters like ':', '/', '#', '?' or already-valid '%' escape sequences.
    static let poltioURLAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~:/?#[]@!$&'()*+,;=%")
        return set
    }()
}
