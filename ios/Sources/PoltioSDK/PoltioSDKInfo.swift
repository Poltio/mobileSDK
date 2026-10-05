import Foundation

/// Static build information about the SDK, sent to the Poltio API on every request.
enum PoltioSDKInfo {
    /// Semantic version of this SDK build. Kept in sync with the release tag by
    /// `scripts/bump-version.sh` (`make version VERSION=x.y.z`).
    static let version = "1.0.0"

    /// Platform identifier reported alongside `version`.
    static let platform = "ios"
}
