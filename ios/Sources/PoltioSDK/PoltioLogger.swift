import Foundation

/// Represents the verbosity level of internal SDK logging.
@objc public enum PoltioLogLevel: Int, Comparable {
    /// Disables all SDK console logging.
    case none = 0
    /// Logs only critical errors and failures.
    case error = 1
    /// Logs warnings and critical errors.
    case warning = 2
    /// Logs informational events, state changes, and errors (default).
    case info = 3
    /// Logs detailed debug traces, network payloads, and internal transitions.
    case debug = 4

    public static func < (lhs: PoltioLogLevel, rhs: PoltioLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Internal thread-safe logger for Poltio SDK.
public enum PoltioLogger {
    private static let lock = NSLock()
    private static var _logLevel: PoltioLogLevel = .info

    /// The current active log level for the SDK.
    public static var logLevel: PoltioLogLevel {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _logLevel
        }
        set {
            lock.lock()
            _logLevel = newValue
            lock.unlock()
        }
    }

    /// Logs a debug message if the active log level is `.debug`.
    public static func debug(_ message: @autoclosure () -> String) {
        log(.debug, message())
    }

    /// Logs an informational message if the active log level is `.info` or higher.
    public static func info(_ message: @autoclosure () -> String) {
        log(.info, message())
    }

    /// Logs a warning message if the active log level is `.warning` or higher.
    public static func warning(_ message: @autoclosure () -> String) {
        log(.warning, message())
    }

    /// Logs an error message if the active log level is `.error` or higher.
    public static func error(_ message: @autoclosure () -> String) {
        log(.error, message())
    }

    /// Logs a message at the specified level if allowed by the active log level.
    public static func log(_ level: PoltioLogLevel, _ message: @autoclosure () -> String) {
        guard level != .none, level <= logLevel else { return }
        print("[PoltioSDK] \(message())")
    }
}
