import Foundation

/// Backend API environment the SDK talks to.
///
/// By default the SDK auto-detects the environment from the host app's active build configuration
/// (the standard iOS convention): Debug builds resolve to `.stage`, Release builds (including TestFlight
/// and App Store archives) resolve to `.production`. This is more reliable than simulator-vs-device
/// detection, since it also does the right thing for Release builds run on Simulator and Debug builds
/// run on physical devices. Developers can override this via `PoltioSDK.configure(clientKey:useStage:)`.
enum PoltioEnvironment: Equatable {
    case production
    case stage

    /// Base URL for API requests made in this environment.
    var baseURL: String {
        switch self {
        case .production: PoltioAPIClient.productionBaseURL
        case .stage: PoltioAPIClient.stageBaseURL
        }
    }

    /// Automatically resolves the environment from the host app's build configuration.
    static var automatic: PoltioEnvironment {
        #if DEBUG
            .stage
        #else
            .production
        #endif
    }

    /// Resolves the environment from a developer-provided override, falling back to automatic
    /// detection (Debug -> stage, Release -> production) when `useStage` is `nil`.
    static func resolve(useStage: Bool?) -> PoltioEnvironment {
        guard let useStage else { return .automatic }
        return useStage ? .stage : .production
    }
}
