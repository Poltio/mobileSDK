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

    /** Minimum per-gesture drag distance treated as real scroll activity rather than a tap. */
    private const val MOVEMENT_THRESHOLD_DP = 8f

    private val listeners = mutableSetOf<() -> Unit>()
    private val movementListeners = mutableSetOf<() -> Unit>()
    private val pendingThresholds = mutableListOf<Pair<Float, () -> Unit>>()

    fun addListener(listener: () -> Unit) {
        synchronized(listeners) { listeners.add(listener) }
    }

    fun removeListener(listener: () -> Unit) {
        synchronized(listeners) { listeners.remove(listener) }
    }

    /** Registers a listener notified once per gesture, the first time cumulative drag distance
     * exceeds [MOVEMENT_THRESHOLD_DP] — a genuine "the user is actively scrolling right now"
     * signal, independent of the fixed 100dp reveal threshold above. Used to auto-collapse an
     * expanded trigger while the host scrolls. */
    fun addMovementListener(listener: () -> Unit) {
        synchronized(movementListeners) { movementListeners.add(listener) }
    }

    fun removeMovementListener(listener: () -> Unit) {
        synchronized(movementListeners) { movementListeners.remove(listener) }
    }

    private fun notifyMovementDetected() {
        val snapshot = synchronized(movementListeners) { movementListeners.toList() }
        snapshot.forEach { it.invoke() }
    }

    /** Registers a one-shot callback that fires the first time total scroll drag distance
     * exceeds [thresholdDp], then automatically un-registers itself. Used by triggers with their
     * own configurable threshold (the card trigger's `floatingScrollThreshold`, default 300dp,
     * matching web), as an alternative to the fixed-100dp [addListener]/[removeListener] pair used
     * by the box/pill triggers. */
    fun onScrollPast(activity: Activity, thresholdDp: Float, callback: () -> Unit) {
        synchronized(pendingThresholds) { pendingThresholds.add(thresholdDp to callback) }
        installIfNeeded(activity)
    }

    /** Installs the wrapper on [activity]'s window if not already installed for it. Checks the
     * window's current callback directly rather than caching the [Activity] reference itself,
     * which would otherwise leak that activity for the lifetime of the app process (this object
     * is a singleton and never releases what it holds). */
    fun installIfNeeded(activity: Activity) {
        val original = activity.window.callback ?: return
        if (original is ScrollObservingCallback) return
        activity.window.callback = ScrollObservingCallback(activity, original)
    }

    private fun notifyThresholdCrossed() {
        val snapshot = synchronized(listeners) { listeners.toList() }
        snapshot.forEach { it.invoke() }
    }

    private fun handleScrolled(activity: Activity, distancePx: Float) {
        val toFire = synchronized(pendingThresholds) {
            val crossed = pendingThresholds.filter { (thresholdDp, _) -> distancePx > activity.dp(thresholdDp) }
            pendingThresholds.removeAll(crossed)
            crossed
        }
        toFire.forEach { (_, callback) -> callback() }
    }

    private class ScrollObservingCallback(
        private val activity: Activity,
        private val original: Window.Callback,
    ) : Window.Callback by original {
        private val thresholdPx = activity.dp(THRESHOLD_DP)
        private val movementThresholdPx = activity.dp(MOVEMENT_THRESHOLD_DP)
        private var downY = 0f
        private var lastY = 0f
        /** Total vertical drag distance accumulated across every gesture since this wrapper was
         * installed — an absolute-position proxy, not a per-gesture one. Without this, a page
         * scrolled via several smaller swipes would never cross [thresholdPx] or a card's
         * configurable threshold, since each gesture's distance used to reset to zero on its own
         * `ACTION_DOWN`, matching iOS/web's continuous scroll-offset tracking instead. */
        private var cumulativeScrollPx = 0f
        private var hasNotifiedMovementThisGesture = false

        override fun dispatchTouchEvent(event: MotionEvent): Boolean {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downY = event.rawY
                    lastY = event.rawY
                    hasNotifiedMovementThisGesture = false
                }
                MotionEvent.ACTION_MOVE -> {
                    cumulativeScrollPx += abs(event.rawY - lastY)
                    lastY = event.rawY
                    if (cumulativeScrollPx > thresholdPx) notifyThresholdCrossed()
                    // Per-gesture (not cumulative) distance: this only needs to tell a real drag
                    // apart from a stray tap, not track absolute scroll position.
                    if (!hasNotifiedMovementThisGesture && abs(event.rawY - downY) > movementThresholdPx) {
                        hasNotifiedMovementThisGesture = true
                        notifyMovementDetected()
                    }
                    handleScrolled(activity, cumulativeScrollPx)
                }
            }
            return original.dispatchTouchEvent(event)
        }
    }
}
