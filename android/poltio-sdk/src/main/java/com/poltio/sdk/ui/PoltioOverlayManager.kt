package com.poltio.sdk.ui

import android.app.Activity
import android.app.Application
import android.content.Intent
import android.os.Bundle
import android.view.Gravity
import android.view.MotionEvent
import android.view.ViewGroup
import android.widget.FrameLayout
import com.poltio.sdk.PoltioExecutors
import com.poltio.sdk.PoltioLogger
import com.poltio.sdk.PoltioTriggerDismissalStore
import com.poltio.sdk.PoltioWidgetResponse
import java.lang.ref.WeakReference

/**
 * Manages attaching, presenting, and dismissing native Poltio floating triggers and the
 * interactive widget WebView.
 *
 * Unlike iOS (which needs a dedicated passthrough `UIWindow` to overlay across the whole app),
 * Android's single-window view hierarchy lets a sibling `FrameLayout` added on top of the current
 * Activity's content view achieve the same click-through effect for free: a touch that doesn't
 * land on the trigger simply isn't consumed, so the framework's own dispatch falls through to the
 * content view beneath it. This mirrors AGENTS.md's guidance to attach to the current Activity's
 * `window.decorView` / root `FrameLayout` rather than a system-alert-window overlay.
 */
internal object PoltioOverlayManager {
    private const val MAX_SHOW_RETRIES = 10
    private const val RETRY_DELAY_MS = 200L

    /**
     * Default bottom inset for the box trigger — unlike pill/card (70dp), the box trigger's
     * collapsed tab is tall (140dp) and sits low by design, but 24dp put it directly behind most
     * apps' bottom navigation bars (Material's default `NavigationBar` height is 80dp). This
     * clears that by default across screen sizes, since dp — unlike raw pixels — already scales
     * with density rather than physical screen size; [avoidSystemBars] on top of it additionally
     * accounts for the real gesture/3-button system nav bar at runtime.
     */
    private const val BOX_DEFAULT_BOTTOM_INSET_DP = 88f

    private var application: Application? = null
    private var resumedActivity: WeakReference<Activity>? = null

    private var overlayContainer: FrameLayout? = null
    private var activeTriggerView: (android.view.View)? = null
    private var currentPublicId: String? = null
    private var currentTriggerType: String? = null
    private var showTriggerRetryCount = 0
    private var pendingShowRunnable: Runnable? = null

