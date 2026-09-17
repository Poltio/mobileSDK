package com.poltio.sdk.ui

import android.app.Activity
import android.view.MotionEvent
import android.view.Window
import kotlin.math.abs

/**
 * Passively observes touch-drag distance across the current Activity's whole window by wrapping
 * its [Window.Callback], notifying listeners once a gesture's cumulative vertical displacement
 * exceeds a threshold. Used as a native proxy for `floating-box-open-on-scroll` — there's no
 * single "did the content scroll" signal that works for both classic Views and Jetpack Compose
 * (Compose manages its own scroll state without touching legacy `View.scrollTo`/`scrollBy`), but
 * every scroll gesture starts as a touch drag, so this observes that instead, at the one point
 * (`Window.Callback.dispatchTouchEvent`) that sees every touch before either UI toolkit does.
 *
 * Always delegates to the original callback unmodified and never consumes/alters the event, so
 * host touch and gesture handling is completely unaffected — the same non-interference guarantee
 * [PoltioHostInteractionBus] already relies on for its own touch observation.
 */
internal object PoltioScrollObserver {
    /** Matches the web SDK's own hardcoded `floating-box-open-on-scroll` threshold (`box.ts`). */
    private const val THRESHOLD_DP = 100f

    private val listeners = mutableSetOf<() -> Unit>()
    private var wrappedActivity: Activity? = null

    fun addListener(listener: () -> Unit) {
        synchronized(listeners) { listeners.add(listener) }
    }

    fun removeListener(listener: () -> Unit) {
        synchronized(listeners) { listeners.remove(listener) }
    }

    /** Installs the wrapper on [activity]'s window if not already installed for it. */
    fun installIfNeeded(activity: Activity) {
        if (wrappedActivity === activity) return
        val original = activity.window.callback
        if (original is ScrollObservingCallback) {
            wrappedActivity = activity
            return
        }
        if (original == null) return
        activity.window.callback = ScrollObservingCallback(activity, original)
        wrappedActivity = activity
    }

    private fun notifyThresholdCrossed() {
        val snapshot = synchronized(listeners) { listeners.toList() }
        snapshot.forEach { it.invoke() }
    }

    private class ScrollObservingCallback(
        private val activity: Activity,
        private val original: Window.Callback,
    ) : Window.Callback by original {
        private val thresholdPx = activity.dp(THRESHOLD_DP)
        private var downY = 0f

        override fun dispatchTouchEvent(event: MotionEvent): Boolean {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> downY = event.rawY
                MotionEvent.ACTION_MOVE -> {
                    if (abs(event.rawY - downY) > thresholdPx) notifyThresholdCrossed()
                }
            }
            return original.dispatchTouchEvent(event)
        }
    }
}
