package com.poltio.exampleapp.services

import androidx.compose.runtime.mutableStateListOf
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

object PoltioSDKPlaceholder {
    val logs = mutableStateListOf<SDKLogEntry>()

    init {
        log(LogType.INFO, "PoltioSDK initialized for TechStore Android app")
    }

    fun trackScreen(screenName: String) {
        log(LogType.SCREEN_TRACK, "Screen view registered: $screenName")
    }

    fun trackEvent(eventName: String, details: String) {
        log(LogType.EVENT, "Event fired: $eventName -> $details")
    }

    fun triggerWidget(widgetName: String, url: String) {
        log(LogType.TRIGGER, "Poltio Overlay Widget opened: $widgetName ($url)")
    }

    private fun log(type: LogType, message: String) {
        val sdf = SimpleDateFormat("HH:mm:ss", Locale.getDefault())
        val timestamp = sdf.format(Date())
        logs.add(0, SDKLogEntry(timestamp, type, message))
    }
}
