package com.poltio.sdk.ui

import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewOutlineProvider
import android.view.animation.OvershootInterpolator
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import com.poltio.sdk.PoltioExecutors
import com.poltio.sdk.PoltioWidgetResponse
import kotlin.math.abs
import kotlin.math.max

/**
 * Native floating card trigger view supporting collapsed (rounded edge tab with sparkle & chevron)
 * and expanded (floating rounded card with close button, title, description, and action button)
 * states.
 */
internal class PoltioFloatingCardTriggerView(
    context: Context,
    private val widget: PoltioWidgetResponse,
    private val onOpenWidget: () -> Unit,
) : FrameLayout(context), PoltioTriggerPresentable {

    enum class TriggerState { COLLAPSED, EXPANDED }

    private object Constants {
        const val COLLAPSED_WIDTH_DP = 44f
        const val COLLAPSED_HEIGHT_DP = 104f
        const val COLLAPSED_CORNER_RADIUS_DP = 24f
        const val COLLAPSED_SPARKLE_SIZE_DP = 28f
        const val COLLAPSED_CHEVRON_SIZE_DP = 16f

        const val EXPANDED_CARD_WIDTH_DP = 290f
        const val EXPANDED_CARD_MARGIN_DP = 16f
        const val EXPANDED_MIN_HEIGHT_DP = 210f

        const val SPARKLE_SIZE_DP = 32f
        const val CLOSE_BUTTON_SIZE_DP = 44f
        const val CONTENT_HORIZONTAL_INSET_DP = 20f
        const val ACTION_BUTTON_HEIGHT_DP = 40f
    }

    private enum class DefaultStrings(val value: String) {
        TITLE("Let us choose together"),
        DESCRIPTION("Let's find your perfect match together"),
        ACTION_BUTTON("Start Now"),
    }

    var currentState: TriggerState = if (widget.overlayOptions.isInitialExpanded) TriggerState.EXPANDED else TriggerState.COLLAPSED
        private set

    private val collapsedWidthPx = context.dp(Constants.COLLAPSED_WIDTH_DP)
    private val collapsedHeightPx = context.dp(Constants.COLLAPSED_HEIGHT_DP)
    private val expandedTotalWidthPx = context.dp(Constants.EXPANDED_CARD_WIDTH_DP + Constants.EXPANDED_CARD_MARGIN_DP)
    private val expandedCardWidthPx = context.dp(Constants.EXPANDED_CARD_WIDTH_DP)

    private val collapsedContainer = FrameLayout(context)
    private val expandedContainer = FrameLayout(context)
    private var collapsedIconLoader: PoltioTriggerIconLoader
    private var expandedIconLoader: PoltioTriggerIconLoader
    private val collapsedSparkle = PoltioSparkleIconView(context)
    private val expandedSparkle = PoltioSparkleIconView(context)

    private var sizeAnimator: android.animation.ValueAnimator? = null
    /** Elapsed-realtime timestamp of the most recent transition into EXPANDED. */
    private var expandedAtMs: Long = 0L
    /** Auto-collapses an expanded card while the host page is actively being scrolled, smoothly
     * following the existing expand/collapse animation — regardless of what caused the expand
     * (manual tap or the scroll-reveal below). Requires a brief grace period after expanding so
     * the very same scroll gesture that revealed the card doesn't immediately collapse it again.
     * This is a deliberate mobile-specific divergence from web, which leaves the card expanded
     * indefinitely once revealed. */
    private val scrollCollapseListener: () -> Unit = {
        val sinceExpanded = android.os.SystemClock.elapsedRealtime() - expandedAtMs
        if (currentState == TriggerState.EXPANDED && sinceExpanded > SCROLL_COLLAPSE_GRACE_PERIOD_MS) {
            PoltioExecutors.runOnMain { setState(TriggerState.COLLAPSED, animated = true) }
        }
    }
    /** Kept so `onDetachedFromWindow` can cancel this exact still-pending registration if the
     * threshold was never crossed — see `PoltioScrollObserver.cancelScrollPast`. */
    private var scrollRevealListener: (() -> Unit)? = null

    init {
        clipChildren = false
        clipToPadding = false

        setupCollapsedContainer()
        setupExpandedContainer()

        collapsedIconLoader = PoltioTriggerIconLoader(collapsedContainer, Constants.COLLAPSED_SPARKLE_SIZE_DP)
        collapsedIconLoader.load(widget.overlayOptions, collapsedSparkle) { collapsedSparkle.visibility = View.GONE }

        expandedIconLoader = PoltioTriggerIconLoader(expandedContainer, Constants.SPARKLE_SIZE_DP)
        expandedIconLoader.load(widget.overlayOptions, expandedSparkle) { expandedSparkle.visibility = View.GONE }

        applyState(currentState, animated = false)
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        // Registered here (not in `init`, which only ever runs once) so a view that gets detached
        // and later reattached to a window — rather than torn down and recreated — re-establishes
        // its scroll observation instead of silently losing it forever.
        setupScrollReveal()
        context.findActivity()?.let { PoltioScrollObserver.installIfNeeded(it) }
        PoltioScrollObserver.addMovementListener(scrollCollapseListener)
    }

    /** Matches web's card (`core.ts`'s `first` -> `second` transition): reveals the collapsed card
     * once the host content scrolls past `floatingScrollThreshold` (default 300dp, matching web's
     * own `scrollThreshold ?? 300`). One-shot. Unlike web (which leaves the card expanded
     * indefinitely once revealed), mobile also auto-collapses it while the host keeps scrolling —
     * see `scrollCollapseListener` — a deliberate mobile-specific UX choice. */
    private fun setupScrollReveal() {
        context.findActivity()?.let { activity ->
            // `pendingThresholds` in PoltioScrollObserver is a long-lived list on a singleton
            // object; a callback that strongly captures `this` would keep this view (and its
            // Activity via `context`) alive forever if the threshold is never crossed. A weak
            // reference lets the view (and the callback itself, once GC'd) become collectable
            // normally instead — and `onDetachedFromWindow` below proactively cancels the
            // registration too, so it doesn't just sit dormant in that list forever either.
            val viewRef = java.lang.ref.WeakReference(this)
            val listener: () -> Unit = {
                PoltioExecutors.runOnMain {
                    val view = viewRef.get() ?: return@runOnMain
                    if (view.currentState == TriggerState.COLLAPSED) view.setState(TriggerState.EXPANDED, animated = true)
                }
            }
            scrollRevealListener = listener
            PoltioScrollObserver.onScrollPast(activity, widget.overlayOptions.floatingScrollThreshold.toFloat(), listener)
        }
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        sizeAnimator?.cancel()
        collapsedIconLoader.dispose()
        expandedIconLoader.dispose()
        PoltioScrollObserver.removeMovementListener(scrollCollapseListener)
        scrollRevealListener?.let { PoltioScrollObserver.cancelScrollPast(it) }
    }

    private companion object {
        /** Minimum time an expand must have been visible before a host scroll can collapse it. */
        const val SCROLL_COLLAPSE_GRACE_PERIOD_MS = 400L

        /** Poltio brand blue, used for the branding mark's dot. */
        val BRAND_DOT_COLOR: Int = Color.rgb(0, 158, 237)

        /** Branding mark wordmark text color. */
        val BRAND_TEXT_COLOR: Int = Color.GRAY
    }

    private fun setupCollapsedContainer() {
        collapsedContainer.background = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(widget.overlayOptions.resolvedBgColor)
            val r = context.dp(Constants.COLLAPSED_CORNER_RADIUS_DP).toFloat()
            cornerRadii = floatArrayOf(r, r, 0f, 0f, 0f, 0f, r, r)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            collapsedContainer.outlineProvider = ViewOutlineProvider.BACKGROUND
            collapsedContainer.elevation = context.dp(4f).toFloat()
        }
        collapsedContainer.isClickable = true

        collapsedContainer.addView(
            collapsedSparkle,
            FrameLayout.LayoutParams(context.dp(Constants.COLLAPSED_SPARKLE_SIZE_DP), context.dp(Constants.COLLAPSED_SPARKLE_SIZE_DP), Gravity.TOP or Gravity.CENTER_HORIZONTAL).apply {
                topMargin = context.dp(14f)
            },
        )

        val chevron = PoltioChevronGlyphView(context, PoltioChevronDirection.LEFT, widget.overlayOptions.resolvedIconColor)
        collapsedContainer.addView(
            chevron,
            FrameLayout.LayoutParams(context.dp(Constants.COLLAPSED_CHEVRON_SIZE_DP), context.dp(Constants.COLLAPSED_CHEVRON_SIZE_DP), Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL).apply {
                bottomMargin = context.dp(16f)
            },
        )

        addView(collapsedContainer, FrameLayout.LayoutParams(collapsedWidthPx, collapsedHeightPx, Gravity.CENTER_VERTICAL or Gravity.END))

        var downX = 0f
        collapsedContainer.setOnTouchListener { view, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> downX = event.x
                MotionEvent.ACTION_UP -> if (abs(event.x - downX) < context.dp(8f)) view.performClick()
            }
            true
        }
        collapsedContainer.setOnClickListener { setState(TriggerState.EXPANDED, animated = true) }
    }

    private fun setupExpandedContainer() {
        expandedContainer.background = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(widget.overlayOptions.resolvedBgColor)
            cornerRadius = context.dp(widget.overlayOptions.resolvedMobileTopBorderRadius).toFloat()
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            expandedContainer.outlineProvider = ViewOutlineProvider.BACKGROUND
            expandedContainer.elevation = context.dp(6f).toFloat()
        }
        expandedContainer.isClickable = true

        val column = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(
                context.dp(Constants.CONTENT_HORIZONTAL_INSET_DP),
                context.dp(18f),
                context.dp(Constants.CONTENT_HORIZONTAL_INSET_DP),
                context.dp(20f),
            )
        }

        val topRow = FrameLayout(context)
        topRow.addView(expandedSparkle, FrameLayout.LayoutParams(context.dp(Constants.SPARKLE_SIZE_DP), context.dp(Constants.SPARKLE_SIZE_DP), Gravity.START or Gravity.TOP))
        val closeButton = PoltioCloseGlyphView(context, widget.overlayOptions.resolvedIconColor).apply {
            contentDescription = "Close Poltio Widget Card"
            setOnClickListener { setState(TriggerState.COLLAPSED, animated = true) }
        }
        topRow.addView(closeButton, FrameLayout.LayoutParams(context.dp(Constants.CLOSE_BUTTON_SIZE_DP), context.dp(Constants.CLOSE_BUTTON_SIZE_DP), Gravity.END or Gravity.TOP).apply {
            topMargin = -context.dp(6f)
            rightMargin = -context.dp(8f)
        })
        column.addView(topRow, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, context.dp(Constants.SPARKLE_SIZE_DP)))

        val titleLabel = TextView(context).apply {
            text = widget.overlayOptions.floatingTitle ?: widget.overlayOptions.floatingBoxTextFirst ?: DefaultStrings.TITLE.value
            setTextColor(widget.overlayOptions.resolvedTextColor)
            textSize = 18f
            typeface = resolvedTypeface(widget.overlayOptions.floatingFontFamily, android.graphics.Typeface.BOLD)
            maxLines = 2
        }
        column.addView(titleLabel, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { topMargin = context.dp(12f) })

        val descLabel = TextView(context).apply {
            text = widget.overlayOptions.floatingDesc ?: widget.overlayOptions.floatingBoxTextSecond ?: DefaultStrings.DESCRIPTION.value
            setTextColor(withAlpha(widget.overlayOptions.resolvedTextColor, 0.95f))
            textSize = 13.5f
            typeface = resolvedTypeface(widget.overlayOptions.floatingFontFamily)
            maxLines = 4
        }
        column.addView(descLabel, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { topMargin = context.dp(6f) })

        val actionButton = TextView(context).apply {
            text = widget.overlayOptions.floatingButtonText ?: DefaultStrings.ACTION_BUTTON.value
            setTextColor(Color.BLACK)
            textSize = 15f
            typeface = resolvedTypeface(widget.overlayOptions.floatingFontFamily, android.graphics.Typeface.BOLD)
            gravity = Gravity.CENTER
            setPadding(context.dp(24f), 0, context.dp(24f), 0)
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = context.dp(20f).toFloat()
                setColor(Color.WHITE)
            }
            isClickable = true
            setOnClickListener { onOpenWidget() }
        }
        column.addView(
            actionButton,
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, context.dp(Constants.ACTION_BUTTON_HEIGHT_DP)).apply { topMargin = context.dp(16f) },
        )

        if (widget.overlayOptions.showLogo) {
            column.addView(
                buildBrandingRow(context),
                LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
                    topMargin = context.dp(10f)
                    gravity = Gravity.CENTER_HORIZONTAL
                },
            )
        }

        expandedContainer.addView(column, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT))

        addView(expandedContainer, FrameLayout.LayoutParams(expandedCardWidthPx, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER_VERTICAL or Gravity.END).apply {
            rightMargin = context.dp(Constants.EXPANDED_CARD_MARGIN_DP)
        })

        var downX = 0f
        expandedContainer.setOnTouchListener { view, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> downX = event.x
                MotionEvent.ACTION_UP -> {
                    val dx = event.x - downX
                    if (dx > context.dp(24f)) {
                        setState(TriggerState.COLLAPSED, animated = true)
                    } else if (abs(dx) < context.dp(8f)) {
                        view.performClick()
                    }
                }
            }
            true
        }
        expandedContainer.setOnClickListener { onOpenWidget() }
    }

    /** Small "Poltio" wordmark row shown at the bottom of the expanded card, gated by `showLogo`. */
    private fun buildBrandingRow(context: Context): LinearLayout = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL

        val dot = View(context).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(BRAND_DOT_COLOR)
            }
        }
        addView(dot, LinearLayout.LayoutParams(context.dp(6f), context.dp(6f)))

        val brandLabel = TextView(context).apply {
            text = "Poltio"
            setTextColor(BRAND_TEXT_COLOR)
            textSize = 10.5f
            typeface = resolvedTypeface(widget.overlayOptions.floatingFontFamily, android.graphics.Typeface.BOLD)
        }
        addView(brandLabel, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { leftMargin = context.dp(5f) })
    }

    private fun withAlpha(@androidx.annotation.ColorInt color: Int, alphaFraction: Float): Int {
        val alpha = (Color.alpha(color) * alphaFraction).toInt().coerceIn(0, 255)
        return Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color))
    }

    // MARK: - State management

    fun setState(state: TriggerState, animated: Boolean) {
        if (currentState == state) return
        currentState = state
        applyState(state, animated)
    }

    override fun resetToCollapsed(animated: Boolean) {
        setState(TriggerState.COLLAPSED, animated)
    }

    private fun measuredExpandedHeightPx(): Int {
        expandedContainer.measure(
            android.view.View.MeasureSpec.makeMeasureSpec(expandedCardWidthPx, android.view.View.MeasureSpec.EXACTLY),
            android.view.View.MeasureSpec.makeMeasureSpec(0, android.view.View.MeasureSpec.UNSPECIFIED),
        )
        return max(expandedContainer.measuredHeight, context.dp(Constants.EXPANDED_MIN_HEIGHT_DP))
    }

    private fun applyState(state: TriggerState, animated: Boolean) {
        val isExpanded = state == TriggerState.EXPANDED
        val targetWidth = if (isExpanded) expandedTotalWidthPx else collapsedWidthPx
        val targetHeight = if (isExpanded) measuredExpandedHeightPx() else collapsedHeightPx

        if (isExpanded) {
            expandedAtMs = android.os.SystemClock.elapsedRealtime()
        }

        sizeAnimator?.cancel()

        if (!animated) {
            setSizePx(targetWidth, targetHeight)
            collapsedContainer.alpha = if (isExpanded) 0f else 1f
            expandedContainer.alpha = if (isExpanded) 1f else 0f
            collapsedContainer.visibility = if (isExpanded) View.INVISIBLE else View.VISIBLE
            expandedContainer.visibility = if (isExpanded) View.VISIBLE else View.INVISIBLE
            return
        }

        val startWidth = layoutParams?.width?.takeIf { it > 0 } ?: width.takeIf { it > 0 } ?: collapsedWidthPx
        val startHeight = layoutParams?.height?.takeIf { it > 0 } ?: height.takeIf { it > 0 } ?: collapsedHeightPx

        collapsedContainer.visibility = View.VISIBLE
        expandedContainer.visibility = View.VISIBLE

        sizeAnimator = android.animation.ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 350
            interpolator = OvershootInterpolator(0.85f)
            addUpdateListener { animator ->
                val t = animator.animatedValue as Float
                setSizePx((startWidth + (targetWidth - startWidth) * t).toInt(), (startHeight + (targetHeight - startHeight) * t).toInt())
                collapsedContainer.alpha = if (isExpanded) 1f - t else t
                expandedContainer.alpha = if (isExpanded) t else 1f - t
            }
            addListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: android.animation.Animator) {
                    collapsedContainer.visibility = if (currentState == TriggerState.COLLAPSED) View.VISIBLE else View.INVISIBLE
                    expandedContainer.visibility = if (currentState == TriggerState.EXPANDED) View.VISIBLE else View.INVISIBLE
                }
            })
            start()
        }
    }

    private fun setSizePx(widthPx: Int, heightPx: Int) {
        val params = layoutParams ?: FrameLayout.LayoutParams(widthPx, heightPx)
        params.width = widthPx
        params.height = heightPx
        layoutParams = params
    }
}
