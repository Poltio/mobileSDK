package com.poltio.sdk.ui

import android.app.Activity
import android.view.MotionEvent
import android.view.Window
import java.lang.ref.WeakReference
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
    /** Weakly held so the singleton never keeps an `Activity` (via the callback's own reference to
     * it) alive past its real lifetime — only used to reset scroll tracking for freshly registered
     * listeners, see [resetCumulativeScrollForNewObservation]. */
    private var activeCallbackRef: WeakReference<ScrollObservingCallback>? = null

    fun addListener(listener: () -> Unit) {
        resetCumulativeScrollForNewObservation()
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
        // installIfNeeded first: it's what points activeCallbackRef at the correct (current)
        // wrapper for `activity`. Resetting before this could reset a stale wrapper from a
        // different activity, or nothing at all, instead of the one this registration actually
        // observes.
        installIfNeeded(activity)
        resetCumulativeScrollForNewObservation()
        synchronized(pendingThresholds) { pendingThresholds.add(thresholdDp to callback) }
    }

    /** Cancels a still-pending [onScrollPast] registration by the exact callback reference it was
     * registered with — e.g. when its view is detached before the threshold was ever crossed.
     * Without this, that callback (and anything it captures) would sit in [pendingThresholds] for
     * the life of the process, since nothing else ever removes an entry that never fires. */
    fun cancelScrollPast(callback: () -> Unit) {
        synchronized(pendingThresholds) { pendingThresholds.removeAll { it.second === callback } }
    }

    /** Installs the wrapper on [activity]'s window if not already installed for it. Checks the
     * window's current callback directly rather than caching the [Activity] reference itself,
     * which would otherwise leak that activity for the lifetime of the app process (this object
     * is a singleton and never releases what it holds). */
    fun installIfNeeded(activity: Activity) {
        val original = activity.window.callback
        if (original is ScrollObservingCallback) {
            activeCallbackRef = WeakReference(original)
            return
        }
        if (original == null) return
        val wrapper = ScrollObservingCallback(activity, original)
        activity.window.callback = wrapper
        activeCallbackRef = WeakReference(wrapper)
    }

    /** A freshly registered listener/threshold starts counting scroll distance from zero, rather
     * than inheriting however far the user had already scrolled on a previous screen that shares
     * the same Activity (and therefore the same [ScrollObservingCallback]) — otherwise a new box,
     * pill, or card trigger could fire on the very first touch move after appearing. */
    private fun resetCumulativeScrollForNewObservation() {
        activeCallbackRef?.get()?.resetCumulativeScroll()
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
        /** Net downward scroll accumulated across every gesture since this wrapper was installed
         * (or last reset) — an absolute-position proxy, not a per-gesture one, and floored at zero
         * so scrolling back up (or finger jiggling) can't inflate it, matching how a real
         * `scrollTop`-style offset behaves on iOS/web. Without accumulating across gestures at
         * all, a page scrolled via several smaller swipes would never cross [thresholdPx] or a
         * card's configurable threshold, since each gesture's distance used to reset to zero on
         * its own `ACTION_DOWN`. */
        private var cumulativeScrollPx = 0f
        private var hasNotifiedMovementThisGesture = false

        fun resetCumulativeScroll() {
            cumulativeScrollPx = 0f
        }

        override fun dispatchTouchEvent(event: MotionEvent): Boolean {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downY = event.rawY
                    lastY = event.rawY
                    hasNotifiedMovementThisGesture = false
                }
                MotionEvent.ACTION_MOVE -> {
                    // Finger moving up (rawY decreasing) means the content scrolls down, so that's
                    // what grows cumulativeScrollPx; scrolling back up shrinks it, floored at 0 —
                    // net position, not total distance traveled.
                    val deltaY = lastY - event.rawY
                    cumulativeScrollPx = (cumulativeScrollPx + deltaY).coerceAtLeast(0f)
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
