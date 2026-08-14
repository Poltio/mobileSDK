import Foundation

/// Main entry point for the Poltio iOS SDK.
public final class PoltioSDK {
    
    /// Shared singleton instance of `PoltioSDK`.
    internal static let shared = PoltioSDK()
    
    private var _clientKey: String?
    private var _isInitialized: Bool = false
    private let queue = DispatchQueue(label: "com.poltio.sdk", attributes: .concurrent)
    
    /// The client key configured for this SDK session.
    public var clientKey: String? {
        queue.sync { _clientKey }
    }
    
    /// Indicates whether the SDK has been configured.
    public var isInitialized: Bool {
        queue.sync { _isInitialized }
    }
    
    internal init() {}
    
    #if DEBUG
    /// Resets the SDK state. Used exclusively for unit testing to prevent state pollution.
    internal func reset() {
        queue.sync(flags: .barrier) {
            self._clientKey = nil
            self._isInitialized = false
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
        
        print("[PoltioSDK] Configured successfully.")
        return self
    }
    
    // MARK: - Public Event Tracking API
    
    /// Tracks an in-app event with optional parameters.
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
        
        let safeParams = params ?? [:]
        print("[PoltioSDK] Event tracked: '\(trimmedEvent)', params: \(safeParams)")
    }
}
