package com.poltio.sdk.ui

import android.animation.ValueAnimator
import android.app.Activity
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.LinearGradient
import android.graphics.Outline
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.os.Build
import android.provider.Settings
import android.text.TextPaint
import android.text.TextUtils
import android.util.TypedValue
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
import java.util.Locale
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin

/** Web's em on phones (13px): the stack's sizes are web's, in em, as dp. */
private const val EM = 13f

/** The warm tone of web's shadows and shades. */
private val SHADE = Color.rgb(40, 22, 12)

private fun white(alpha: Float) = ColorUtils.setAlphaComponent(Color.WHITE, (alpha * 255).roundToInt())

private fun withAlpha(color: Int, alpha: Float) = ColorUtils.setAlphaComponent(color, (Color.alpha(color) * alpha).roundToInt())

/** A linear gradient along a CSS angle (0deg points up, 90deg right) across [r], as CSS sizes it. */
private fun cssGradient(r: RectF, degrees: Float, colors: IntArray, positions: FloatArray?): LinearGradient {
    val rad = Math.toRadians(degrees.toDouble())
    val dx = sin(rad).toFloat()
    val dy = -cos(rad).toFloat()
    val half = (abs(r.width() * dx) + abs(r.height() * dy)) / 2
    return LinearGradient(
        r.centerX() - dx * half, r.centerY() - dy * half, r.centerX() + dx * half, r.centerY() + dy * half,
        colors, positions, Shader.TileMode.CLAMP,
    )
}

/**
 * The `stack` ("Multi") trigger: 2–5 glass cards stacked toward the middle of the screen, the first
 * one in front. Back cards stand upright and only peek out: odd ones past the front card's top edge,
 * even ones past its side. Any card, front or back, opens its own content. × folds the stack into a
 * pill showing the front card (remembered for 48 hours); tapping the pill brings the cards back.
 *
 * Android has no backdrop blur without extra libraries, so the glass is translucent (the card's tint,
 * a sheen, light caught in its edges and a bevel rim) without blurring the app behind it.
 */
