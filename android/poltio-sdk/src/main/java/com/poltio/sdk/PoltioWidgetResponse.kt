package com.poltio.sdk

import android.view.Gravity
import androidx.annotation.ColorInt
import org.json.JSONObject

/** Represents the response payload from `/sdk/mobile/v1/widget`. */
data class PoltioWidgetResponse(
    /** The unique public identifier of the Poltio widget. */
    val publicId: String,
    /** The overlay and trigger configuration options. */
    val overlayOptions: PoltioOverlayOptions,
    /** Optional scheduling start timestamp. */
    val startsAt: String? = null,
    /** Optional scheduling end timestamp. */
    val endsAt: String? = null,
) {
    companion object {
        fun fromJson(json: JSONObject): PoltioWidgetResponse {
            val publicId = json.optString("public_id", "")
            val overlayOptionsJson = json.optJSONObject("overlay_options") ?: JSONObject()
            return PoltioWidgetResponse(
                publicId = publicId,
                overlayOptions = PoltioOverlayOptions.fromJson(overlayOptionsJson),
                startsAt = json.optStringOrNull("starts_at"),
                endsAt = json.optStringOrNull("ends_at"),
            )
        }
    }
}

private fun JSONObject.optStringOrNull(key: String): String? =
    if (has(key) && !isNull(key)) getString(key) else null

/**
 * Overlay presentation and style options for native triggers.
 *
 * Backed by a single normalized `Map<String, String>` (`fields`) rather than one stored property
 * per parameter — the mobile widget parameter surface (see `WIDGET_PARAMS.md`) is 60+ entries and
 * mirrors the web SDK's `data-poltio-*` attributes almost 1:1, so a per-field stored property with
 * duplicated mobile-override lookup logic doesn't scale. Every key (top-level and inside the
 * `mobile` override object) is normalized to kebab-case (`_` -> `-`) and merged into one map, with
 * `mobile` entries winning — that merge happens once at parse time instead of on every access.
 */
class PoltioOverlayOptions private constructor(private val fields: Map<String, String>) {

    override fun equals(other: Any?): Boolean = other is PoltioOverlayOptions && other.fields == fields
    override fun hashCode(): Int = fields.hashCode()

    // MARK: - Key normalization & lookup

    private fun field(vararg keys: String): String? {
        for (key in keys) {
            fields[key]?.let { return it }
        }
        return null
    }

    companion object {
        private const val CARD_DESIGN_TYPE_2025 = "2025-01"

        private fun normalizeKey(raw: String): String = raw.replace('_', '-').lowercase()

        private fun stringify(value: Any?): String? = when (value) {
            null, JSONObject.NULL -> null
            is String -> value
            is Int -> value.toString()
            is Long -> value.toString()
            is Double -> if (value == value.toLong().toDouble()) value.toLong().toString() else value.toString()
            is Boolean -> if (value) "true" else "false"
            else -> null
        }

        private fun boolValue(raw: String?, default: Boolean): Boolean {
            val normalized = raw?.trim()?.lowercase()
            if (normalized.isNullOrEmpty()) return default
            return normalized == "true" || normalized == "1"
        }

        private fun numericValue(raw: String?): Double? {
            val trimmed = raw?.trim()
            if (trimmed.isNullOrEmpty()) return null
            return trimmed.toDoubleOrNull()
        }

        /**
         * Merges the top-level object and its nested `mobile` override object (mobile wins) into
         * one normalized-key map.
         */
        private fun buildFields(raw: JSONObject): Map<String, String> {
            val result = LinkedHashMap<String, String>()
            val keys = raw.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                if (key == "mobile") continue
                stringify(raw.opt(key))?.let { result[normalizeKey(key)] = it }
            }

            raw.optJSONObject("mobile")?.let { mobile ->
                val mobileKeys = mobile.keys()
                while (mobileKeys.hasNext()) {
                    val key = mobileKeys.next()
                    stringify(mobile.opt(key))?.let { result[normalizeKey(key)] = it }
                }
            }
            return result
        }

        fun fromJson(raw: JSONObject): PoltioOverlayOptions = PoltioOverlayOptions(buildFields(raw))

        /** Resolves a raw color string, falling back to a caller-provided default. */
        @ColorInt
        fun resolvedColor(raw: String?, @ColorInt fallback: Int): Int = PoltioColorParser.parse(raw) ?: fallback

