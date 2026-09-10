import Foundation

/// Persists explicit user dismissals of the pill/box "remember for N hours" close button
/// (`pillCloseRememberDuration` / `boxCloseRememberDuration`), so a widget the user explicitly closed
/// doesn't reappear until the remember window elapses. Mirrors the `UserDefaults`-backed persistence
/// pattern already used for `sdkId`/`puid` in `PoltioSDK`.
enum PoltioTriggerDismissalStore {
    private static let storageKey = "com.poltio.sdk.trigger_dismissals"

    /// Returns whether `publicId` is currently within an active "remember" dismissal window.
    static func isDismissed(publicId: String, now: Date = Date()) -> Bool {
        guard let dismissedUntil = load()[publicId] else {
            return false
        }
        return now.timeIntervalSince1970 < dismissedUntil
    }

    /// Records that `publicId` was explicitly closed; it will be suppressed for `hours` from now.
    static func recordDismissal(publicId: String, hours: Double, now: Date = Date()) {
        guard hours > 0 else { return }
        var stored = load()
        stored[publicId] = now.timeIntervalSince1970 + hours * 3600
        save(stored)
    }

    #if DEBUG
        /// Clears all persisted dismissals. Used exclusively for unit testing.
        static func reset() {
            UserDefaults.standard.removeObject(forKey: storageKey)
        }
    #endif

    private static func load() -> [String: TimeInterval] {
        UserDefaults.standard.dictionary(forKey: storageKey) as? [String: TimeInterval] ?? [:]
    }

    private static func save(_ dict: [String: TimeInterval]) {
        UserDefaults.standard.set(dict, forKey: storageKey)
    }
}