internal class PoltioFloatingStackTriggerView(
    context: Context,
    private val widget: PoltioWidgetResponse,
    private val cards: List<PoltioStackCard>,
    private val onOpenCard: (PoltioStackCard) -> Unit,
) : FrameLayout(context), PoltioTriggerPresentable {

    enum class TriggerState { FANNED, FOLDED }

    /** Where a back card rests, in em toward the middle of the screen. */
    data class Place(val up: Boolean, val side: Float, val rise: Float)

    companion object {
        /** How long a fold is remembered, matching web. */
        const val FOLD_REMEMBER_HOURS = 48.0
        private const val CLOSE_SIZE = 26f
        private const val PILL_H = 4.5f * EM
        private const val PILL_MAX_W = 21f * EM

        /** The fold's key in [PoltioTriggerDismissalStore], kept apart from the widget's own public
         * id, which would hide the trigger outright. */
        fun foldKey(publicId: String) = "stack-fold:$publicId"

        /** Whether the user turned animations off (Developer options or Remove animations). */
        fun animationsRemoved(context: Context): Boolean =
            Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f

        /** Back card [index] (1-based): odd ones peek past the front card's top edge, even ones past
         * its side. Compact pills only stack upward. */
        fun place(index: Int, compact: Boolean): Place {
            if (compact) return Place(true, 0f, 2.9f * index)
            val step = ((index + 1) / 2 - 1).toFloat()
            return if (index % 2 == 1) Place(true, 0.5f + 0.8f * step, 3.4f + 2.8f * step) else Place(false, 3.6f + 2.8f * step, 1.6f + 0.5f * step)
        }
    }

    private val options = widget.overlayOptions
    private val compact = options.isStackCompact
    private val cardW = if (compact) 16f * EM else 13.5f * EM
    private val cardH = if (compact) 3.75f * EM else 16.5f * EM
    /** Direction toward the middle of the screen: back cards peek out away from the docked corner. */
    private val fanX = if (options.isLeftDocked) 1f else -1f
    private val fanY = if (options.verticalPosition == "top") 1f else -1f
    /** Room beside and above (or below) the front card for the back cards and the compact ×, plus
     * slack for their shadows; at least wide enough for the pill. */
    private val totalW = maxOf(
        cardW + ((1 until cards.size).maxOfOrNull { place(it, compact).side } ?: 0f) * EM + (if (compact) 2.1f * EM else 0f) + 24f,
        PILL_MAX_W,
    )
    private val totalH = cardH + ((1 until cards.size).maxOfOrNull { place(it, compact).rise } ?: 0f) * EM + 24f
    /** Set once the visitor opens a card or folds them: the light sweep was only a hint. */
    private var hinted = false

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
        // Sized to hold the whole stack: touches only reach children inside this view's bounds, and
        // the empty corners stay unclickable, so they fall through to the host.
        layoutParams = LayoutParams(context.dp(totalW), context.dp(totalH))

        cardViews = cards.mapIndexed { index, card ->
            val style = when {
                compact -> PoltioStackCardView.Style.COMPACT
                index == 0 -> PoltioStackCardView.Style.CARD
                place(index, false).up -> PoltioStackCardView.Style.UP
                else -> PoltioStackCardView.Style.SIDE
            }
            PoltioStackCardView(context, card, style, options)
        }
        // Back cards first, so the front card draws, and takes touches, on top.
        cardViews.asReversed().forEach { cardView ->
            cardView.setOnClickListener { openCard(cardView.card) }
            addAtCorner(cardView, cardW, cardH)
        }
        // TalkBack reads the front card first, then the ones behind it.
        cardViews.forEach { it.id = View.generateViewId() }
        cardViews.zipWithNext { front, behind -> behind.accessibilityTraversalAfter = front.id }

        closeButton.background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(ColorUtils.setAlphaComponent(Color.BLACK, 71))
        }
        // Above the cards' own elevation, or they'd draw over it and take its taps.
        closeButton.elevation = context.dp(10f).toFloat()
        closeButton.contentDescription = "Close"
        closeButton.setOnClickListener { handleCloseTap() }
        // Compact: beside the front pill, toward the middle of the screen, clear of the pills above it.
        val closeX = when {
            !compact -> cardW - CLOSE_SIZE - 8f
            fanX > 0 -> cardW + 4.5f
            else -> -CLOSE_SIZE - 4.5f
        }
        val closeY = if (compact) (cardH - CLOSE_SIZE) / 2 else 8f
        addAtCorner(closeButton, CLOSE_SIZE, CLOSE_SIZE, offsetX = closeX, offsetY = closeY, cornerW = cardW, cornerH = cardH)

        pillView.setOnClickListener { handlePillTap() }
        pillView.contentDescription = PoltioTriggerAccessibility.label(cards[0].title, cards[0].desc) + ". Shows all cards."
        // As wide as its content, up to web's 21em; absolute LEFT/RIGHT, like addAtCorner.
        addView(
            pillView,
            LayoutParams(LayoutParams.WRAP_CONTENT, context.dp(PILL_H), (if (fanX > 0) Gravity.LEFT else Gravity.RIGHT) or (if (fanY > 0) Gravity.TOP else Gravity.BOTTOM)),
        )

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
        val boxX = if (fanX > 0) 0f else totalW - cornerW
        val boxY = if (fanY > 0) 0f else totalH - cornerH
        addView(view, LayoutParams(context.dp(w), context.dp(h), Gravity.TOP or Gravity.LEFT).apply {
            leftMargin = context.dp(boxX + offsetX)
            topMargin = context.dp(boxY + offsetY)
        })
    }

    /** Card [index]'s resting translation and scale: upright, shifted toward the middle of the
     * screen and drawn as web's perspective draws a card pushed 30px further back per card. */
    private fun fanPose(index: Int): Triple<Float, Float, Float> {
        if (index == 0) return Triple(0f, 0f, 1f)
        val place = place(index, compact)
        val scale = 900f / (900f + 30f * index)
        val unit = EM * resources.displayMetrics.density * scale
        return Triple(fanX * place.side * unit, fanY * place.rise * unit, scale)
    }

    /** Places card [index] where it rests in the stack. */
    fun applyFanPose(view: View, index: Int) {
        val (x, y, scale) = fanPose(index)
        view.translationX = x
        view.translationY = y
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

    /** The staggered cascade: each card rises from the docked edge into its place, then light sweeps
     * across the cards three times to hint they're tappable. */
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
            cardView.translationX = 0f
            cardView.translationY = -fanY * context.dp(1.5f * EM)
            cardView.scaleX = 0.9f
            cardView.scaleY = 0.9f
            val (x, y, scale) = fanPose(index)
            cardView.animate()
                .alpha(1f)
                .translationX(x)
                .translationY(y)
                .scaleX(scale)
                .scaleY(scale)
                .setStartDelay(90L * index)
                .setDuration(550)
                .setInterpolator(OvershootInterpolator(0.8f))
                .start()
            if (!hinted) cardView.playGlow(startDelayMs = 700L + 300L * index)
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
            cardView.animate().alpha(0f).translationX(0f).translationY(0f)
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

    private fun openCard(card: PoltioStackCard) {
        hinted = true
        cardViews.forEach { it.stopGlow() }
        onOpenCard(card)
    }

    private fun handleCloseTap() {
        stopObservingScroll()
        hinted = true
        PoltioTriggerDismissalStore.recordDismissal(context, foldKey(widget.publicId), FOLD_REMEMBER_HOURS)
        setState(TriggerState.FOLDED, animated = true)
    }

    private fun handlePillTap() {
        stopObservingScroll()
        setState(TriggerState.FANNED, animated = true)
    }
}

