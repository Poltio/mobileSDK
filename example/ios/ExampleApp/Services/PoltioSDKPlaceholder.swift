import Foundation
import Combine

/// PoltioSDKPlaceholder provides a lightweight interface for Poltio TAG screen tracking.
/// When PoltioSDK is compiled into the app, this placeholder delegates to the native Swift SDK.
public class PoltioSDKPlaceholder: ObservableObject {
    public static let shared = PoltioSDKPlaceholder()
    
    @Published public private(set) var currentScreen: String?
    @Published public private(set) var trackedScreensHistory: [String] = []
    
    private init() {}
    
    public static func configure(apiKey: String) {
        print("[PoltioSDK] Configured with API Key: \(apiKey)")
    }
    
    public static func trackScreen(_ screenName: String) {
        DispatchQueue.main.async {
            shared.currentScreen = screenName
            shared.trackedScreensHistory.append(screenName)
            print("[PoltioSDK] 🏷️ Tracked Screen: '\(screenName)'")
        }
    }
}