        /**
         * Parses a CSS length string (`"1.75em"`, `"1rem"`, `"16px"`, `"16"`) into dp.
         * `em`/`rem` are resolved against a 16dp base, matching typical browser defaults.
         */
        fun cssLength(raw: String?, default: Float): Float {
            val trimmed = raw?.trim()?.lowercase()
            if (trimmed.isNullOrEmpty()) return default
            return when {
                trimmed.endsWith("rem") -> trimmed.dropLast(3).toFloatOrNull()?.times(16f) ?: default
                trimmed.endsWith("em") -> trimmed.dropLast(2).toFloatOrNull()?.times(16f) ?: default
                trimmed.endsWith("px") -> trimmed.dropLast(2).toFloatOrNull() ?: default
                else -> trimmed.toFloatOrNull() ?: default
            }
        }

        /** Maps a CSS numeric font-weight string (`"400"`...`"900"`) to a bold/regular flag. */
        fun isBoldWeight(raw: String?, default: Boolean): Boolean {
            val value = numericValue(raw) ?: return default
            return value >= 600.0
        }

        /** Maps a CSS flexbox alignment keyword (`flex-start`/`center`/`flex-end`, or `left`/`right`) to a `Gravity` constant. */
        fun textAlignment(raw: String?, default: Int): Int {
            val value = raw?.trim()?.lowercase()
            if (value.isNullOrEmpty()) return default
            return when (value) {
                "flex-start", "left", "start" -> Gravity.START
                "center" -> Gravity.CENTER_HORIZONTAL
                "flex-end", "right", "end" -> Gravity.END
                else -> default
            }
        }
    }

    // MARK: - Trigger type resolution

    /** Resolved trigger type string, ignoring the `isCardTrigger` heuristic fallback (used internally). */
    private val rawTriggerType: String?
        get() = field("trigger-type")?.trim()?.lowercase()

    /** The resolved trigger type (e.g. "box", "pill", "card"), respecting mobile overrides if present. */
    val triggerType: String?
        get() = rawTriggerType ?: if (isCardTrigger) "card" else null

    /** Convenience check for box trigger type. */
    val isBoxTrigger: Boolean get() = rawTriggerType == "box"

    /** Convenience check for pill trigger type. */
    val isPillTrigger: Boolean get() = rawTriggerType == "pill"

    /** Convenience check for card trigger type (rounded slideover/card trigger). */
    val isCardTrigger: Boolean
        get() {
            if (isBoxTrigger || isPillTrigger) return false
            val raw = rawTriggerType
            if (raw == "card" || raw == "slideover" || raw == CARD_DESIGN_TYPE_2025) return true
            val designType = floatingDesignType?.trim()?.lowercase()
            if (designType == CARD_DESIGN_TYPE_2025 || designType == "card" || designType == "slideover") return true
            val displayType = floatingDisplayType?.trim()?.lowercase()
            if (displayType == "slideover" || displayType == "card") return true
            if (floatingTitle != null || floatingDesc != null) return true
            return false
        }

    /** Convenience check whether initial state should be active (auto-expand then auto-collapse). */
    val isInitialActive: Boolean
        get() = floatingInitialPosition?.trim()?.lowercase() == "active"

    /**
     * Convenience check whether the trigger should start in its expanded state at all
     * (`active`, which also auto-collapses, or `expanded`, which stays open).
     */
    val isInitialExpanded: Boolean
        get() {
            val value = floatingInitialPosition?.trim()?.lowercase()
            return value == "active" || value == "expanded"
        }

    // MARK: - identity / iframe query params (passed through to the WebView URL)

    val content: String? get() = field("widget-content")
    val customId: String? get() = field("widget-custom-id")
    val loc: String? get() = field("widget-loc")
    val resultfit: String? get() = field("widget-resultfit")
    val disclaimer: String? get() = field("widget-disclaimer")

    // MARK: - common

    val floatingDesignType: String? get() = field("floating-design-type")
    val floatingDisplayType: String? get() = field("floating-display-type")
    val floatingBgColor: String? get() = field("floating-bgcolor", "floating-bg-color")
    val widgetBg: String? get() = field("widget-bgcolor")
    val widgetBgImage: String? get() = field("widget-bg-image")
    val floatingTitle: String? get() = field("floating-title")
    val floatingDesc: String? get() = field("floating-desc")
    val floatingZindexRaw: String? get() = field("floating-zindex")
    val floatingZindex: Double get() = numericValue(floatingZindexRaw) ?: 100.0

    /**
     * Custom font family name, respecting mobile overrides. Decoded for parity only: unlike
     * iOS's `UIFont(name:)`, Android has no API to resolve an arbitrary font family name to a
     * `Typeface` the host app registered elsewhere, so triggers always render with the system font.
     */
    val floatingFontFamily: String? get() = field("floating-font-family")
    val floatingMobileTopBorderRadius: String? get() = field("floating-mobile-top-border-radius")
    val hideButton: Boolean get() = boolValue(field("floating-hide-button"), false)
    val floatingPosition: String? get() = field("floating-position")

    /** Vertical component of `floatingPosition` (`top`/`center`/`bottom`), default `bottom`. */
    val verticalPosition: String
        get() = (floatingPosition ?: "bottom-right").split("-", limit = 2).firstOrNull() ?: "bottom"

    /** Horizontal component of `floatingPosition` (`left`/`right`), default `right`. */
    val horizontalPosition: String
        get() {
            val parts = (floatingPosition ?: "bottom-right").split("-", limit = 2)
            return if (parts.size > 1) parts[1] else "right"
        }

    val floatingInitialPosition: String? get() = field("floating-initial-position")

    /** Scroll offset (px) at which the JS SDK reveals the trigger. No native equivalent; decoded for parity only. */
    val floatingScrollThreshold: Double get() = numericValue(field("floating-scroll-threshold")) ?: 300.0

    val floatingSvg: String? get() = field("floating-svg")

    /** Whether the product-card variant is enabled. No native product_card trigger exists yet; decoded for parity only. */
    val productCardEnabled: Boolean get() = boolValue(field("floating-product-card-enabled"), false)

    // MARK: - card

    val floatingButtonText: String? get() = field("floating-buttontext", "floating-button-text", "floating-bar-text-button")
    val floatingTextColor: String? get() = field("floating-textcolor", "floating-text-color")
    val floatingIconColor: String? get() = field("floating-icon-color", "floating-widget-icon-color")

    // MARK: - pill

    val textFirst: String? get() = field("floating-text-first")
    val textSecond: String? get() = field("floating-text-second")
    val textThird: String? get() = field("floating-text-third")
    val textColorFirst: String? get() = field("floating-text-color-first")
    val textColorSecond: String? get() = field("floating-text-color-second")
    val textColorThird: String? get() = field("floating-text-color-third")
    val pulsateColor: String? get() = field("floating-pulsate-color")
    val showPulsate: Boolean get() = boolValue(field("floating-show-pulsate"), true)
    val pillStartMode: String? get() = field("floating-pill-start-mode")
    val pillShowCloseButton: Boolean get() = boolValue(field("floating-pill-show-close-button"), false)
    val pillCloseRememberDuration: Double get() = numericValue(field("floating-pill-close-remember-duration")) ?: 48.0

    // MARK: - box

    val floatingImg: String? get() = field("floating-img")
    val floatingBoxTextFirst: String? get() = field("floating-box-text-first")
    val floatingBoxTextSecond: String? get() = field("floating-box-text-second")
    val boxTextColorFirst: String? get() = field("floating-box-text-color-first")
    val boxTextColorSecond: String? get() = field("floating-box-text-color-second")
    val boxBgColorFirst: String? get() = field("floating-box-bg-color-first")
    val boxBgColorSecond: String? get() = field("floating-box-bg-color-second")
    val boxTextFirstFontSizeRaw: String? get() = field("floating-box-text-first-font-size")
    val boxTextFirstFontWeightRaw: String? get() = field("floating-box-text-first-font-weight")
    val boxTextSecondFontSizeRaw: String? get() = field("floating-box-text-second-font-size")
    val boxTextSecondFontWeightRaw: String? get() = field("floating-box-text-second-font-weight")
    val boxTextAlignFirstRaw: String? get() = field("floating-box-text-align-first")
    val boxTextAlignSecondRaw: String? get() = field("floating-box-text-align-second")
    val boxStartMode: String? get() = field("floating-box-start-mode")

    /** Whether the box should auto-expand on host scroll (default true). No generic host-scroll hook is available natively; decoded for parity only. */
    val boxOpenOnScroll: Boolean get() = boolValue(field("floating-box-open-on-scroll"), true)

    /** Milliseconds after which the box auto-expands once, if set. `null` disables auto-expand. */
    val boxOpenOnTime: Double? get() = numericValue(field("floating-box-open-on-time"))
    val boxShowCloseButton: Boolean get() = boolValue(field("floating-box-show-close-button"), false)
    val boxCloseRememberDuration: Double get() = numericValue(field("floating-box-close-remember-duration")) ?: 48.0

    /** Uniform scale factor applied to the box trigger's dimensions (default 1), clamped by callers to a sane range. */
    val boxResize: Double get() = numericValue(field("floating-box-resize")) ?: 1.0
    val boxFullImageMode: Boolean get() = boolValue(field("floating-box-full-image-mode"), false)

    // MARK: - product_card (decoded for parity; no native product_card trigger exists yet)

    val productParent: String? get() = field("floating-product-parent")
    val productParentNumber: String? get() = field("floating-product-parent-number")
    val productSibling: String? get() = field("floating-product-sibling")
    val productChildNumber: String? get() = field("floating-product-child-number")
    val productImage: String? get() = field("floating-product-image")

    // MARK: - iframe (decoded for parity; DOM-embedding only, no native equivalent)

    val parentId: String? get() = field("floating-parent-id")
    val parentClassName: String? get() = field("floating-parent-class-name")
    val parentHeight: String? get() = field("floating-parent-height")

    // MARK: - Resolved (Android) values

    /** Resolved background color with fallback to Poltio vibrant blue (`#00A3FF`). */
    @get:ColorInt
    val resolvedBgColor: Int get() = PoltioColorParser.parse(floatingBgColor) ?: PoltioColorParser.parse("#00A3FF")!!

    /** Resolved text color with fallback to white. */
    @get:ColorInt
    val resolvedTextColor: Int get() = PoltioColorParser.parse(floatingTextColor) ?: android.graphics.Color.WHITE

    /** Resolved icon/accent color with fallback to deep navy (`#1E3D54`). */
    @get:ColorInt
    val resolvedIconColor: Int get() = PoltioColorParser.parse(floatingIconColor) ?: PoltioColorParser.parse("#1E3D54")!!

    /** Resolved widget/panel background color with fallback to white. */
    @get:ColorInt
    val resolvedWidgetBgColor: Int get() = PoltioColorParser.parse(widgetBg) ?: android.graphics.Color.WHITE

    /** Parsed box header font size in dp (default 16dp / "1rem"). */
    val boxTextFirstFontSize: Float get() = cssLength(boxTextFirstFontSizeRaw, 16f)

    /** Parsed box header font weight (default bold / "700"). */
    val boxTextFirstFontWeight: Boolean get() = isBoldWeight(boxTextFirstFontWeightRaw, true)

    /** Parsed box footer font size in dp (default 20dp / "1.25rem"). */
    val boxTextSecondFontSize: Float get() = cssLength(boxTextSecondFontSizeRaw, 20f)

    /** Parsed box footer font weight (default bold / "700"). */
    val boxTextSecondFontWeight: Boolean get() = isBoldWeight(boxTextSecondFontWeightRaw, true)

    /** Parsed box header text alignment (default `Gravity.START` / "flex-start"). */
    val boxTextAlignFirst: Int get() = textAlignment(boxTextAlignFirstRaw, Gravity.START)

    /** Parsed box footer text alignment (default `Gravity.START` / "flex-start"). */
    val boxTextAlignSecond: Int get() = textAlignment(boxTextAlignSecondRaw, Gravity.START)

    /** Parsed top-corner radius in dp (default 28dp / "1.75em"). */
    val resolvedMobileTopBorderRadius: Float get() = cssLength(floatingMobileTopBorderRadius, 28f)

    /**
     * Resolves the full URL for `floatingImg` or `floatingSvg`.
     * If `floatingImg`/`floatingSvg` is an absolute URL (`http://` or `https://`), it is returned directly.
     * If it is a relative path (e.g. `widget/1787042301.079.svg`), it is resolved using the CDN prefix:
     * - For pill triggers / `floatingSvg`: `https://cdn.poltio.com/40x40/`
     * - For box triggers: `https://cdn.poltio.com/240x120/`
     */
    fun resolvedImageUrl(cdnPrefix: String? = null): String? {
        val rawImgPath = listOfNotNull(floatingSvg, floatingImg)
            .map { it.trim() }
            .firstOrNull { it.isNotEmpty() } ?: return null

        if (rawImgPath.startsWith("http://") || rawImgPath.startsWith("https://")) {
            return rawImgPath
        }

        val cleanPath = rawImgPath.trim('/')
        val hasValidSvg = !(floatingSvg?.trim().isNullOrEmpty())
        val defaultPrefix = if (isPillTrigger || hasValidSvg || cleanPath.endsWith(".svg")) {
            "https://cdn.poltio.com/40x40"
        } else {
            "https://cdn.poltio.com/240x120"
        }

        val effectivePrefix = (cdnPrefix ?: defaultPrefix).trim('/')
        return "$effectivePrefix/$cleanPath"
    }
}