    /** Registers activity-lifecycle tracking; safe to call more than once with the same instance. */
    fun attach(app: Application) {
        if (application === app) return
        application = app
        app.registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
            override fun onActivityResumed(activity: Activity) {
                resumedActivity = WeakReference(activity)
            }

            override fun onActivityPaused(activity: Activity) {
                if (resumedActivity?.get() === activity) resumedActivity = null
            }

            override fun onActivityDestroyed(activity: Activity) {
                if (resumedActivity?.get() === activity) resumedActivity = null
                if (overlayContainer?.let { it.context === activity } == true) {
                    teardownOverlaySynchronously()
                }
            }

            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit
            override fun onActivityStarted(activity: Activity) = Unit
            override fun onActivityStopped(activity: Activity) = Unit
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
        })
    }

    /** Displays the floating trigger for the resolved widget on the current Activity, on the main thread. */
    fun showTrigger(widget: PoltioWidgetResponse, puid: String?) {
        PoltioExecutors.runOnMain { showTriggerOnMain(widget, puid) }
    }

    /** Hides and removes any currently displayed floating trigger, on the main thread. */
    fun hideTrigger() {
        PoltioExecutors.runOnMain { hideTriggerOnMain() }
    }

    private fun showTriggerOnMain(widget: PoltioWidgetResponse, puid: String?) {
        pendingShowRunnable?.let { PoltioExecutors.main.removeCallbacks(it) }
        pendingShowRunnable = null

        val options = widget.overlayOptions
        if (!(options.isBoxTrigger || options.isPillTrigger || options.isCardTrigger)) {
            PoltioLogger.warning { "Trigger type '${options.triggerType ?: "none"}' is not currently handled (supported: 'box', 'pill', 'card')." }
            hideTriggerOnMain()
            return
        }

        if (options.hideButton) {
            PoltioLogger.debug { "Floating trigger suppressed for widget '${widget.publicId}' (floating-hide-button)." }
            hideTriggerOnMain()
            return
        }

        val activity = resumedActivity?.get()
        if (activity != null && PoltioTriggerDismissalStore.isDismissed(activity, widget.publicId)) {
            PoltioLogger.debug { "Floating trigger suppressed for widget '${widget.publicId}' (still within its close-remember window)." }
            hideTriggerOnMain()
            return
        }

        val targetTriggerType = options.triggerType ?: ""

        if (currentPublicId == widget.publicId &&
            currentTriggerType == targetTriggerType &&
            activeTriggerView != null &&
            activeTriggerView?.parent != null
        ) {
            // Already active and visible for this exact widget and trigger type.
            return
        }

        val isRetryForSameWidget = currentPublicId == widget.publicId
        teardownOverlaySynchronously()
        if (!isRetryForSameWidget) showTriggerRetryCount = 0
        currentPublicId = widget.publicId
        currentTriggerType = targetTriggerType

        if (activity == null) {
            if (showTriggerRetryCount >= MAX_SHOW_RETRIES) {
                PoltioLogger.warning { "No resumed Activity available after $MAX_SHOW_RETRIES retries; giving up on showing trigger for widget '${widget.publicId}'." }
                showTriggerRetryCount = 0
                currentPublicId = null
                currentTriggerType = null
                return
            }
            showTriggerRetryCount++
            PoltioLogger.debug { "No resumed Activity yet, retrying showTrigger ($showTriggerRetryCount/$MAX_SHOW_RETRIES) after ${RETRY_DELAY_MS}ms..." }
            val runnable = Runnable {
                if (currentPublicId == widget.publicId) showTriggerOnMain(widget, puid)
            }
            pendingShowRunnable = runnable
            PoltioExecutors.main.postDelayed(runnable, RETRY_DELAY_MS)
            return
        }

        showTriggerRetryCount = 0

        val contentRoot = activity.findViewById<ViewGroup>(android.R.id.content) ?: return
        val container = FrameLayout(activity).apply {
            layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            clipChildren = false
            clipToPadding = false
        }
        installOutsideTouchDetector(container)
        contentRoot.addView(container)
        overlayContainer = container

        // Android has no direct analogue of a CSS/window z-index; `floating-zindex` is instead
        // mapped onto view elevation so a host app that stacks its own elevated views (dialogs,
        // app bars) can still be told to render the trigger more/less prominently above them.
        // Clamped to Material's practical elevation range so an arbitrary large value doesn't
        // produce a runaway shadow.
        val zIndexElevationDp = (options.floatingZindex / 100.0 * 8.0).coerceIn(0.0, 24.0)
        androidx.core.view.ViewCompat.setElevation(container, activity.dp(zIndexElevationDp.toFloat()).toFloat())

        val onOpenWidget: () -> Unit = { presentWidgetWebView(widget.publicId, puid, widget.overlayOptions) }
        val onDismissForever: (Double) -> Unit = { hours ->
            resumedActivity?.get()?.let { PoltioTriggerDismissalStore.recordDismissal(it, widget.publicId, hours) }
            hideTriggerOnMain()
        }

        val vertical = options.verticalPosition
        val horizontal = options.horizontalPosition

        val triggerView: android.view.View = when {
            options.isPillTrigger -> PoltioFloatingPillTriggerView(activity, widget, onOpenWidget, onDismissForever).also {
                pinTrigger(it, container, vertical, horizontal, horizontalInsetDp = 16f, verticalInsetDp = 70f, avoidSystemBars = true)
            }
            options.isCardTrigger -> PoltioFloatingCardTriggerView(activity, widget, onOpenWidget).also {
                pinTrigger(it, container, vertical, horizontal, horizontalInsetDp = 0f, verticalInsetDp = 70f, avoidSystemBars = false)
            }
            else -> PoltioFloatingBoxTriggerView(activity, widget, onOpenWidget, onDismissForever).also {
                pinTrigger(it, container, vertical, horizontal, horizontalInsetDp = 0f, verticalInsetDp = BOX_DEFAULT_BOTTOM_INSET_DP, avoidSystemBars = true)
            }
        }

        activeTriggerView = triggerView

        PoltioLogger.info { "Attached floating trigger overlay for widget '${widget.publicId}' (type: ${options.triggerType ?: "unknown"})." }

        animateTriggerIn(triggerView)
    }

    private fun animateTriggerIn(view: android.view.View) {
        val restingX = view.translationX
        view.alpha = 0f
        view.translationX = restingX + view.context.dp(80f)
        view.animate()
            .alpha(1f)
            .translationX(restingX)
            .setStartDelay(50)
            .setDuration(400)
            .setInterpolator(android.view.animation.OvershootInterpolator(0.9f))
            .start()
    }

    private fun hideTriggerOnMain() {
        pendingShowRunnable?.let { PoltioExecutors.main.removeCallbacks(it) }
        pendingShowRunnable = null
        currentPublicId = null
        currentTriggerType = null

        val container = overlayContainer
        val view = activeTriggerView
        overlayContainer = null
        activeTriggerView = null

        if (view == null || container == null) return

        view.animate()
            .alpha(0f)
            .translationX(view.translationX + view.context.dp(80f))
            .setDuration(250)
            .withEndAction {
                (container.parent as? ViewGroup)?.removeView(container)
            }
            .start()
    }

    /** Synchronously tears down any existing overlay container/view (no animation). */
    private fun teardownOverlaySynchronously() {
        pendingShowRunnable?.let { PoltioExecutors.main.removeCallbacks(it) }
        pendingShowRunnable = null
        currentPublicId = null
        currentTriggerType = null
        activeTriggerView = null
        overlayContainer?.let { (it.parent as? ViewGroup)?.removeView(it) }
        overlayContainer = null
    }

    /**
     * Detects touches that land on the overlay container but not on any trigger child, and
     * broadcasts them via [PoltioHostInteractionBus] — the Android analogue of iOS's
     * `PoltioPassthroughWindow.hitTest` scroll/tap-outside notification. The overlay never
     * consumes these events, so they still fall through to the host screen underneath.
     */
    private fun installOutsideTouchDetector(container: FrameLayout) {
        container.setOnTouchListener { _, event ->
            if (event.actionMasked == MotionEvent.ACTION_DOWN) {
                PoltioHostInteractionBus.notifyOutsideInteraction()
            }
            false
        }
    }

    /**
     * Pins [view] within [container] according to the parsed `floatingPosition`
     * (`vertical`/`horizontal`), applying system-bar insets only where iOS relied on the safe-area
     * layout guide (the pill trigger); the card/box tabs intentionally hug the raw edge so their
     * collapsed tab bleeds off-screen, matching iOS.
     */
    private fun pinTrigger(
        view: android.view.View,
        container: FrameLayout,
        vertical: String,
        horizontal: String,
        horizontalInsetDp: Float,
        verticalInsetDp: Float,
        avoidSystemBars: Boolean,
    ) {
        val context = container.context
        val params = view.layoutParams as? FrameLayout.LayoutParams
            ?: FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT)

        val horizontalGravity = if (horizontal == "left") Gravity.START else Gravity.END
        val verticalGravity = when (vertical) {
            "top" -> Gravity.TOP
            "center" -> Gravity.CENTER_VERTICAL
            else -> Gravity.BOTTOM
        }
        params.gravity = horizontalGravity or verticalGravity

        val horizontalInsetPx = context.dp(horizontalInsetDp)
        val verticalInsetPx = context.dp(verticalInsetDp)

        fun applyMargins(systemLeft: Int, systemRight: Int, systemTop: Int, systemBottom: Int) {
            if (horizontal == "left") params.leftMargin = horizontalInsetPx + systemLeft else params.rightMargin = horizontalInsetPx + systemRight
            when (vertical) {
                "top" -> params.topMargin = verticalInsetPx + systemTop
                "center" -> Unit
                else -> params.bottomMargin = verticalInsetPx + systemBottom
            }
            view.layoutParams = params
        }

        // Position with zero system-bar compensation up front so the trigger doesn't wait on a
        // window-insets dispatch to appear at all.
        applyMargins(systemLeft = 0, systemRight = 0, systemTop = 0, systemBottom = 0)
        container.addView(view, params)
        if (vertical == "center") view.translationY = -verticalInsetPx.toFloat()

        if (avoidSystemBars) {
            // `ViewCompat.getRootWindowInsets(container)` right after `addView` is unreliable —
            // insets aren't dispatched until the next layout pass, so a synchronous read here can
            // silently return null. `setOnApplyWindowInsetsListener` instead reacts whenever insets
            // actually become available (and again on later changes, e.g. rotation).
            androidx.core.view.ViewCompat.setOnApplyWindowInsetsListener(container) { _, insets ->
                val systemBars = insets.getInsets(androidx.core.view.WindowInsetsCompat.Type.systemBars())
                applyMargins(systemBars.left, systemBars.right, systemBars.top, systemBars.bottom)
                insets
            }
        }
    }

    /** Presents the interactive widget modal WebView on top of the resumed Activity. */
    fun presentWidgetWebView(publicId: String, puid: String?, overlayOptions: com.poltio.sdk.PoltioOverlayOptions? = null) {
        PoltioExecutors.runOnMain {
            val activity = resumedActivity?.get()
            if (activity == null) {
                PoltioLogger.error { "Unable to find a resumed Activity to present the widget." }
                return@runOnMain
            }

            // Hide (but don't tear down) the floating trigger while the webview is presented.
            overlayContainer?.visibility = android.view.View.INVISIBLE

            val intent = PoltioWebViewActivity.newIntent(activity, publicId, puid, overlayOptions)
            activity.startActivity(intent)
            // PoltioWebViewActivity drives its own slide-up/scrim-fade entrance animation against
            // its translucent theme; suppress the system's default activity-enter transition so
            // the two don't stack.
            activity.overridePendingTransition(0, 0)
        }
    }

    /** Called by [PoltioWebViewActivity] when it's dismissed, to restore the collapsed trigger. */
    internal fun onWidgetWebViewDismissed() {
        PoltioExecutors.runOnMain {
            val container = overlayContainer ?: return@runOnMain
            val trigger = activeTriggerView as? PoltioTriggerPresentable

            trigger?.resetToCollapsed(animated = false)
            container.visibility = android.view.View.VISIBLE

            val view = activeTriggerView ?: return@runOnMain
            animateTriggerIn(view)
        }
    }
}
