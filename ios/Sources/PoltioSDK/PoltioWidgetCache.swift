import Foundation

/// Cached outcome of a widget resolution request for a target URL.
public enum CachedWidgetResult: Equatable {
    /// Successfully resolved widget metadata.
    case widget(PoltioWidgetResponse)
    /// Explicitly verified that no widget is configured for this URL (404 Not Found).
    case noWidget
}

/// Thread-safe in-memory cache entry with expiration timestamp.
final class PoltioCacheEntry: NSObject {
    let result: CachedWidgetResult
    let expirationDate: Date

    init(result: CachedWidgetResult, ttl: TimeInterval) {
        self.result = result
        expirationDate = Date().addingTimeInterval(ttl)
    }

    var isExpired: Bool {
        Date() >= expirationDate
    }
}

/// Lightweight, in-memory ephemeral cache manager for widget resolutions.
/// Automatically limits memory footprint via `NSCache` and expires entries after the configured TTL.
final class PoltioWidgetCache {
    private let cache = NSCache<NSString, PoltioCacheEntry>()
    private let lock = NSLock()
    private var _defaultTTL: TimeInterval

    /// Default Time-To-Live in seconds for cached widget responses (default is 300 seconds / 5 minutes).
    var defaultTTL: TimeInterval {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _defaultTTL
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _defaultTTL = newValue
        }
    }

    /// Maximum number of items retained in the cache before older items are evicted (default is 100).
    var countLimit: Int {
        get { cache.countLimit }
        set { cache.countLimit = newValue }
    }

    /// Initializes a new widget cache with specified default TTL and item count limit.
    /// - Parameters:
    ///   - defaultTTL: Cache duration in seconds (defaults to 300.0s / 5 minutes).
    ///   - countLimit: Maximum number of entries (defaults to 100).
    init(defaultTTL: TimeInterval = 300.0, countLimit: Int = 100) {
        _defaultTTL = defaultTTL
        cache.countLimit = countLimit
    }

    /// Retrieves the cached widget result for the specified URL if present and unexpired.
    /// - Parameter url: The target URL string.
    /// - Returns: The cached `CachedWidgetResult`, or `nil` on cache miss / expiration.
    func get(for url: String) -> CachedWidgetResult? {
        let ttl = defaultTTL
        guard ttl > 0 else { return nil }

        let key = url as NSString
        guard let entry = cache.object(forKey: key) else {
            return nil
        }

        if entry.isExpired {
            cache.removeObject(forKey: key)
            PoltioLogger.debug("Cache entry expired for '\(url)'.")
            return nil
        }

        return entry.result
    }

    /// Stores a widget resolution outcome in the cache.
    /// - Parameters:
    ///   - result: The resolution outcome (`.widget` or `.noWidget`).
    ///   - url: The target URL string.
    ///   - ttl: Optional override TTL in seconds (uses `defaultTTL` if nil).
    func set(result: CachedWidgetResult, for url: String, ttl: TimeInterval? = nil) {
        let effectiveTTL = ttl ?? defaultTTL
        guard effectiveTTL > 0 else { return }

        let entry = PoltioCacheEntry(result: result, ttl: effectiveTTL)
        cache.setObject(entry, forKey: url as NSString)
        PoltioLogger.debug("Cached widget resolution for '\(url)' (TTL: \(Int(effectiveTTL))s).")
    }

    /// Removes the cached entry for a specific URL.
    /// - Parameter url: The target URL string.
    func remove(for url: String) {
        cache.removeObject(forKey: url as NSString)
    }

    /// Clears all entries from the in-memory cache.
    func clear() {
        cache.removeAllObjects()
        PoltioLogger.debug("Widget cache cleared.")
    }
}
