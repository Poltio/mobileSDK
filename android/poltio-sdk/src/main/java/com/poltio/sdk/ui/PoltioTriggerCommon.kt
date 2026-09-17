package com.poltio.sdk.ui

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.view.View
import kotlin.math.roundToInt

/** Common contract for all Poltio floating trigger views (box, pill, card). */
internal interface PoltioTriggerPresentable {
    /** Resets the trigger to its collapsed state. */
    fun resetToCollapsed(animated: Boolean)
}

/** Converts a dp value to pixels using this context's display density. */
internal fun Context.dp(value: Float): Int = (value * resources.displayMetrics.density).roundToInt()

internal fun Context.dp(value: Int): Int = dp(value.toFloat())

/**
 * Resolves `floatingFontFamily` to a [android.graphics.Typeface], mirroring iOS's
 * `UIFont(name:)` attempt-then-fall-back-to-system behavior. Android has no API to resolve an
 * arbitrary custom font family name the host app hasn't registered, but [android.graphics.Typeface.create]
 * still resolves known system family names (e.g. "sans-serif-medium") and silently falls back to
 * the default typeface for anything else — never throws, so this stays safe to call unconditionally.
 */
internal fun resolvedTypeface(familyName: String?, style: Int = android.graphics.Typeface.NORMAL): android.graphics.Typeface {
    val trimmed = familyName?.trim()
    if (trimmed.isNullOrEmpty()) return android.graphics.Typeface.defaultFromStyle(style)
    return try {
        android.graphics.Typeface.create(trimmed, style)
    } catch (error: Exception) {
        android.graphics.Typeface.defaultFromStyle(style)
    }
}

/** Draws the Poltio sparkle question-mark glyph used as the default trigger icon fallback. */
internal class PoltioSparkleIconView(context: Context) : View(context) {
    private val topSparklePath = Path()
    private val bottomSparklePath = Path()
    private val topSparklePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        alpha = (0.75f * 255).roundToInt()
        style = Paint.Style.FILL
    }
    private val bottomSparklePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        alpha = (0.55f * 255).roundToInt()
        style = Paint.Style.FILL
    }
    private val glyphPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textAlign = Paint.Align.CENTER
        typeface = android.graphics.Typeface.create(android.graphics.Typeface.DEFAULT, android.graphics.Typeface.BOLD)
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (w <= 0 || h <= 0) return

        val topRect = RectF(w * 0.62f, h * 0.12f, w * 0.62f + w * 0.30f, h * 0.12f + h * 0.30f)
        sparklePath(topRect, topSparklePath)

        val bottomRect = RectF(w * 0.08f, h * 0.60f, w * 0.08f + w * 0.22f, h * 0.60f + h * 0.22f)
        sparklePath(bottomRect, bottomSparklePath)

        glyphPaint.textSize = h * 0.55f
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.drawPath(topSparklePath, topSparklePaint)
        canvas.drawPath(bottomSparklePath, bottomSparklePaint)

        val cx = width / 2f - context.dp(1f)
        val fontMetrics = glyphPaint.fontMetrics
        val cy = height / 2f - (fontMetrics.ascent + fontMetrics.descent) / 2f
        canvas.drawText("?", cx, cy, glyphPaint)
    }

    private fun sparklePath(rect: RectF, path: Path) {
        path.reset()
        val cx = rect.centerX()
        val cy = rect.centerY()
        val hw = rect.width() / 2f
        val hh = rect.height() / 2f
        val indent = 0.22f

        path.moveTo(cx, rect.top)
        path.quadTo(cx + hw * indent, cy - hh * indent, rect.right, cy)
        path.quadTo(cx + hw * indent, cy + hh * indent, cx, rect.bottom)
        path.quadTo(cx - hw * indent, cy + hh * indent, rect.left, cy)
        path.quadTo(cx - hw * indent, cy - hh * indent, cx, rect.top)
        path.close()
    }
}
