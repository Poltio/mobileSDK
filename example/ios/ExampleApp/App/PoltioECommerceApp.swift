import SwiftUI

@main
struct PoltioECommerceApp: App {
    init() {
        // Initialize Poltio TAG SDK
        PoltioSDKPlaceholder.configure(apiKey: "POLTIO_DEMO_KEY")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
