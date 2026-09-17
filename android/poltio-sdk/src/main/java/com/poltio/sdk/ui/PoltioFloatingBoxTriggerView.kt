package com.poltio.sdk.ui

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewOutlineProvider
import android.view.animation.OvershootInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import com.poltio.sdk.PoltioExecutors
import com.poltio.sdk.PoltioOverlayOptions
import com.poltio.sdk.PoltioWidgetResponse
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Future
import kotlin.math.abs

/**
 * Native floating box trigger view supporting collapsed and expanded states matching Poltio
 * design specs.
 */
internal class PoltioFloatingBoxTriggerView(
    context: Context,
    private val widget: PoltioWidgetResponse,
    private val onOpenWidget: () -> Unit,
    private val onDismissForever: (Double) -> Unit = {},
) : FrameLayout(context), PoltioTriggerPresentable {

    enum class TriggerState { COLLAPSED, EXPANDED }

    companion object {
        /** How long the expanded box stays open before auto-collapsing if left untouched. */
        private const val AUTO_COLLAPSE_DELAY_MS = 5000L
    }

    /** Uniform scale factor applied to every dimension below, clamped to a sane range. */
    private val scale = widget.overlayOptions.boxResize.toFloat().coerceIn(0.5f, 2.0f)

    private val collapsedWidthPx get() = context.dp(42f * scale)
    private val collapsedHeightPx get() = context.dp(140f * scale)
    private val expandedWidthPx get() = context.dp(180f * scale)
    private val expandedHeightPx get() = context.dp(195f * scale)

    var currentState: TriggerState = run {
        val shouldStartExpanded = widget.overlayOptions.isInitialExpanded ||
            widget.overlayOptions.boxStartMode?.trim()?.lowercase() == "open"
        if (shouldStartExpanded) TriggerState.EXPANDED else TriggerState.COLLAPSED
    }
        private set

    private val collapsedContainer = FrameLayout(context)
    private val expandedContainer = FrameLayout(context)
    private val bannerContainer = FrameLayout(context)
    private val bannerImageView = ImageView(context)
    private val bannerFallback = FrameLayout(context)
    private var sizeAnimator: android.animation.ValueAnimator? = null
    private var bannerDownload: Future<*>? = null
    /** Guards `floating-box-open-on-scroll` so it only ever fires once per trigger instance,
     * matching the web SDK's one-shot scroll listener (`controller.abort()` in `box.ts`). */
    private var hasAutoOpenedFromScroll = false

    private val autoOpenRunnable = Runnable {
        if (currentState == TriggerState.COLLAPSED) setState(TriggerState.EXPANDED, animated = true)
    }
    private val autoCollapseRunnable = Runnable {
        if (currentState == TriggerState.EXPANDED) setState(TriggerState.COLLAPSED, animated = true)
    }
    private val outsideInteractionListener: () -> Unit = {
        if (currentState == TriggerState.EXPANDED) setState(TriggerState.COLLAPSED, animated = true)
    }
    /** Assigned in `init` (not as a property initializer) so it can safely reference itself for
     * self-removal on first fire — see `setupScrollOpenIfNeeded`. */
    private lateinit var scrollListener: () -> Unit

    init {
        clipChildren = false
        clipToPadding = false

        setupCollapsedContainer()
        setupExpandedContainer()
        applyState(currentState, animated = false)
        loadBannerImage()
        scheduleAutoOpenIfNeeded()
        setupScrollOpenIfNeeded()
        PoltioHostInteractionBus.addListener(outsideInteractionListener)
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        sizeAnimator?.cancel()
        bannerDownload?.cancel(true)
        PoltioExecutors.main.removeCallbacks(autoOpenRunnable)
        PoltioExecutors.main.removeCallbacks(autoCollapseRunnable)
        PoltioHostInteractionBus.removeListener(outsideInteractionListener)
        if (::scrollListener.isInitialized) PoltioScrollObserver.removeListener(scrollListener)
    }

    private fun setupCollapsedContainer() {
        val outerBg = PoltioOverlayOptions.resolvedColor(widget.overlayOptions.boxBgColorFirst, Color.WHITE)
        val headerColor = PoltioOverlayOptions.resolvedColor(widget.overlayOptions.boxTextColorFirst, Color.BLACK)

        collapsedContainer.background = GradientDrawable().apply {
            setColor(outerBg)
            val r = context.dp(14f).toFloat()
            cornerRadii = floatArrayOf(r, r, 0f, 0f, 0f, 0f, r, r)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            collapsedContainer.outlineProvider = ViewOutlineProvider.BACKGROUND
            collapsedContainer.elevation = context.dp(3f).toFloat()
        }
        collapsedContainer.isClickable = true

        val label = TextView(context).apply {
            text = widget.overlayOptions.floatingBoxTextFirst ?: "Product Finder"
            setTextColor(headerColor)
            textSize = 13f
            typeface = resolvedTypeface(widget.overlayOptions.floatingFontFamily, android.graphics.Typeface.BOLD)
            gravity = Gravity.CENTER
            rotation = -90f
        }
        collapsedContainer.addView(
            label,
            FrameLayout.LayoutParams(context.dp(130f * scale), context.dp(30f * scale), Gravity.CENTER),
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
        val outerBg = PoltioOverlayOptions.resolvedColor(widget.overlayOptions.boxBgColorFirst, Color.WHITE)
        val innerBg = PoltioOverlayOptions.resolvedColor(widget.overlayOptions.boxBgColorSecond, Color.WHITE)
        val headerColor = PoltioOverlayOptions.resolvedColor(widget.overlayOptions.boxTextColorFirst, Color.BLACK)
        val footerColor = PoltioOverlayOptions.resolvedColor(widget.overlayOptions.boxTextColorSecond, Color.BLACK)
        val fullImageMode = widget.overlayOptions.boxFullImageMode
        val expandedCornerRadiusPx = context.dp(PoltioOverlayOptions.cssLength(widget.overlayOptions.floatingMobileTopBorderRadius, 18f)).toFloat()

        expandedContainer.background = GradientDrawable().apply {
            setColor(outerBg)
            cornerRadius = expandedCornerRadiusPx
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            expandedContainer.outlineProvider = ViewOutlineProvider.BACKGROUND
            expandedContainer.elevation = context.dp(5f).toFloat()
        }
        expandedContainer.isClickable = true

        val innerCard = FrameLayout(context).apply {
            background = GradientDrawable().apply {
                setColor(innerBg)
                val r = expandedCornerRadiusPx
                cornerRadii = floatArrayOf(r, r, r, r, 0f, 0f, 0f, 0f)
            }
            clipToOutline = true
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) outlineProvider = ViewOutlineProvider.BACKGROUND
        }
        expandedContainer.addView(innerCard, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))

        val headerLabel = TextView(context).apply {
            text = widget.overlayOptions.floatingBoxTextFirst ?: "Product Finder"
            setTextColor(if (fullImageMode) Color.WHITE else headerColor)
            textSize = widget.overlayOptions.boxTextFirstFontSize
            val style = if (widget.overlayOptions.boxTextFirstFontWeight) android.graphics.Typeface.BOLD else android.graphics.Typeface.NORMAL
            typeface = resolvedTypeface(widget.overlayOptions.floatingFontFamily, style)
            gravity = widget.overlayOptions.boxTextAlignFirst or Gravity.CENTER_VERTICAL
            maxLines = 1
        }

        val collapseButton = PoltioChevronGlyphView(context, PoltioChevronDirection.RIGHT, if (fullImageMode) Color.WHITE else Color.GRAY).apply {
            setOnClickListener { setState(TriggerState.COLLAPSED, animated = true) }
        }

        val footerLabel = TextView(context).apply {
            text = widget.overlayOptions.floatingBoxTextSecond ?: "Product Finder"
            setTextColor(if (fullImageMode) Color.WHITE else footerColor)
            textSize = widget.overlayOptions.boxTextSecondFontSize
            val style = if (widget.overlayOptions.boxTextSecondFontWeight) android.graphics.Typeface.BOLD else android.graphics.Typeface.NORMAL
            typeface = resolvedTypeface(widget.overlayOptions.floatingFontFamily, style)
            gravity = widget.overlayOptions.boxTextAlignSecond or Gravity.CENTER_VERTICAL
            maxLines = 1
        }

        bannerImageView.scaleType = ImageView.ScaleType.CENTER_CROP
        bannerImageView.setBackgroundColor(Color.rgb(0, 158, 237))
        bannerContainer.addView(bannerImageView, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        setupBannerFallbackView()
        bannerContainer.addView(bannerFallback, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))

        var closeButton: PoltioCloseGlyphView? = null
        if (widget.overlayOptions.boxShowCloseButton) {
            closeButton = PoltioCloseGlyphView(context, if (fullImageMode) Color.WHITE else Color.GRAY).apply {
                contentDescription = "Close"
                setOnClickListener { onDismissForever(widget.overlayOptions.boxCloseRememberDuration) }
            }
        }

        if (fullImageMode) {
            val headerScrim = View(context).apply { setBackgroundColor(Color.argb(89, 0, 0, 0)) }
            val footerScrim = View(context).apply { setBackgroundColor(Color.argb(89, 0, 0, 0)) }

            innerCard.addView(bannerContainer, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
            innerCard.addView(headerScrim, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, context.dp(38f), Gravity.TOP))
            innerCard.addView(footerScrim, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, context.dp(38f), Gravity.BOTTOM))
            innerCard.addView(headerLabel, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.TOP).apply {
                topMargin = context.dp(14f); leftMargin = context.dp(16f); rightMargin = context.dp(34f)
            })
            innerCard.addView(collapseButton, FrameLayout.LayoutParams(context.dp(24f), context.dp(24f), Gravity.TOP or Gravity.END).apply {
                topMargin = context.dp(11f); rightMargin = context.dp(10f)
            })
            innerCard.addView(footerLabel, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.BOTTOM).apply {
                bottomMargin = context.dp(14f); leftMargin = context.dp(16f); rightMargin = context.dp(16f)
            })
            closeButton?.let {
                innerCard.addView(it, FrameLayout.LayoutParams(context.dp(24f), context.dp(24f), Gravity.TOP or Gravity.END).apply {
                    topMargin = context.dp(11f); rightMargin = context.dp(38f)
                })
            }
        } else {
            innerCard.addView(headerLabel, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.TOP).apply {
                topMargin = context.dp(14f); leftMargin = context.dp(16f); rightMargin = context.dp(34f)
            })
            innerCard.addView(collapseButton, FrameLayout.LayoutParams(context.dp(24f), context.dp(24f), Gravity.TOP or Gravity.END).apply {
                topMargin = context.dp(14f); rightMargin = context.dp(10f)
            })
            innerCard.addView(bannerContainer, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, context.dp(95f * scale), Gravity.TOP).apply {
                topMargin = context.dp(14f + 32f)
            })
            innerCard.addView(footerLabel, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.TOP).apply {
                topMargin = context.dp(14f + 32f + 95f * scale + 14f); leftMargin = context.dp(16f); rightMargin = context.dp(16f)
            })
            closeButton?.let {
                innerCard.addView(it, FrameLayout.LayoutParams(context.dp(24f), context.dp(24f), Gravity.TOP or Gravity.END).apply {
                    topMargin = context.dp(14f); rightMargin = context.dp(38f)
                })
            }
        }

        addView(expandedContainer, FrameLayout.LayoutParams(expandedWidthPx, expandedHeightPx, Gravity.CENTER_VERTICAL or Gravity.END))

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
        expandedContainer.setOnClickListener {
            PoltioExecutors.main.removeCallbacks(autoCollapseRunnable)
            onOpenWidget()
        }
    }

    private fun setupBannerFallbackView() {
        bannerFallback.setBackgroundColor(Color.rgb(0, 158, 237))

        val title = TextView(context).apply {
            text = "Find\nyour\nperfect\nproduct"
            maxLines = 4
            textSize = 13f
            setTypeface(typeface, android.graphics.Typeface.BOLD)
            setTextColor(Color.WHITE)
        }
        bannerFallback.addView(title, FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER_VERTICAL or Gravity.START).apply {
            leftMargin = context.dp(12f)
        })

        val icon = TextView(context).apply {
            text = "?"
            textSize = 32f
            setTypeface(typeface, android.graphics.Typeface.BOLD)
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
        }
        bannerFallback.addView(icon, FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER_VERTICAL or Gravity.END).apply {
            rightMargin = context.dp(14f)
        })
    }

    private fun loadBannerImage() {
        val urlString = widget.overlayOptions.resolvedImageUrl() ?: return
        bannerDownload?.cancel(true)
        bannerDownload = PoltioExecutors.io.submit {
            val bitmap = try {
                downloadBitmap(urlString)
            } catch (error: Exception) {
                null
            } ?: return@submit
            // No `isAttachedToWindow` gate here: `loadBannerImage()` runs from `init`, before this
            // view is attached to the overlay, so a fast (e.g. cached) response could otherwise
            // have its result silently dropped. Setting a bitmap on a not-yet-attached ImageView
            // is safe — it renders correctly once the view is actually laid out.
            PoltioExecutors.runOnMain {
                bannerImageView.setImageBitmap(bitmap)
                bannerFallback.visibility = View.GONE
            }
        }
    }

    private fun downloadBitmap(urlString: String): Bitmap? {
        val connection = URL(urlString).openConnection() as HttpURLConnection
        return try {
            connection.connectTimeout = 15_000
            connection.readTimeout = 15_000
            if (connection.responseCode !in 200..299) return null
            connection.inputStream.use { BitmapFactory.decodeStream(it) }
        } finally {
            connection.disconnect()
        }
    }

    private fun scheduleAutoOpenIfNeeded() {
        val delayMs = widget.overlayOptions.boxOpenOnTime ?: return
        if (delayMs <= 0) return
        PoltioExecutors.main.removeCallbacks(autoOpenRunnable)
        PoltioExecutors.main.postDelayed(autoOpenRunnable, delayMs.toLong())
    }

    /** Mirrors the web SDK's `else if (params.boxOpenOnScroll === 'true')` precedence in
     * `box.ts` — `boxOpenOnTime` wins if both are configured, since the two are alternative ways
     * of specifying the same "auto-reveal once" moment. */
    private fun setupScrollOpenIfNeeded() {
        val openOnTime = widget.overlayOptions.boxOpenOnTime
        if ((openOnTime != null && openOnTime > 0) || !widget.overlayOptions.boxOpenOnScroll) return
        scrollListener = {
            if (!hasAutoOpenedFromScroll && currentState == TriggerState.COLLAPSED) {
                hasAutoOpenedFromScroll = true
                PoltioScrollObserver.removeListener(scrollListener)
                PoltioExecutors.runOnMain { setState(TriggerState.EXPANDED, animated = true) }
            }
        }
        (context as? android.app.Activity)?.let { PoltioScrollObserver.installIfNeeded(it) }
        PoltioScrollObserver.addListener(scrollListener)
    }

    // MARK: - State handling

    fun setState(state: TriggerState, animated: Boolean = true) {
        if (currentState == state) return
        currentState = state
        applyState(state, animated)
    }

    override fun resetToCollapsed(animated: Boolean) {
        setState(TriggerState.COLLAPSED, animated)
    }

    private fun applyState(state: TriggerState, animated: Boolean) {
        val isExpanded = state == TriggerState.EXPANDED
        val targetWidth = if (isExpanded) expandedWidthPx else collapsedWidthPx
        val targetHeight = if (isExpanded) expandedHeightPx else collapsedHeightPx

        sizeAnimator?.cancel()

        PoltioExecutors.main.removeCallbacks(autoCollapseRunnable)
        if (isExpanded) {
            PoltioExecutors.main.postDelayed(autoCollapseRunnable, AUTO_COLLAPSE_DELAY_MS)
        }

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
