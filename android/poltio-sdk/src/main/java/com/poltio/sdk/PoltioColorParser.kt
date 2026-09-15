package com.poltio.sdk

import android.graphics.Color
import androidx.annotation.ColorInt
import kotlin.math.roundToInt

/** Utility to parse Hex, RGB, RGBA, and named CSS color strings into an Android `@ColorInt`. */
internal object PoltioColorParser {
    @ColorInt
    fun parse(raw: String?): Int? {
        val trimmed = raw?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        val lower = trimmed.lowercase()

        // 1. Named colors
        when (lower) {
            "white" -> return Color.WHITE
            "black" -> return Color.BLACK
            "clear", "transparent" -> return Color.TRANSPARENT
            "red" -> return Color.parseColor("#F44336")
            "green" -> return Color.parseColor("#4CAF50")
            "blue" -> return Color.parseColor("#2196F3")
            "gray", "grey" -> return Color.parseColor("#9E9E9E")
            "yellow" -> return Color.parseColor("#FFEB3B")
            "orange" -> return Color.parseColor("#FF9800")
            "purple" -> return Color.parseColor("#9C27B0")
        }

        // 2. RGB / RGBA: "rgb(174, 174, 209)" or "rgba(0, 163, 255, 0.9)"
        if (lower.startsWith("rgb")) {
            return parseRgbOrRgba(lower)
        }

        // 3. Hex: "#1E3D54", "#FFF", "#00A3FF"
        return parseHex(lower)
    }

    private fun parseRgbOrRgba(raw: String): Int? {
        val start = raw.indexOf('(')
        val end = raw.lastIndexOf(')')
        if (start < 0 || end < 0 || start >= end) return null

        val components = raw.substring(start + 1, end).split(",").map { it.trim() }
        if (components.size < 3) return null

        val r = components[0].toDoubleOrNull() ?: return null
        val g = components[1].toDoubleOrNull() ?: return null
        val b = components[2].toDoubleOrNull() ?: return null
        val a = if (components.size >= 4) (components[3].toDoubleOrNull() ?: 1.0) else 1.0

        return Color.argb(
            (a * 255.0).roundToInt().coerceIn(0, 255),
            r.roundToInt().coerceIn(0, 255),
            g.roundToInt().coerceIn(0, 255),
            b.roundToInt().coerceIn(0, 255),
        )
    }

    private fun parseHex(raw: String): Int? {
        var hex = raw.trimStart('#')
        if (hex.isEmpty()) return null

        // Support 3-digit hex (e.g. "FFF" -> "FFFFFF")
        if (hex.length == 3) {
            hex = hex.map { "$it$it" }.joinToString("")
        }

        return try {
            when (hex.length) {
                6 -> {
                    val r = hex.substring(0, 2).toInt(16)
                    val g = hex.substring(2, 4).toInt(16)
                    val b = hex.substring(4, 6).toInt(16)
                    Color.rgb(r, g, b)
                }
                // 8-digit hex follows the CSS Color Module Level 4 format: #RRGGBBAA.
                8 -> {
                    val r = hex.substring(0, 2).toInt(16)
                    val g = hex.substring(2, 4).toInt(16)
                    val b = hex.substring(4, 6).toInt(16)
                    val a = hex.substring(6, 8).toInt(16)
                    Color.argb(a, r, g, b)
                }
                else -> null
            }
        } catch (error: NumberFormatException) {
            null
        }
    }
}