/**
 * One glass card of the stack trigger, drawn as the front card, a back card peeking past the front
 * one's top edge ([Style.UP]) or side ([Style.SIDE]), a compact pill, or the folded pill. The whole
 * card is one button.
 */
internal class PoltioStackCardView(
    context: Context,
    val card: PoltioStackCard,
    val style: Style,
    options: PoltioOverlayOptions,
) : FrameLayout(context) {

    enum class Style { CARD, UP, SIDE, COMPACT, PILL }

    private var imageLoader: PoltioTriggerIconLoader? = null
    private val glow = GlowView(context)
    private var glowAnimator: ValueAnimator? = null
    private val density = resources.displayMetrics.density

    /** [em] of web's em, in px. */
    private fun px(em: Float) = context.dp(em * EM)

    init {
        val cardColor = PoltioOverlayOptions.resolvedColor(card.bg, options.resolvedBgColor)
        val textColor = PoltioOverlayOptions.resolvedColor(card.textColor, Color.WHITE)
        val buttonColor = PoltioOverlayOptions.resolvedColor(card.buttonBg, ColorUtils.blendARGB(cardColor, Color.BLACK, 0.3f))
        val regular = resolvedTypeface(options.floatingFontFamily)
        val bold = resolvedTypeface(options.floatingFontFamily, Typeface.BOLD)
        val radius = px(
            when (style) {
                Style.CARD, Style.UP, Style.SIDE -> 1.5f
                Style.COMPACT -> 1.875f
                Style.PILL -> 1.4f
            },
        ).toFloat()
        val ring = if (options.isStackCompact) 0.15f else 0.2f
        val buttonText = card.button?.trim().takeUnless { it.isNullOrEmpty() } ?: "Start"

        background = PoltioGlassDrawable(cardColor, card.alpha, radius, density)
        foreground = RippleDrawable(ColorStateList.valueOf(ColorUtils.setAlphaComponent(Color.WHITE, 60)), null, GradientDrawable().apply { cornerRadius = radius; setColor(Color.WHITE) })
        outlineProvider = ViewOutlineProvider.BACKGROUND
        clipToOutline = true
        // The lifted shadow, in web's warm tone where the platform can tint it.
        elevation = context.dp(8f).toFloat()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            outlineSpotShadowColor = SHADE
            outlineAmbientShadowColor = SHADE
        }

        when (style) {
            Style.CARD -> {
                val body = LinearLayout(context).apply {
                    orientation = LinearLayout.VERTICAL
                    setPadding(px(1f), px(1f), px(1f), px(1f))
                }
                val head = LinearLayout(context).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                }
                head.addView(imageSlot(4.5f, ring), LinearLayout.LayoutParams(px(4.5f), px(4.5f)))
                val name = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
                name.addView(text(card.title, 1.05f, textColor, bold, lines = 2))
                name.addView(line(textColor), LinearLayout.LayoutParams(px(1.6f), context.dp(2f)).apply { topMargin = px(0.5f) })
                head.addView(name, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply { leftMargin = px(0.65f) })
                body.addView(head)
                val desc = text(card.desc, 0.85f, textColor, regular, lines = 3).apply { setLineSpacing(px(0.17f).toFloat(), 1f) }
                body.addView(desc, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { topMargin = px(0.75f) })
                // Pushes START to the bottom.
                body.addView(View(context), LinearLayout.LayoutParams(0, 0, 1f))
                val cta = gloss(text(buttonText.uppercase(Locale.getDefault()), 0.85f, Color.WHITE, bold, spacing = 0.1f).apply { setPadding(px(0.85f), 0, px(0.85f), 0) }, buttonColor, 0.85f)
                body.addView(cta, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, px(2.75f * 0.85f)).apply { topMargin = px(0.55f) })
                addView(body, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
            }
            Style.UP -> {
                // Its full-size image moves into the strip showing past the front card's edge,
                // beside a spaced label.
                val edge = if (options.verticalPosition == "top") Gravity.BOTTOM else Gravity.TOP
                addView(imageSlot(4.5f, ring), LayoutParams(px(4.5f), px(4.5f), Gravity.LEFT or edge).apply {
                    leftMargin = px(1f)
                    topMargin = px(0.7f)
                    bottomMargin = px(0.7f)
                })
                addView(text(card.title.uppercase(Locale.getDefault()), 0.75f, textColor, bold, spacing = 0.14f), LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT, Gravity.LEFT or edge).apply {
                    leftMargin = px(1f + 4.5f + 0.65f)
                    rightMargin = px(1f)
                    topMargin = px(0.7f + 1.15f * 0.75f)
                    bottomMargin = topMargin
                })
            }
            Style.SIDE -> {
                // Its full-size image moves to the bottom of the strip showing past the front card's
                // side, under a vertical label.
                val onLeft = !options.isLeftDocked
                val side = if (onLeft) Gravity.LEFT else Gravity.RIGHT
                addView(imageSlot(4.5f, ring), LayoutParams(px(4.5f), px(4.5f), Gravity.BOTTOM or side).apply {
                    leftMargin = px(0.7f)
                    rightMargin = px(0.7f)
                    bottomMargin = px(0.7f)
                })
                val spine = SpineView(context, card.title, textColor, bold, upward = onLeft)
                addView(spine, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT, Gravity.TOP or side).apply {
                    topMargin = px(1.2f * 0.75f)
                    leftMargin = px(0.6f * 0.75f)
                    rightMargin = leftMargin
                })
            }
            Style.COMPACT -> {
                val body = LinearLayout(context).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                    setPadding(px(0.45f), 0, px(0.6f), 0)
                }
                body.addView(imageSlot(2.85f, ring), LinearLayout.LayoutParams(px(2.85f), px(2.85f)))
                body.addView(text(card.title, 0.95f, textColor, bold), LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                    leftMargin = px(0.6f)
                    rightMargin = px(0.6f)
                })
                body.addView(gloss(ArrowGlyphView(context, textColor), buttonColor, 1f), LinearLayout.LayoutParams(px(1.9f), px(1.9f)))
                addView(body, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
            }
            Style.PILL -> {
                val body = LinearLayout(context).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                    setPadding(px(0.55f), 0, px(0.55f), 0)
                }
                body.addView(imageSlot(3.3f, ring), LinearLayout.LayoutParams(px(3.3f), px(3.3f)))
                val texts = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
                texts.addView(text(card.title, 0.95f, textColor, bold))
                if (!options.isStackCompact) {
                    texts.addView(line(textColor), LinearLayout.LayoutParams(px(1.3f), context.dp(2f)).apply {
                        topMargin = px(0.3f)
                        bottomMargin = px(0.25f)
                    })
                }
                if (!card.desc.isNullOrBlank()) texts.addView(text(card.desc, 0.75f, textColor, regular))
                // Past web's max width, the texts truncate before START does.
                body.addView(texts, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                    leftMargin = px(0.7f)
                    rightMargin = px(0.7f)
                })
                val cta = gloss(text(buttonText.uppercase(Locale.getDefault()), 0.75f, Color.WHITE, bold, spacing = 0.1f).apply { setPadding(px(1.1f * 0.75f), 0, px(1.1f * 0.75f), 0) }, buttonColor, 0.75f)
                body.addView(cta, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, px(2.4f * 0.75f)))
                addView(body, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.MATCH_PARENT))
            }
        }
        addView(glow, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))

        isClickable = true
        isFocusable = true
        PoltioTriggerAccessibility.configureAsButton(
            this,
            PoltioTriggerAccessibility.label(card.title, card.desc.takeIf { style != Style.COMPACT }, card.button.takeIf { style == Style.CARD || style == Style.UP || style == Style.SIDE }),
        )
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        for (i in 0 until childCount) getChildAt(i).importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
    }

    /** The pill is as wide as its content, up to web's 21em. */
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        if (style != Style.PILL) return super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        val max = px(21f)
        val size = if (MeasureSpec.getMode(widthMeasureSpec) == MeasureSpec.UNSPECIFIED) max else min(MeasureSpec.getSize(widthMeasureSpec), max)
        super.onMeasure(MeasureSpec.makeMeasureSpec(size, MeasureSpec.AT_MOST), heightMeasureSpec)
    }

    /** The round image in a white ring, lifted off the glass. */
    private fun imageSlot(sizeEm: Float, ringEm: Float): FrameLayout {
        val slot = FrameLayout(context)
        slot.background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(white(0.3f))
        }
        // The ring draws over the image.
        slot.foreground = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setStroke(px(ringEm), white(0.75f))
        }
        slot.outlineProvider = ViewOutlineProvider.BACKGROUND
        slot.clipToOutline = true
        slot.elevation = context.dp(3f).toFloat()
        // The loader lays its image over this anchor, filling the round slot.
        val anchor = View(context)
        slot.addView(anchor, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        val loader = PoltioTriggerIconLoader(slot, sizeEm * EM, ImageView.ScaleType.CENTER_CROP)
        card.imageUrl?.let { loader.load(it, svgHint = false, anchor) {} }
        imageLoader = loader
        return slot
    }

    private fun text(value: String?, sizeEm: Float, color: Int, typeface: Typeface, lines: Int = 1, spacing: Float = 0f) = TextView(context).apply {
        text = value
        setTextColor(color)
        textSize = sizeEm * EM
        this.typeface = typeface
        maxLines = lines
        ellipsize = TextUtils.TruncateAt.END
        letterSpacing = spacing
        includeFontPadding = false
        setShadowLayer(2f * density, 0f, density, ColorUtils.setAlphaComponent(Color.BLACK, 46))
    }

    /** The short white line under a title. */
    private fun line(color: Int) = View(context).apply {
        background = GradientDrawable().apply {
            cornerRadius = density
            setColor(color)
        }
        alpha = 0.85f
    }

    /** [content] centered on a glossy 3D face in the button color; [sizeEm] is the button's font size. */
    private fun gloss(content: View, color: Int, sizeEm: Float) = FrameLayout(context).apply {
        val unit = sizeEm * EM * density
        background = PoltioGlossDrawable(color, unit, density)
        outlineProvider = ViewOutlineProvider.BACKGROUND
        // The soft drop under the button.
        elevation = 0.35f * unit
        addView(content, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT, Gravity.CENTER))
    }

    /** Sweeps a band of light across the glass three times, starting after [startDelayMs]. */
    fun playGlow(startDelayMs: Long) {
        glowAnimator?.cancel()
        glowAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 1100
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
        imageLoader?.dispose()
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
                intArrayOf(Color.TRANSPARENT, white(0.5f), Color.TRANSPARENT),
                null, Shader.TileMode.CLAMP,
            )
            canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)
        }
    }

    /** The side card's vertical label behind a short line: read upward when the strip is on the
     * left, downward when it's on the right. */
    private class SpineView(context: Context, title: String, color: Int, typeface: Typeface, private val upward: Boolean) : View(context) {
        private val unit = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, 0.75f * EM, resources.displayMetrics)
        private val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            this.typeface = typeface
            textSize = unit
            letterSpacing = 0.12f
            setShadowLayer(2f * resources.displayMetrics.density, 0f, resources.displayMetrics.density, ColorUtils.setAlphaComponent(Color.BLACK, 46))
        }
        private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            alpha = (Color.alpha(color) * 0.85f).roundToInt()
        }
        private val lead = 2f * unit
        private val text = TextUtils.ellipsize(title.uppercase(Locale.getDefault()), paint, 9f * unit - lead, TextUtils.TruncateAt.END).toString()

        init {
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        }

        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            setMeasuredDimension(ceil(paint.fontSpacing).toInt(), ceil(lead + paint.measureText(text)).toInt())
        }

        override fun onDraw(canvas: Canvas) {
            canvas.save()
            // Lays the label out along x, from the bottom up or the top down.
            if (upward) {
                canvas.rotate(-90f)
                canvas.translate(-height.toFloat(), 0f)
            } else {
                canvas.rotate(90f)
                canvas.translate(0f, -width.toFloat())
            }
            val mid = width / 2f
            val half = resources.displayMetrics.density
            canvas.drawRoundRect(0f, mid - half, 1.3f * unit, mid + half, half, half, linePaint)
            canvas.drawText(text, lead, mid - (paint.ascent() + paint.descent()) / 2, paint)
            canvas.restore()
        }
    }

    /** Web's arrow icon: a shaft and a head. */
    private class ArrowGlyphView(context: Context, color: Int) : View(context) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }

        init {
            val size = (14 * resources.displayMetrics.density).roundToInt()
            minimumWidth = size
            minimumHeight = size
        }

        override fun onDraw(canvas: Canvas) {
            val s = width / 24f
            paint.strokeWidth = 2.4f * s
            canvas.drawLine(5 * s, 12 * s, 19 * s, 12 * s, paint)
            canvas.drawLine(13 * s, 6 * s, 19 * s, 12 * s, paint)
            canvas.drawLine(19 * s, 12 * s, 13 * s, 18 * s, paint)
        }
    }
}

