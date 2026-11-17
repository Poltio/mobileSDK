package com.poltio.sdk.ui

import android.animation.ValueAnimator
import android.app.Activity
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.LayerDrawable
import android.graphics.drawable.RippleDrawable
import android.provider.Settings
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.ViewOutlineProvider
import android.view.animation.DecelerateInterpolator
import android.view.animation.OvershootInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.graphics.ColorUtils
import com.poltio.sdk.PoltioExecutors
import com.poltio.sdk.PoltioOverlayOptions
import com.poltio.sdk.PoltioStackCard
import com.poltio.sdk.PoltioTriggerDismissalStore
import com.poltio.sdk.PoltioWidgetResponse

/**
 * The `stack` ("Multi") trigger: 2–5 glass cards fanned toward the middle of the screen, the first
 * one in front. Any card, front or back, opens its own content. × folds the fan into a pill showing
 * the front card (remembered for 48 hours); tapping the pill fans the cards out again.
 *
 * Android has no backdrop blur without extra libraries, so the cards are translucent and frosted
 * looking (a tinted gradient, a light rim and sheen) without blurring the app behind them.
 */
internal class PoltioFloatingStackTriggerView(
    context: Context,
    private val widget: PoltioWidgetResponse,
    private val cards: List<PoltioStackCard>,
    private val onOpenCard: (PoltioStackCard) -> Unit,
) : FrameLayout(context), PoltioTriggerPresentable {

    enum class TriggerState { FANNED, FOLDED }

    private class Layout(val cardW: Float, val cardH: Float, val stepX: Float, val stepY: Float, val tiltDeg: Float)

    companion object {
        /** How long a fold is remembered, matching web. */
        const val FOLD_REMEMBER_HOURS = 48.0
        private const val PILL_W = 250f
        private const val PILL_H = 64f
        private const val CLOSE_SIZE = 26f
        private val EXPANDED = Layout(168f, 216f, 26f, 12f, 4f)
        private val COMPACT = Layout(240f, 56f, 14f, 20f, 2f)

        /** The fold's key in [PoltioTriggerDismissalStore], kept apart from the widget's own public
         * id, which would hide the trigger outright. */
        fun foldKey(publicId: String) = "stack-fold:$publicId"

        /** Whether the user turned animations off (Developer options or Remove animations). */
        fun animationsRemoved(context: Context): Boolean =
            Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }

    private val options = widget.overlayOptions
    private val layout = if (options.isStackCompact) COMPACT else EXPANDED
    /** Direction toward the middle of the screen: back cards fan away from the docked corner. */
    private val fanX = if (options.isLeftDocked) 1f else -1f
    private val fanY = if (options.verticalPosition == "top") 1f else -1f
    /** Room for the fan beside and above (or below) the front card, plus slack for the tilt. */
    private val spreadX = layout.stepX * (cards.size - 1) + 24f
    private val spreadY = layout.stepY * (cards.size - 1) + 24f

    var state: TriggerState
        private set

    /** Front card first. */
    val cardViews: List<PoltioStackCardView>
    val closeButton = PoltioCloseGlyphView(context, PoltioOverlayOptions.resolvedColor(cards[0].textColor, Color.WHITE))
    val pillView = PoltioStackCardView(context, cards[0], PoltioStackCardView.Style.PILL, options)

    private var scrollUnfoldListener: ((Activity) -> Unit)? = null
    private val foldRemembered: Boolean

    init {
        clipChildren = false
        clipToPadding = false
        // Sized to hold the whole fan: touches only reach children inside this view's bounds, and
        // the empty corners stay unclickable, so they fall through to the host.
        layoutParams = LayoutParams(context.dp(layout.cardW + spreadX), context.dp(layout.cardH + spreadY))

        val style = if (options.isStackCompact) PoltioStackCardView.Style.COMPACT else PoltioStackCardView.Style.CARD
        cardViews = cards.map { PoltioStackCardView(context, it, style, options) }
        // Back cards first, so the front card draws, and takes touches, on top.
        cardViews.asReversed().forEach { cardView ->
            cardView.setOnClickListener { onOpenCard(cardView.card) }
            addAtCorner(cardView, layout.cardW, layout.cardH)
        }
        // TalkBack reads the front card first, then the ones behind it.
        cardViews.forEach { it.id = View.generateViewId() }
        cardViews.zipWithNext { front, behind -> behind.accessibilityTraversalAfter = front.id }

        closeButton.background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(ColorUtils.setAlphaComponent(Color.BLACK, 46))
        }
        // Above the cards' own elevation, or they'd draw over it and take its taps.
        closeButton.elevation = context.dp(8f).toFloat()
        closeButton.contentDescription = "Close"
        closeButton.setOnClickListener { handleCloseTap() }
        val closeY = if (options.isStackCompact) (layout.cardH - CLOSE_SIZE) / 2 else 8f
        addAtCorner(closeButton, CLOSE_SIZE, CLOSE_SIZE, offsetX = layout.cardW - CLOSE_SIZE - 8f, offsetY = closeY, cornerW = layout.cardW, cornerH = layout.cardH)

        pillView.setOnClickListener { handlePillTap() }
        pillView.contentDescription = PoltioTriggerAccessibility.label(cards[0].title, cards[0].desc) + ". Shows all cards."
        addAtCorner(pillView, PILL_W, PILL_H)

        foldRemembered = PoltioTriggerDismissalStore.isDismissed(context, foldKey(widget.publicId))
        val startsCollapsed = options.floatingInitialPosition?.trim()?.lowercase() == "collapsed"
        state = if (foldRemembered || startsCollapsed) TriggerState.FOLDED else TriggerState.FANNED
        if (state == TriggerState.FANNED) fanOut(animated = true) else showPill(animated = false)
    }

    /**
     * Adds [view] ([w]×[h] dp) so that a [cornerW]×[cornerH] box at the docked corner holds it at
     * ([offsetX], [offsetY]) from that box's top-left. Absolute LEFT/TOP: `floating-position` names
     * a physical side, so a right-to-left locale mustn't flip it.
     */
    private fun addAtCorner(
        view: View,
        w: Float,
        h: Float,
        offsetX: Float = 0f,
        offsetY: Float = 0f,
        cornerW: Float = w,
        cornerH: Float = h,
    ) {
        val totalW = layout.cardW + spreadX
        val totalH = layout.cardH + spreadY
        val boxX = if (fanX > 0) 0f else totalW - cornerW
        val boxY = if (fanY > 0) 0f else totalH - cornerH
        addView(view, LayoutParams(context.dp(w), context.dp(h), Gravity.TOP or Gravity.LEFT).apply {
            leftMargin = context.dp(boxX + offsetX)
            topMargin = context.dp(boxY + offsetY)
        })
    }

    /** Places card [index] in the fan: shifted toward the middle of the screen, smaller, tilted. */
    fun applyFanPose(view: View, index: Int) {
        val step = index.toFloat()
        view.translationX = context.dp(fanX * step * layout.stepX).toFloat()
        view.translationY = context.dp(fanY * step * layout.stepY).toFloat()
        view.rotation = -fanX * fanY * step * layout.tiltDeg
        view.rotationY = fanX * step * 7f
        view.scaleX = 1f - 0.05f * step
        view.scaleY = 1f - 0.05f * step
    }

    private fun resetPose(view: View, scale: Float) {
        view.translationX = 0f
        view.translationY = 0f
        view.rotation = 0f
        view.rotationY = 0f
        view.scaleX = scale
        view.scaleY = scale
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        // A collapsed start fans out once the host scrolls past the threshold, like web; a
        // remembered fold stays folded.
        if (state == TriggerState.FOLDED && !foldRemembered && scrollUnfoldListener == null) {
            val activity = context.findActivity() ?: return
            val viewRef = java.lang.ref.WeakReference(this)
            val listener: (Activity) -> Unit = { scrolledActivity ->
                PoltioExecutors.runOnMain {
                    val view = viewRef.get() ?: return@runOnMain
                    if (view.context.findActivity() == scrolledActivity && view.scrollUnfoldListener != null) {
                        view.scrollUnfoldListener = null
                        view.setState(TriggerState.FANNED, animated = true)
                    }
                }
            }
            scrollUnfoldListener = listener
            PoltioScrollObserver.onScrollPast(activity, options.floatingScrollThreshold.toFloat(), listener)
        }
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        stopObservingScroll()
        (cardViews + pillView).forEach { it.dispose() }
    }

    private fun stopObservingScroll() {
        scrollUnfoldListener?.let { PoltioScrollObserver.cancelScrollPast(it) }
        scrollUnfoldListener = null
    }

    // MARK: - State

    fun setState(newState: TriggerState, animated: Boolean) {
        if (state == newState) return
        state = newState
        if (newState == TriggerState.FANNED) fanOut(animated) else showPill(animated)
    }

    /** Closing a card's experience brings the stack back unchanged. */
    override fun resetToCollapsed(animated: Boolean) = Unit

    /** The staggered cascade: each card leaves the front position for its place in the fan, then a
     * soft glow crosses the cards three times to hint they're tappable. */
    private fun fanOut(animated: Boolean) {
        val animate = animated && !animationsRemoved(context)
        pillView.animate().cancel()
        pillView.animate().alpha(0f).setDuration(if (animate) 200L else 0L)
            .withEndAction { if (state == TriggerState.FANNED) pillView.visibility = View.GONE }.start()

        cardViews.forEachIndexed { index, cardView ->
            cardView.visibility = View.VISIBLE
            cardView.animate().cancel()
            if (!animate) {
                cardView.alpha = 1f
                applyFanPose(cardView, index)
                return@forEachIndexed
            }
            cardView.alpha = 0f
            resetPose(cardView, 0.85f)
            val step = index.toFloat()
            cardView.animate()
                .alpha(1f)
                .translationX(context.dp(fanX * step * layout.stepX).toFloat())
                .translationY(context.dp(fanY * step * layout.stepY).toFloat())
                .rotation(-fanX * fanY * step * layout.tiltDeg)
                .rotationY(fanX * step * 7f)
                .scaleX(1f - 0.05f * step)
                .scaleY(1f - 0.05f * step)
                .setStartDelay(90L * index)
                .setDuration(550)
                .setInterpolator(OvershootInterpolator(0.8f))
                .start()
            cardView.playGlow(startDelayMs = 600L + 90L * cardViews.size + 150L * index)
        }

        closeButton.visibility = View.VISIBLE
        closeButton.animate().cancel()
        closeButton.alpha = if (animate) 0f else 1f
        if (animate) closeButton.animate().alpha(1f).setStartDelay(300).setDuration(300).start()

        pillView.importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        cardViews.forEach { it.importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES }
    }

    /** Cards gather onto the front card and fade while the pill takes their place. */
    private fun showPill(animated: Boolean) {
        val animate = animated && !animationsRemoved(context)
        cardViews.forEach { cardView ->
            cardView.stopGlow()
            cardView.animate().cancel()
            cardView.animate().alpha(0f).translationX(0f).translationY(0f).rotation(0f).rotationY(0f)
                .scaleX(0.9f).scaleY(0.9f).setStartDelay(0).setDuration(if (animate) 280L else 0L)
                .setInterpolator(DecelerateInterpolator())
                .withEndAction { if (state == TriggerState.FOLDED) cardView.visibility = View.GONE }
                .start()
        }
        closeButton.animate().cancel()
        closeButton.animate().alpha(0f).setStartDelay(0).setDuration(if (animate) 200L else 0L)
            .withEndAction { if (state == TriggerState.FOLDED) closeButton.visibility = View.GONE }.start()

        pillView.visibility = View.VISIBLE
        pillView.animate().cancel()
        pillView.alpha = 0f
        pillView.scaleX = if (animate) 0.9f else 1f
        pillView.scaleY = pillView.scaleX
        pillView.animate().alpha(1f).scaleX(1f).scaleY(1f)
            .setStartDelay(if (animate) 150L else 0L).setDuration(if (animate) 400L else 0L)
            .setInterpolator(OvershootInterpolator(0.8f)).start()

        pillView.importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        cardViews.forEach { it.importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS }
    }

    // MARK: - Actions

    private fun handleCloseTap() {
        stopObservingScroll()
        PoltioTriggerDismissalStore.recordDismissal(context, foldKey(widget.publicId), FOLD_REMEMBER_HOURS)
        setState(TriggerState.FOLDED, animated = true)
    }

    private fun handlePillTap() {
        stopObservingScroll()
        setState(TriggerState.FANNED, animated = true)
    }
}

