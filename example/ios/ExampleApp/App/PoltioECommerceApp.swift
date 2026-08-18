import PoltioSDK
import SwiftUI

@main
struct PoltioECommerceApp: App {
    init() {
        // Initialize Poltio TAG SDK
        let clientKey = ProcessInfo.processInfo.environment["POLTIO_CLIENT_KEY"] ?? "poltio_test_pk_12345"
        PoltioSDK.configure(clientKey: clientKey)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
