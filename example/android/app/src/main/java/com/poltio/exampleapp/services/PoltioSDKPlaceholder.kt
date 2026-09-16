package com.poltio.exampleapp.services

import androidx.compose.runtime.mutableStateListOf
import com.poltio.sdk.PoltioSDK
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

data class SDKLogEntry(
    val timestamp: String,
    val type: LogType,
    val message: String
)

enum class LogType {
    INFO, SCREEN_TRACK, EVENT, TRIGGER
}

/**
 * Thin bridge between the TechStore UI and the real [PoltioSDK], additionally mirroring every
 * call into an in-memory log feed for the Log Inspector screen (`PoltioSDK` itself only logs to
 * Logcat, which isn't visible from within the app).
 */
object PoltioSDKPlaceholder {
    val logs = mutableStateListOf<SDKLogEntry>()

    init {
        log(LogType.INFO, "PoltioSDK initialized for TechStore Android app")
    }

    fun trackScreen(screenName: String, url: String) {
        PoltioSDK.track(event = "view", params = mapOf("url" to url))
        log(LogType.SCREEN_TRACK, "Screen view registered: $screenName ($url)")
    }

    fun trackEvent(eventName: String, details: String) {
        PoltioSDK.track(event = eventName, params = mapOf("details" to details))
        log(LogType.EVENT, "Event fired: $eventName -> $details")
    }

    fun triggerWidget(widgetName: String, url: String) {
        // Poltio triggers are resolved and shown automatically from `trackScreen`'s "view" events —
        // this button exists to show the ask ("help me choose") in context; it doesn't call the SDK
        // directly, mirroring the iOS example app's equivalent button.
        log(LogType.TRIGGER, "Poltio Overlay Widget opened: $widgetName ($url)")
    }

    private fun log(type: LogType, message: String) {
        val sdf = SimpleDateFormat("HH:mm:ss", Locale.getDefault())
        val timestamp = sdf.format(Date())
        logs.add(0, SDKLogEntry(timestamp, type, message))
    }
}