/**
 * One frosted card of the stack trigger, drawn as a vertical card, a compact pill (image and
 * title), or the folded pill (image, title and description). The whole card is one button.
 */
internal class PoltioStackCardView(
    context: Context,
    val card: PoltioStackCard,
    style: Style,
    options: PoltioOverlayOptions,
) : FrameLayout(context) {

    enum class Style { CARD, COMPACT, PILL }

    private val imageSlot = FrameLayout(context)
    private val imageLoader: PoltioTriggerIconLoader
    private val glow = GlowView(context)
    private var glowAnimator: ValueAnimator? = null

    init {
        val cardColor = PoltioOverlayOptions.resolvedColor(card.bg, options.resolvedBgColor)
        val textColor = PoltioOverlayOptions.resolvedColor(card.textColor, Color.WHITE)
        val radius = context.dp(if (style == Style.CARD) 22f else 28f).toFloat()
        val alpha = (card.alpha * 255).toInt()

        val tint = GradientDrawable(
            GradientDrawable.Orientation.TL_BR,
            intArrayOf(ColorUtils.setAlphaComponent(ColorUtils.blendARGB(cardColor, Color.WHITE, 0.35f), alpha), ColorUtils.setAlphaComponent(cardColor, alpha)),
        ).apply {
            cornerRadius = radius
            setStroke(context.dp(1f), ColorUtils.setAlphaComponent(Color.WHITE, 90))
        }
        // A soft white sheen over the top half reads as frosted glass.
        val sheen = GradientDrawable(
            GradientDrawable.Orientation.TOP_BOTTOM,
            intArrayOf(ColorUtils.setAlphaComponent(Color.WHITE, 46), Color.TRANSPARENT),
        ).apply { cornerRadius = radius }
        background = LayerDrawable(arrayOf(tint, sheen))
        foreground = RippleDrawable(ColorStateList.valueOf(ColorUtils.setAlphaComponent(Color.WHITE, 60)), null, GradientDrawable().apply { cornerRadius = radius; setColor(Color.WHITE) })
        outlineProvider = ViewOutlineProvider.BACKGROUND
        clipToOutline = true
        elevation = context.dp(6f).toFloat()
        cameraDistance = 8000 * resources.displayMetrics.density

        val imageSize = when (style) {
            Style.CARD -> 52f
            Style.COMPACT -> 36f
            Style.PILL -> 44f
        }
        imageSlot.background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(cardColor)
            setStroke(context.dp(1f), ColorUtils.setAlphaComponent(Color.WHITE, 128))
        }
        imageSlot.outlineProvider = ViewOutlineProvider.BACKGROUND
        imageSlot.clipToOutline = true
        // The loader lays its image over this anchor, filling the round slot.
        val imageAnchor = View(context)
        imageSlot.addView(imageAnchor, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        imageLoader = PoltioTriggerIconLoader(imageSlot, imageSize, ImageView.ScaleType.CENTER_CROP)
        card.imageUrl?.let { imageLoader.load(it, svgHint = false, imageAnchor) {} }

        val typeface = resolvedTypeface(options.floatingFontFamily)
        val title = TextView(context).apply {
            text = card.title
            setTextColor(textColor)
            textSize = if (style == Style.CARD) 16f else 14f
            this.typeface = resolvedTypeface(options.floatingFontFamily, android.graphics.Typeface.BOLD)
            maxLines = if (style == Style.CARD) 2 else 1
            ellipsize = TextUtils.TruncateAt.END
        }
        val desc = TextView(context).apply {
            text = card.desc
            setTextColor(ColorUtils.setAlphaComponent(textColor, 230))
            textSize = if (style == Style.CARD) 13f else 12f
            this.typeface = typeface
            maxLines = if (style == Style.CARD) 3 else 1
            ellipsize = TextUtils.TruncateAt.END
            visibility = if (card.desc.isNullOrBlank() || style == Style.COMPACT) View.GONE else View.VISIBLE
        }
        val texts = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            addView(title)
            addView(desc, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
                topMargin = context.dp(if (style == Style.CARD) 4f else 1f)
            })
        }

        val body = LinearLayout(context)
        if (style == Style.CARD) {
            body.orientation = LinearLayout.VERTICAL
            body.setPadding(context.dp(14f), context.dp(14f), context.dp(14f), context.dp(14f))
            body.addView(imageSlot, LinearLayout.LayoutParams(context.dp(imageSize), context.dp(imageSize)))
            body.addView(texts, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f).apply { topMargin = context.dp(10f) })
            val button = TextView(context).apply {
                text = card.button?.trim().takeUnless { it.isNullOrEmpty() } ?: "Start"
                setTextColor(Color.WHITE)
                textSize = 14f
                this.typeface = resolvedTypeface(options.floatingFontFamily, android.graphics.Typeface.BOLD)
                gravity = Gravity.CENTER
                maxLines = 1
                background = GradientDrawable().apply {
                    cornerRadius = context.dp(17f).toFloat()
                    setColor(PoltioOverlayOptions.resolvedColor(card.buttonBg, ColorUtils.blendARGB(cardColor, Color.BLACK, 0.3f)))
                }
            }
            body.addView(button, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, context.dp(34f)))
        } else {
            body.orientation = LinearLayout.HORIZONTAL
            body.gravity = Gravity.CENTER_VERTICAL
            // Compact cards leave room for the front card's ×.
            body.setPadding(context.dp(10f), 0, context.dp(if (style == Style.COMPACT) 40f else 16f), 0)
            body.addView(imageSlot, LinearLayout.LayoutParams(context.dp(imageSize), context.dp(imageSize)))
            body.addView(texts, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply { leftMargin = context.dp(10f) })
        }
        addView(body, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        addView(glow, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))

        isClickable = true
        isFocusable = true
        PoltioTriggerAccessibility.configureAsButton(
            this,
            PoltioTriggerAccessibility.label(card.title, card.desc.takeIf { style != Style.COMPACT }, card.button.takeIf { style == Style.CARD }),
        )
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        body.importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
    }

    /** Sweeps a soft highlight across the card three times, starting after [startDelayMs]. */
    fun playGlow(startDelayMs: Long) {
        glowAnimator?.cancel()
        glowAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 1300
            repeatCount = 2
            startDelay = startDelayMs
            addUpdateListener { glow.progress = it.animatedValue as Float }
            start()
        }
    }

    fun stopGlow() {
        glowAnimator?.cancel()
        glowAnimator = null
        glow.progress = -1f
    }

    val isGlowing: Boolean get() = glowAnimator?.isStarted == true

    fun dispose() {
        stopGlow()
        imageLoader.dispose()
    }

    /** A diagonal light band drawn at [progress] (0…1 across the card; negative hides it). */
    private class GlowView(context: Context) : View(context) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)

        var progress = -1f
            set(value) {
                field = value
                invalidate()
            }

        init {
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        }

        override fun onDraw(canvas: Canvas) {
            if (progress < 0f || width == 0) return
            val band = width * 0.6f
            val x = -band + (width + 2 * band) * progress
            paint.shader = LinearGradient(
                x, 0f, x + band, height * 0.4f,
                intArrayOf(Color.TRANSPARENT, ColorUtils.setAlphaComponent(Color.WHITE, 100), Color.TRANSPARENT),
                null, Shader.TileMode.CLAMP,
            )
            canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)
        }
    }
}
