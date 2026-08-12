import SwiftUI

struct DebugLogsView: View {
    @ObservedObject var sdk = PoltioSDKPlaceholder.shared
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Current Active Screen")) {
                    HStack {
                        Image(systemName: "circle.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                        Text(sdk.currentScreen ?? "None")
                            .font(.headline)
                    }
                }
                
                Section(header: Text("Screen View Log History (\(sdk.trackedScreensHistory.count))")) {
                    if sdk.trackedScreensHistory.isEmpty {
                        Text("No screens tracked yet")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(sdk.trackedScreensHistory.enumerated().reversed()), id: \.offset) { index, screen in
                            HStack {
                                Text("\(index + 1).")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 24, alignment: .leading)
                                Text(screen)
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Poltio TAG Logs")
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Shop", systemImage: "storefront.fill")
                }
            
            NavigationStack {
                PLPView(category: .phones)
            }
            .tabItem {
                Label("Phones", systemImage: "iphone")
            }
            
            NavigationStack {
                PLPView(category: .tvs)
            }
            .tabItem {
                Label("TVs", systemImage: "tv")
            }
            
            NavigationStack {
                PLPView(category: .laptops)
            }
            .tabItem {
                Label("Laptops", systemImage: "laptopcomputer")
            }
            
            DebugLogsView()
                .tabItem {
                    Label("SDK Logs", systemImage: "tag.fill")
                }
        }
    }
}
