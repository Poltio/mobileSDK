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
import com.poltio.sdk.PoltioSDK
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
    /** How far (dp) the active trigger slides in from, and out to, beyond its docked edge. */
    private var triggerSlideOffsetDp = 80f
    private var currentPublicId: String? = null
    private var currentTriggerType: String? = null
    /** Widgets can share content and trigger type yet differ in copy, colors and position, so the
     * trigger on screen is only the incoming one when its widget id matches too. */
    private var currentWidgetId: Int? = null

    /** A widget waiting for a host Activity to resume, shown from `onActivityResumed`: one that
     * resolved while no host was resumed (the app still starting or in the background, or the
     * widget sheet up over a host that a rotation rebuilt behind it), or the trigger a host was
     * showing when a configuration change destroyed it. */
    private var pendingTrigger: TriggerRequest? = null
    /** What the trigger on screen was built from, so a configuration change can carry it over. */
    private var shownTrigger: TriggerRequest? = null

    private class TriggerRequest(val widget: PoltioWidgetResponse, val puid: String?)

    /** Registers activity-lifecycle tracking; safe to call more than once with the same instance. */
    fun attach(app: Application) {
        if (application === app) return
        application = app
        app.registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
            override fun onActivityResumed(activity: Activity) {
                // The widget sheet never hosts a trigger: while it's up, the trigger belongs to the
                // host behind it, which resumes again once the sheet closes.
                if (activity is PoltioWebViewActivity) return
                resumedActivity = WeakReference(activity)
                pendingTrigger?.let { request ->
                    pendingTrigger = null
                    showTriggerOnMain(request.widget, request.puid)
                }
            }

            override fun onActivityPaused(activity: Activity) {
                if (resumedActivity?.get() === activity) resumedActivity = null
            }

            override fun onActivityDestroyed(activity: Activity) {
                if (resumedActivity?.get() === activity) resumedActivity = null
                if (overlayContainer?.let { it.context === activity } == true) {
                    // A configuration change (e.g. rotation) rebuilds the host: carry its trigger
                    // over to the new one instead of leaving it bare until the next screen view.
                    val carriedOver = shownTrigger.takeIf { activity.isChangingConfigurations }
                    teardownOverlaySynchronously()
                    if (carriedOver != null) pendingTrigger = carriedOver
                }
            }

            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit
            override fun onActivityStarted(activity: Activity) = Unit
            override fun onActivityStopped(activity: Activity) = Unit
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
        })
    }

    /**
     * Seeds the "current Activity" when [PoltioSDK.configure] is called with an `Activity` after
     * that Activity already resumed — lifecycle callbacks registered in [attach] only observe
     * *future* `onResume`s, so without this the first screen would never get a trigger.
     */
    fun seedCurrentActivity(activity: Activity) {
        PoltioExecutors.runOnMain {
            // A weakly-held Activity that's already finishing/destroyed (but not yet collected) is
            // as good as none — replace it rather than letting it block the new one.
            val current = resumedActivity?.get()
            val currentIsStale = current == null || current.isFinishing || current.isDestroyed
            if (currentIsStale && !activity.isFinishing && !activity.isDestroyed) {
                resumedActivity = WeakReference(activity)
            }
        }
    }

    /** Displays the floating trigger for the resolved widget on the current Activity, on the main thread. */
    fun showTrigger(widget: PoltioWidgetResponse, puid: String?) {
        PoltioExecutors.runOnMain { showTriggerOnMain(widget, puid) }
    }

    /** Hides and removes any currently displayed floating trigger, on the main thread. */
    fun hideTrigger() {
        PoltioExecutors.runOnMain { hideTriggerOnMain() }
    }

    /** Whether [widget] is the one the current trigger was built for: same content and same widget. */
    private fun isCurrent(widget: PoltioWidgetResponse): Boolean =
        currentPublicId == widget.publicId && currentWidgetId == widget.widgetId

    private fun showTriggerOnMain(widget: PoltioWidgetResponse, puid: String?) {
        // A newer request supersedes one still waiting for a host to resume.
        pendingTrigger = null

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
        val storeContext = application ?: activity?.applicationContext
        if (storeContext != null && PoltioTriggerDismissalStore.isDismissed(storeContext, widget.publicId)) {
            PoltioLogger.debug { "Floating trigger suppressed for widget '${widget.publicId}' (still within its close-remember window)." }
            hideTriggerOnMain()
            return
        }

        val targetTriggerType = options.triggerType ?: ""

        if (isCurrent(widget) &&
            currentTriggerType == targetTriggerType &&
            activeTriggerView != null &&
            activeTriggerView?.parent != null &&
            activeTriggerView?.context === activity
        ) {
            // Already active and visible for this exact widget and trigger type on the current
            // Activity. Still a fresh impression from the caller's perspective (e.g. the same
            // widget is configured for two screens), so report it even though nothing is rebuilt.
            //
            // The `context === activity` check matters because the trigger is attached to the
            // current Activity's content view: without it, navigating to a *new* Activity (which
            // only backstacks the old one rather than destroying it) that resolves the same widget
            // would match on widget and trigger type alone and return here — leaving the trigger
            // attached to the paused, off-screen Activity underneath instead of the one actually
            // visible now.
            PoltioSDK.reportCtaView(widget)
            return
        }

        teardownOverlaySynchronously()

        if (activity == null) {
            // Keep it rather than give up after a few tries: a host sitting paused under the widget
            // sheet after a rotation resumes only once the sheet closes, however long that takes.
            PoltioLogger.debug { "No resumed Activity; showing the trigger for widget '${widget.publicId}' once one resumes." }
            pendingTrigger = TriggerRequest(widget, puid)
            return
        }

        currentPublicId = widget.publicId
        currentTriggerType = targetTriggerType
        currentWidgetId = widget.widgetId

        val contentRoot = activity.findViewById<ViewGroup>(android.R.id.content) ?: return

        // The trigger is now guaranteed to actually render below — report the impression once
        // here rather than at the top of the method, so a widget kept for a host to resume isn't
        // reported until it actually shows.
        PoltioSDK.reportCtaView(widget)
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

        val onOpenWidget: () -> Unit = { presentWidgetWebView(widget.publicId, widget.widgetId, puid, widget.overlayOptions) }
        // Persist against the application context, not whichever Activity happens to be resumed —
        // the dismissal must be recorded even if no Activity is resumed at that exact moment.
        val dismissalContext = activity.applicationContext
        val onDismissForever: (Double) -> Unit = { hours ->
            PoltioTriggerDismissalStore.recordDismissal(dismissalContext, widget.publicId, hours)
            hideTriggerOnMain()
        }

        val vertical = options.verticalPosition
        val horizontal = options.horizontalPosition
        triggerSlideOffsetDp = if (options.isLeftDocked) -80f else 80f

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
        shownTrigger = TriggerRequest(widget, puid)

        PoltioLogger.info { "Attached floating trigger overlay for widget '${widget.publicId}' (type: ${options.triggerType ?: "unknown"})." }

        animateTriggerIn(triggerView)
    }

    private fun animateTriggerIn(view: android.view.View) {
        val restingX = view.translationX
        view.alpha = 0f
        view.translationX = restingX + view.context.dp(triggerSlideOffsetDp)
        view.animate()
            .alpha(1f)
            .translationX(restingX)
            .setStartDelay(50)
            .setDuration(400)
            .setInterpolator(android.view.animation.OvershootInterpolator(0.9f))
            .start()
    }

    private fun hideTriggerOnMain() {
        pendingTrigger = null
        shownTrigger = null
        currentPublicId = null
        currentTriggerType = null
        currentWidgetId = null

        val container = overlayContainer
        val view = activeTriggerView
        overlayContainer = null
        activeTriggerView = null

        if (view == null || container == null) return

        view.animate()
            .alpha(0f)
            .translationX(view.translationX + view.context.dp(triggerSlideOffsetDp))
            .setDuration(250)
            .withEndAction {
                (container.parent as? ViewGroup)?.removeView(container)
            }
            .start()
    }

    /** Synchronously tears down any existing overlay container/view (no animation). */
    private fun teardownOverlaySynchronously() {
        shownTrigger = null
        currentPublicId = null
        currentTriggerType = null
        currentWidgetId = null
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

        // Absolute LEFT/RIGHT, not START/END: `floating-position` names a physical side and the
        // triggers draw their rounded corners for it, so a right-to-left locale mustn't flip it.
        val horizontalGravity = if (horizontal == "left") Gravity.LEFT else Gravity.RIGHT
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
    fun presentWidgetWebView(publicId: String, widgetId: Int? = null, puid: String?, overlayOptions: com.poltio.sdk.PoltioOverlayOptions? = null) {
        PoltioExecutors.runOnMain {
            val activity = resumedActivity?.get()
            if (activity == null) {
                PoltioLogger.error { "Unable to find a resumed Activity to present the widget." }
                return@runOnMain
            }

            // Hide (but don't tear down) the floating trigger while the webview is presented.
            overlayContainer?.visibility = android.view.View.INVISIBLE

            val intent = PoltioWebViewActivity.newIntent(activity, publicId, widgetId, puid, overlayOptions)
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
