package com.poltio.sdk.ui

import android.animation.Keyframe
import android.animation.ObjectAnimator
import android.animation.PropertyValuesHolder
import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.view.Gravity
import android.view.MotionEvent
import android.view.VelocityTracker
import android.view.View
import android.view.ViewOutlineProvider
import android.view.animation.DecelerateInterpolator
import android.view.animation.OvershootInterpolator
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import com.poltio.sdk.PoltioExecutors
import com.poltio.sdk.PoltioOverlayOptions
import com.poltio.sdk.PoltioWidgetResponse
import kotlin.math.abs
import kotlin.math.max

/**
 * Native floating pill trigger view supporting collapsed (circular bouncing) and expanded (pill
 * capsule) states.
 */
internal class PoltioFloatingPillTriggerView(
    context: Context,
    private val widget: PoltioWidgetResponse,
    private val onOpenWidget: () -> Unit,
    private val onDismissForever: (Double) -> Unit = {},
) : FrameLayout(context), PoltioTriggerPresentable {

    enum class TriggerState { COLLAPSED, EXPANDED }

    var currentState: TriggerState = TriggerState.COLLAPSED
        private set

    private val collapsedSizePx = context.dp(56f)

    private val pulsateRing = PulsateRingView(context, widget.overlayOptions)
    private val iconSlot = FrameLayout(context)
    private val sparkleIcon = PoltioSparkleIconView(context)
    private val iconLoader = PoltioTriggerIconLoader(iconSlot, 40f)
    private val textStack = LinearLayout(context)
    private val firstLabel = TextView(context)
    private val secondLabel = TextView(context)
    private val thirdLabel = TextView(context)
    private val closeButton: PoltioCloseGlyphView?

    private var widthAnimator: ValueAnimator? = null
    private var bounceAnimator: ObjectAnimator? = null
    private var pulsateAnimator: ValueAnimator? = null
    private val autoCollapseRunnable = Runnable {
        if (currentState == TriggerState.EXPANDED) setState(TriggerState.COLLAPSED, animated = true)
    }
    private val outsideInteractionListener: () -> Unit = {
        if (currentState == TriggerState.EXPANDED) setState(TriggerState.COLLAPSED, animated = true)
    }

    init {
        clipChildren = false
        clipToPadding = false

        val shouldStartExpanded = widget.overlayOptions.isInitialExpanded ||
            widget.overlayOptions.pillStartMode?.trim()?.lowercase() == "open"
        currentState = if (shouldStartExpanded) TriggerState.EXPANDED else TriggerState.COLLAPSED

        background = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = context.dp(28f).toFloat()
            setColor(widget.overlayOptions.resolvedBgColor)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            outlineProvider = ViewOutlineProvider.BACKGROUND
            elevation = context.dp(4f).toFloat()
        }

        addView(pulsateRing, FrameLayout.LayoutParams(collapsedSizePx, collapsedSizePx, Gravity.CENTER_VERTICAL or Gravity.END))

        addView(iconSlot, FrameLayout.LayoutParams(context.dp(40f), context.dp(40f), Gravity.TOP or Gravity.START).apply {
            topMargin = (collapsedSizePx - context.dp(40f)) / 2
        })
        iconSlot.addView(sparkleIcon, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))

        val accentColor = Color.rgb(224, 161, 89) // Warm Golden Tan (default accent)
        textStack.orientation = LinearLayout.VERTICAL
        textStack.gravity = Gravity.START

        firstLabel.text = widget.overlayOptions.textFirst ?: "Try our"
        firstLabel.setTextColor(PoltioOverlayOptions.resolvedColor(widget.overlayOptions.textColorFirst, Color.WHITE))
        firstLabel.textSize = 13f
        firstLabel.maxLines = 1
        textStack.addView(firstLabel)

        secondLabel.text = (widget.overlayOptions.textSecond ?: "PRODUCT").uppercase()
        secondLabel.setTextColor(PoltioOverlayOptions.resolvedColor(widget.overlayOptions.textColorSecond, accentColor))
        secondLabel.textSize = 15f
        secondLabel.setTypeface(secondLabel.typeface, android.graphics.Typeface.BOLD)
        secondLabel.letterSpacing = 0.05f
        secondLabel.maxLines = 1
        textStack.addView(secondLabel)

        thirdLabel.text = (widget.overlayOptions.textThird ?: "FINDER").uppercase()
        thirdLabel.setTextColor(PoltioOverlayOptions.resolvedColor(widget.overlayOptions.textColorThird, accentColor))
        thirdLabel.textSize = 15f
        thirdLabel.setTypeface(thirdLabel.typeface, android.graphics.Typeface.BOLD)
        thirdLabel.letterSpacing = 0.05f
        thirdLabel.maxLines = 1
        textStack.addView(thirdLabel)

        val textLeftPx = context.dp(14f) + context.dp(40f) + context.dp(8f)
        addView(
            textStack,
            FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER_VERTICAL or Gravity.START).apply {
                leftMargin = textLeftPx
            },
        )
        textStack.alpha = 0f

        closeButton = if (widget.overlayOptions.pillShowCloseButton) {
            PoltioCloseGlyphView(context, widget.overlayOptions.resolvedTextColor).apply {
                contentDescription = "Close"
                setOnClickListener { handleCloseTap() }
            }
        } else {
            null
        }
        closeButton?.let {
            addView(it, FrameLayout.LayoutParams(context.dp(28f), context.dp(28f), Gravity.CENTER_VERTICAL or Gravity.END).apply {
                rightMargin = context.dp(8f)
            })
        }

        isClickable = true
        setOnClickListener { handleTap() }
        setupSwipeToCollapse()

        iconLoader.load(widget.overlayOptions, sparkleIcon) { sparkleIcon.visibility = View.GONE }

        PoltioHostInteractionBus.addListener(outsideInteractionListener)
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        applyState(currentState, animated = false)
        if (widget.overlayOptions.isInitialActive) scheduleAutoCollapse()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        PoltioHostInteractionBus.removeListener(outsideInteractionListener)
        PoltioExecutors.main.removeCallbacks(autoCollapseRunnable)
        widthAnimator?.cancel()
        bounceAnimator?.cancel()
        pulsateAnimator?.cancel()
        iconLoader.dispose()
    }

    // MARK: - State Management

    fun setState(state: TriggerState, animated: Boolean = true) {
        if (currentState == state) return
        currentState = state
        applyState(state, animated)
    }

    override fun resetToCollapsed(animated: Boolean) {
        PoltioExecutors.main.removeCallbacks(autoCollapseRunnable)
        setState(TriggerState.COLLAPSED, animated)
    }

    private fun applyState(state: TriggerState, animated: Boolean) {
        val isExpanded = state == TriggerState.EXPANDED
        PoltioExecutors.main.removeCallbacks(autoCollapseRunnable)

        val targetWidth = if (isExpanded) calculateExpandedWidth() else collapsedSizePx
        val iconLeadingX = context.dp(14f).toFloat()
        val iconCenteredX = { width: Int -> (width - context.dp(40f)) / 2f }

        if (isExpanded) {
            stopBouncingAnimation()
            stopPulsateAnimation()
            if (widget.overlayOptions.isInitialActive) scheduleAutoCollapse()
        } else {
            startBouncingAnimation()
            startPulsateAnimation()
        }

        widthAnimator?.cancel()
        val startWidth = layoutParams?.width?.takeIf { it > 0 } ?: width.takeIf { it > 0 } ?: collapsedSizePx
        val startIconX = iconSlot.translationX
        val startTextAlpha = textStack.alpha

        if (!animated) {
            setWidthPx(targetWidth)
            iconSlot.translationX = if (isExpanded) iconLeadingX else iconCenteredX(targetWidth)
            textStack.alpha = if (isExpanded) 1f else 0f
            return
        }

        widthAnimator = ValueAnimator.ofInt(startWidth, targetWidth).apply {
            duration = 400
            interpolator = OvershootInterpolator(0.9f)
            addUpdateListener { animator ->
                val currentWidth = animator.animatedValue as Int
                setWidthPx(currentWidth)
                val fraction = animator.animatedFraction
                val targetIconX = if (isExpanded) iconLeadingX else iconCenteredX(targetWidth)
                iconSlot.translationX = startIconX + (targetIconX - startIconX) * fraction
                val targetTextAlpha = if (isExpanded) 1f else 0f
                textStack.alpha = startTextAlpha + (targetTextAlpha - startTextAlpha) * fraction
            }
            start()
        }
    }

    private fun setWidthPx(widthPx: Int) {
        val params = layoutParams ?: FrameLayout.LayoutParams(widthPx, collapsedSizePx)
        params.width = widthPx
        layoutParams = params
    }

    private fun calculateExpandedWidth(): Int {
        val textWidth = listOf(firstLabel, secondLabel, thirdLabel).maxOf { it.paint.measureText(it.text.toString()) }
        val trailingReserve = if (widget.overlayOptions.pillShowCloseButton) context.dp(20f + 2f + 28f) else context.dp(20f)
        val total = context.dp(14f) + context.dp(40f) + context.dp(8f) + textWidth.toInt() + trailingReserve
        return max(total, context.dp(210f))
    }

    // MARK: - Pulsate

    private fun startPulsateAnimation() {
        if (!widget.overlayOptions.showPulsate) return
        if (pulsateAnimator?.isRunning == true) return
        pulsateAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 1600
            repeatCount = ValueAnimator.INFINITE
            interpolator = DecelerateInterpolator()
            addUpdateListener { pulsateRing.progress = it.animatedValue as Float }
            start()
        }
    }

    private fun stopPulsateAnimation() {
        pulsateAnimator?.cancel()
        pulsateAnimator = null
        pulsateRing.progress = -1f
    }

    // MARK: - Bounce

    private fun startBouncingAnimation() {
        if (bounceAnimator?.isRunning == true) return
        val fractions = floatArrayOf(0f, 0.45f, 0.60f, 0.75f, 0.88f, 0.96f, 1f)
        val values = floatArrayOf(0f, 0f, -context.dp(8f).toFloat(), context.dp(2f).toFloat(), -context.dp(4f).toFloat(), 0f, 0f)
        val keyframes = fractions.indices.map { i -> Keyframe.ofFloat(fractions[i], values[i]) }.toTypedArray()
        val holder = PropertyValuesHolder.ofKeyframe(View.TRANSLATION_Y, *keyframes)
        bounceAnimator = ObjectAnimator.ofPropertyValuesHolder(this, holder).apply {
            duration = 2400
            repeatCount = ValueAnimator.INFINITE
            start()
        }
    }

    private fun stopBouncingAnimation() {
        bounceAnimator?.cancel()
        bounceAnimator = null
        translationY = 0f
    }

    // MARK: - Auto collapse

    private fun scheduleAutoCollapse() {
        PoltioExecutors.main.removeCallbacks(autoCollapseRunnable)
        PoltioExecutors.main.postDelayed(autoCollapseRunnable, 2000)
    }

    // MARK: - Gestures

    private fun setupSwipeToCollapse() {
        var velocityTracker: VelocityTracker? = null
        var downX = 0f
        setOnTouchListener { view, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.x
                    velocityTracker = VelocityTracker.obtain().also { it.addMovement(event) }
                }
                MotionEvent.ACTION_MOVE -> velocityTracker?.addMovement(event)
                MotionEvent.ACTION_UP -> {
                    velocityTracker?.addMovement(event)
                    val dx = event.x - downX
                    velocityTracker?.recycle()
                    velocityTracker = null
                    if (currentState == TriggerState.EXPANDED && abs(dx) > context.dp(24f)) {
                        setState(TriggerState.COLLAPSED, animated = true)
                    } else {
                        view.performClick()
                    }
                }
                MotionEvent.ACTION_CANCEL -> {
                    velocityTracker?.recycle()
                    velocityTracker = null
                }
            }
            true
        }
    }

    private fun handleTap() {
        if (currentState == TriggerState.COLLAPSED) {
            setState(TriggerState.EXPANDED, animated = true)
        } else {
            onOpenWidget()
        }
    }

    private fun handleCloseTap() {
        PoltioExecutors.main.removeCallbacks(autoCollapseRunnable)
        onDismissForever(widget.overlayOptions.pillCloseRememberDuration)
    }

    /** Pulsating ring drawn behind the collapsed puck, gated by `showPulsate`. */
    private class PulsateRingView(context: Context, overlayOptions: PoltioOverlayOptions) : View(context) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            color = PoltioOverlayOptions.resolvedColor(overlayOptions.pulsateColor, Color.WHITE)
        }

        /** -1 hides the ring entirely; 0..1 drives the scale/opacity of one pulsate cycle. */
        var progress: Float = -1f
            set(value) {
                field = value
                invalidate()
            }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            if (progress < 0f) return
            val baseRadius = minOf(width, height) / 2f
            val radius = baseRadius * (1f + 0.6f * progress)
            paint.alpha = (255 * 0.35f * (1f - progress)).toInt().coerceIn(0, 255)
            canvas.drawCircle(width / 2f, height / 2f, radius, paint)
        }
    }
}
