package com.poltio.sdk.ui

/**
 * Fires when the user taps/scrolls outside the active trigger's bounds, detected by
 * [PoltioOverlayManager]'s passthrough overlay. Mirrors the iOS SDK's
 * `PoltioSDK.hostDidScroll` `NotificationCenter` broadcast, which the pill trigger uses to
 * auto-collapse when the user interacts with the host screen behind it.
 */
internal object PoltioHostInteractionBus {
    private val listeners = mutableSetOf<() -> Unit>()

    fun addListener(listener: () -> Unit) {
        synchronized(listeners) { listeners.add(listener) }
    }

    fun removeListener(listener: () -> Unit) {
        synchronized(listeners) { listeners.remove(listener) }
    }

    fun notifyOutsideInteraction() {
        val snapshot = synchronized(listeners) { listeners.toList() }
        snapshot.forEach { it.invoke() }
    }
}
