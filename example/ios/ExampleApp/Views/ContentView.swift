import PoltioSDK
import SwiftUI

struct SDKStatusView: View {
    @State private var identifiedUserId: String = ""
    @State private var eventStatusMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Poltio SDK Status")) {
                    HStack {
                        Text("Initialization")
                        Spacer()
                        HStack(spacing: 6) {
                            Image(systemName: PoltioSDK.shared.isInitialized ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(PoltioSDK.shared.isInitialized ? .green : .red)
                            Text(PoltioSDK.shared.isInitialized ? "Initialized" : "Not Initialized")
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Text("SDK ID")
                        Spacer()
                        Text(PoltioSDK.shared.sdkId)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    if let clientKey = PoltioSDK.shared.clientKey {
                        HStack {
                            Text("Client Key")
                            Spacer()
                            Text(clientKey)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Text("PUID")
                        Spacer()
                        Text(PoltioSDK.shared.puid ?? "None")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("User Identification")) {
                    HStack {
                        TextField("Enter User ID / PUID", text: $identifiedUserId)
                        Button("Identify") {
                            guard !identifiedUserId.isEmpty else { return }
                            PoltioSDK.identify(puid: identifiedUserId)
                            eventStatusMessage = "Identified user: \(identifiedUserId)"
                        }
                        .disabled(identifiedUserId.isEmpty)
                    }

                    if PoltioSDK.shared.puid != nil {
                        Button("Clear User (Logout)", role: .destructive) {
                            PoltioSDK.identify(puid: nil)
                            identifiedUserId = ""
                            eventStatusMessage = "Cleared PUID"
                        }
                    }
                }

                Section(header: Text("Manual Event Tracking")) {
                    Button("Track Custom View Event") {
                        PoltioSDK.track(event: "view", params: ["url": "example://manual_track"])
                        eventStatusMessage = "Tracked 'view' event for 'example://manual_track'"
                    }

                    Button("Track Conversion Event") {
                        PoltioSDK.track(event: "TrackConversion", params: ["value": 99.99, "currency": "USD"])
                        eventStatusMessage = "Tracked 'TrackConversion' event"
                    }
                }

                if let message = eventStatusMessage {
                    Section(header: Text("Last Action")) {
                        Text(message)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Poltio SDK")
        }
    }
}

enum AppTab: Int, CaseIterable, Identifiable {
    case shop = 0
    case phones = 1
    case tvs = 2
    case laptops = 3
    case sdkInfo = 4

    var id: Int {
        rawValue
    }
}

struct ContentView: View {
    @State private var selectedTab: AppTab = .shop

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("Shop", systemImage: "storefront.fill")
                }
                .tag(AppTab.shop)

            NavigationStack {
                PLPView(category: .phones)
            }
            .tabItem {
                Label("Phones", systemImage: "iphone")
            }
            .tag(AppTab.phones)

            NavigationStack {
                PLPView(category: .tvs)
            }
            .tabItem {
                Label("TVs", systemImage: "tv")
            }
            .tag(AppTab.tvs)

            NavigationStack {
                PLPView(category: .laptops)
            }
            .tabItem {
                Label("Laptops", systemImage: "laptopcomputer")
            }
            .tag(AppTab.laptops)

            SDKStatusView()
                .tabItem {
                    Label("SDK Info", systemImage: "tag.fill")
                }
                .tag(AppTab.sdkInfo)
        }
        .onChange(of: selectedTab) { newTab in
            switch newTab {
            case .shop:
                PoltioSDK.track(event: "view", params: ["url": "example://home"])
            case .phones:
                PoltioSDK.track(event: "view", params: ["url": "example://plp/phones"])
            case .tvs:
                PoltioSDK.track(event: "view", params: ["url": "example://plp/tvs"])
            case .laptops:
                PoltioSDK.track(event: "view", params: ["url": "example://plp/laptops"])
            case .sdkInfo:
                PoltioSDK.track(event: "view", params: ["url": "example://sdk-info"])
            }
        }
    }
}
