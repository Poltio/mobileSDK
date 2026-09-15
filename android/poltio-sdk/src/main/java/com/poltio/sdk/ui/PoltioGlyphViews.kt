package com.poltio.sdk.ui

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.view.View

/**
 * Small programmatically-drawn glyphs standing in for the SF Symbols used on iOS ("xmark",
 * "chevron.left"/"chevron.right"). Drawing them with `Canvas` instead of shipping vector drawable
 * resources keeps the library resource-free, avoiding any AAR resource-merge surface in host apps.
 */
internal class PoltioCloseGlyphView(context: Context, private val glyphColor: Int) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = glyphColor
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        paint.strokeWidth = minOf(w, h) * 0.11f
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val inset = minOf(width, height) * 0.30f
        canvas.drawLine(inset, inset, width - inset, height - inset, paint)
        canvas.drawLine(width - inset, inset, inset, height - inset, paint)
    }
}

internal enum class PoltioChevronDirection { LEFT, RIGHT }

internal class PoltioChevronGlyphView(
    context: Context,
    private val direction: PoltioChevronDirection,
    private val glyphColor: Int,
) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = glyphColor
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        paint.strokeWidth = minOf(w, h) * 0.14f
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val insetX = width * 0.32f
        val insetY = height * 0.24f
        val midX = if (direction == PoltioChevronDirection.LEFT) width - insetX else insetX
        val tipX = if (direction == PoltioChevronDirection.LEFT) insetX else width - insetX

        canvas.drawLine(midX, insetY, tipX, height / 2f, paint)
        canvas.drawLine(tipX, height / 2f, midX, height - insetY, paint)
    }
}
