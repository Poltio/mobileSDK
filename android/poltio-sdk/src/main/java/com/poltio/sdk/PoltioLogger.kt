package com.poltio.sdk

import android.util.Log

/** Verbosity level of internal SDK logging. */
enum class PoltioLogLevel(val rawValue: Int) : Comparable<PoltioLogLevel> {
    /** Disables all SDK logging. */
    NONE(0),

    /** Logs only critical errors and failures. */
    ERROR(1),

    /** Logs warnings and critical errors. */
    WARNING(2),

    /** Logs informational events, state changes, and errors (default). */
    INFO(3),

    /** Logs detailed debug traces, network payloads, and internal transitions. */
    DEBUG(4),
}

/**
 * Internal thread-safe logger for the Poltio SDK. This is the single sanctioned sink for SDK
 * output — no other SDK source file should call `Log.*`/`println` directly.
 */
object PoltioLogger {
    private const val TAG = "PoltioSDK"

    @Volatile
    var logLevel: PoltioLogLevel = PoltioLogLevel.INFO

    /** Logs a debug message if the active log level is `.DEBUG`. Message is lazily built. */
    fun debug(message: () -> String) = log(PoltioLogLevel.DEBUG, message)

    /** Logs an informational message if the active log level is `.INFO` or higher. */
    fun info(message: () -> String) = log(PoltioLogLevel.INFO, message)

    /** Logs a warning message if the active log level is `.WARNING` or higher. */
    fun warning(message: () -> String) = log(PoltioLogLevel.WARNING, message)

    /** Logs an error message if the active log level is `.ERROR` or higher. */
    fun error(message: () -> String) = log(PoltioLogLevel.ERROR, message)

    /** Logs a message at the specified level if allowed by the active log level. */
    fun log(level: PoltioLogLevel, message: () -> String) {
        if (level == PoltioLogLevel.NONE || level > logLevel) return
        val text = message()
        when (level) {
            PoltioLogLevel.DEBUG -> Log.d(TAG, text)
            PoltioLogLevel.INFO -> Log.i(TAG, text)
            PoltioLogLevel.WARNING -> Log.w(TAG, text)
            PoltioLogLevel.ERROR -> Log.e(TAG, text)
            PoltioLogLevel.NONE -> Unit
        }
    }
}
