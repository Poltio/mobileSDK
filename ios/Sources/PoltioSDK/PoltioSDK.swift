import Foundation

/// Main entry point for the Poltio iOS SDK.
public final class PoltioSDK {
    
    /// Shared singleton instance of `PoltioSDK`.
    internal static let shared = PoltioSDK()
    
    private var _clientKey: String?
    private var _isInitialized: Bool = false
    private var _sdkId: String?
    private var _puid: String?
    
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
        queue.sync(flags: .barrier) {
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
        queue.sync {
            if let cached = self._puid {
                return cached
            }
            return UserDefaults.standard.string(forKey: PoltioSDK.puidStorageKey)
        }
    }
    
    internal init() {}
    
    #if DEBUG
    /// Resets the SDK state. Used exclusively for unit testing to prevent state pollution.
    internal func reset() {
        queue.sync(flags: .barrier) {
            self._clientKey = nil
            self._isInitialized = false
            self._puid = nil
            self._sdkId = nil
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
        return shared.configure(clientKey: clientKey)
    }
    
    /// Instance method to configure the SDK.
    @discardableResult
    internal func configure(clientKey: String) -> PoltioSDK {
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
    internal func identify(puid: String?) {
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
        }
    }
    
    // MARK: - Public Event Tracking API
    
    /// Tracks an in-app event with optional parameters.
    /// Automatically attaches `sdk_id` and `puid` (when available) to the event parameters.
    /// - Parameters:
    ///   - event: The event name (e.g. "ViewContent", "TrackConversion")
    ///   - params: Dictionary of event properties (e.g. ["url": "app://home"])
    public static func track(event: String, params: [String: Any]? = nil) {
        shared.track(event: event, params: params)
    }
    
    /// Instance method to track an in-app event.
    internal func track(event: String, params: [String: Any]? = nil) {
        let trimmedEvent = event.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEvent.isEmpty else {
            print("[PoltioSDK] Error: Event name cannot be empty.")
            return
        }
        
        guard isInitialized else {
            print("[PoltioSDK] Warning: track called before configuration. Call PoltioSDK.configure(clientKey:) first.")
            return
        }
        
        var enrichedParams: [String: Any] = params ?? [:]
        enrichedParams["sdk_id"] = sdkId
        if let currentPuid = puid {
            enrichedParams["puid"] = currentPuid
        }
        
        print("[PoltioSDK] Event tracked: '\(trimmedEvent)', params: \(enrichedParams)")
    }
}