/** A drawable that ignores alpha and color filters: its colors are fixed by the design. */
private abstract class PoltioPaintedDrawable : Drawable() {
    override fun setAlpha(alpha: Int) = Unit

    override fun setColorFilter(colorFilter: ColorFilter?) = Unit

    @Deprecated("Deprecated in Java")
    override fun getOpacity() = PixelFormat.TRANSLUCENT
}

/**
 * A slab of glass: light caught inside its top and left edges and a shade inside the opposite ones,
 * the card's tint under a white sheen at the card's opacity, and a bevel rim brightest where the
 * light hits. The view's outline clips it to its rounded shape.
 */
private class PoltioGlassDrawable(tint: Int, private val opacity: Float, private val radius: Float, private val density: Float) : PoltioPaintedDrawable() {
    private val em = EM * density
    private val tinted = withAlpha(tint, opacity)
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val rimPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 1.5f * density
    }
    private val rect = RectF()
    private val rimRect = RectF()
    private var edges: List<Shader> = emptyList()
    private var sheen: Shader? = null
    private var corner = 0f

    override fun onBoundsChange(bounds: Rect) {
        rect.set(bounds)
        corner = min(radius, rect.height() / 2)
        rimRect.set(rect)
        rimRect.inset(0.75f * density, 0.75f * density)
        // The bright lip along the top, then the edge light fading inward.
        edges = listOf(
            LinearGradient(0f, rect.top, 0f, rect.top + 0.7f * em, intArrayOf(white(0.8f), white(0.3f), Color.TRANSPARENT), floatArrayOf(0f, 0.1f, 1f), Shader.TileMode.CLAMP),
            LinearGradient(rect.left, 0f, rect.left + 0.5f * em, 0f, white(0.35f), Color.TRANSPARENT, Shader.TileMode.CLAMP),
            LinearGradient(0f, rect.bottom, 0f, rect.bottom - 0.8f * em, withAlpha(SHADE, 0.18f), Color.TRANSPARENT, Shader.TileMode.CLAMP),
            LinearGradient(rect.right, 0f, rect.right - 0.6f * em, 0f, withAlpha(SHADE, 0.12f), Color.TRANSPARENT, Shader.TileMode.CLAMP),
        )
        sheen = cssGradient(rect, 155f, intArrayOf(white(0.5f), white(0.12f), white(0.04f), white(0.2f)), floatArrayOf(0f, 0.38f, 0.62f, 1f))
        rimPaint.shader = cssGradient(rect, 150f, intArrayOf(white(0.95f), white(0.25f), white(0.05f), white(0.5f), white(0.9f)), floatArrayOf(0f, 0.3f, 0.55f, 0.85f, 1f))
    }

    override fun draw(canvas: Canvas) {
        paint.color = Color.BLACK
        edges.forEach {
            paint.shader = it
            canvas.drawRect(rect, paint)
        }
        paint.shader = null
        paint.color = tinted
        canvas.drawRect(rect, paint)
        // The sheen is part of the tint, so it takes the card's opacity too.
        paint.color = Color.BLACK
        paint.alpha = (opacity * 255).roundToInt()
        paint.shader = sheen
        canvas.drawRect(rect, paint)
        paint.shader = null
        canvas.drawRoundRect(rimRect, corner - 0.75f * density, corner - 0.75f * density, rimPaint)
    }

    override fun getOutline(outline: Outline) {
        outline.setRoundRect(bounds, min(radius, bounds.height() / 2f))
    }
}

