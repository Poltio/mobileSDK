import Foundation
import os.log

/// Represents the verbosity level of internal SDK logging.
@objc public enum PoltioLogLevel: Int, Comparable {
    /// Disables all SDK console logging.
    case none = 0
    /// Logs only critical errors and failures.
    case error = 1
    /// Logs warnings and critical errors (default).
    case warning = 2
    /// Logs informational events, state changes, warnings, and errors.
    case info = 3
    /// Logs detailed debug traces, network payloads, and internal transitions.
    case debug = 4

    public static func < (lhs: PoltioLogLevel, rhs: PoltioLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Internal thread-safe logger for Poltio SDK. Writes through the unified logging system (`os_log`,
/// subsystem `com.poltio.sdk`), so output shows up in the Xcode console as well as Console.app and
/// `log stream`, and can be filtered by subsystem.
enum PoltioLogger {
    private static let lock = NSLock()
    private static var _logLevel: PoltioLogLevel = .warning
    private static let osLog = OSLog(subsystem: "com.poltio.sdk", category: "PoltioSDK")

    /// The current active log level for the SDK.
    static var logLevel: PoltioLogLevel {
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
    static func debug(_ message: @autoclosure () -> String) {
        log(.debug, message())
    }

    /// Logs an informational message if the active log level is `.info` or higher.
    static func info(_ message: @autoclosure () -> String) {
        log(.info, message())
    }

    /// Logs a warning message if the active log level is `.warning` or higher.
    static func warning(_ message: @autoclosure () -> String) {
        log(.warning, message())
    }

    /// Logs an error message if the active log level is `.error` or higher.
    static func error(_ message: @autoclosure () -> String) {
        log(.error, message())
    }

    /// Logs a message at the specified level if allowed by the active log level.
    static func log(_ level: PoltioLogLevel, _ message: @autoclosure () -> String) {
        guard level != .none, level <= logLevel else { return }
        let type: OSLogType = switch level {
        case .debug: .debug
        case .info: .info
        case .warning: .default
        case .error, .none: .error
        }
        // Messages are only built once they pass the level gate above, and the host app decides
        // what's emitted via `logLevel` — so mark them public rather than letting the system redact
        // them as `<private>` outside of an attached debugger.
        os_log("[PoltioSDK] %{public}@", log: osLog, type: type, message())
    }
}