/** A glossy 3D button face in the button color: a lit top half under a shine and a shaded base;
 * its view's elevation gives the soft drop. [unit] is web's em for the button, in px. */
private class PoltioGlossDrawable(private val color: Int, private val unit: Float, private val density: Float) : PoltioPaintedDrawable() {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val rect = RectF()
    private val shineRect = RectF()
    private val borderRect = RectF()
    private var gloss: Shader? = null
    private var shine: Shader? = null

    override fun onBoundsChange(bounds: Rect) {
        rect.set(bounds)
        borderRect.set(rect)
        borderRect.inset(density / 2, density / 2)
        gloss = LinearGradient(0f, rect.top, 0f, rect.bottom, intArrayOf(white(0.3f), white(0f), ColorUtils.setAlphaComponent(Color.BLACK, 36)), floatArrayOf(0f, 0.5f, 1f), Shader.TileMode.CLAMP)
        val top = rect.top + 0.14f * unit
        shineRect.set(rect.left + rect.width() * 0.12f, top, rect.right - rect.width() * 0.12f, top + rect.height() * 0.46f)
        shine = LinearGradient(0f, shineRect.top, 0f, shineRect.bottom, white(0.55f), white(0.04f), Shader.TileMode.CLAMP)
    }

    override fun draw(canvas: Canvas) {
        val r = rect.height() / 2
        paint.style = Paint.Style.FILL
        paint.shader = null
        paint.color = color
        canvas.drawRoundRect(rect, r, r, paint)
        paint.color = Color.BLACK
        paint.shader = gloss
        canvas.drawRoundRect(rect, r, r, paint)
        paint.shader = shine
        canvas.drawRoundRect(shineRect, shineRect.height() / 2, shineRect.height() / 2, paint)
        paint.shader = null
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = density
        paint.color = white(0.14f)
        canvas.drawRoundRect(borderRect, r, r, paint)
    }

    override fun getOutline(outline: Outline) {
        outline.setRoundRect(bounds, bounds.height() / 2f)
    }
}
