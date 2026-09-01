import Foundation
#if canImport(UIKit)
    import UIKit
#endif

/// Represents the response payload from `/sdk/mobile/v1/widget`.
public struct PoltioWidgetResponse: Codable, Equatable {
    /// The unique public identifier of the Poltio widget.
    public let publicId: String

    /// The overlay and trigger configuration options.
    public let overlayOptions: PoltioOverlayOptions

    /// Optional scheduling start timestamp.
    public let startsAt: String?

    /// Optional scheduling end timestamp.
    public let endsAt: String?

    enum CodingKeys: String, CodingKey {
        case publicId = "public_id"
        case overlayOptions = "overlay_options"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
    }

    public init(
        publicId: String,
        overlayOptions: PoltioOverlayOptions,
        startsAt: String? = nil,
        endsAt: String? = nil
    ) {
        self.publicId = publicId
        self.overlayOptions = overlayOptions
        self.startsAt = startsAt
        self.endsAt = endsAt
    }
}

/// Overlay presentation and style options for native triggers.
///
/// Backed by a single normalized `[String: String]` bag (`fields`) rather than one stored property
/// per parameter — the mobile widget parameter surface (see `WIDGET_PARAMS.md`) is 60+ entries and
/// mirrors the web SDK's `data-poltio-*` attributes almost 1:1, so a per-field stored property with
/// duplicated mobile-override lookup logic doesn't scale. Every key (top-level and inside the
/// `mobile` override object) is normalized to kebab-case (`_` → `-`) and merged into one dictionary,
/// with `mobile` entries winning — that merge happens once at decode time instead of on every access.
public struct PoltioOverlayOptions: Codable, Equatable {
    /// Normalized (kebab-case), merged raw fields: top-level `overlay_options` keys with any
    /// matching `mobile` override applied on top. All lookups go through `field(_:)`.
    private let fields: [String: String]

    /// Design type version identifier for the card/slideover trigger, e.g. "2025-01".
    private static let cardDesignType2025 = "2025-01"

    // MARK: - Key normalization & lookup

    /// Normalizes a raw JSON key to the canonical kebab-case form used for all internal lookups.
    /// The real API always sends kebab-case keys (see `fields.json` / the docs table); this only
    /// guards against a stray snake_case variant reaching the SDK.
    private static func normalizeKey(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    /// Returns the first non-nil value among the given canonical (already-normalized) keys.
    /// Most fields have exactly one key; a few carry legacy aliases from earlier API shapes.
    private func field(_ keys: String...) -> String? {
        for key in keys {
            if let value = fields[key] {
                return value
            }
        }
        return nil
    }

    private static func stringify(_ any: AnyCodable) -> String? {
        switch any.value {
        case let s as String: s
        case let i as Int: String(i)
        case let d as Double: String(d)
        case let b as Bool: b ? "true" : "false"
        default: nil
        }
    }

    private static func boolValue(_ raw: String?, default defaultValue: Bool) -> Bool {
        guard let normalized = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !normalized.isEmpty else {
            return defaultValue
        }
        return normalized == "true" || normalized == "1"
    }

    private static func numericValue(_ raw: String?) -> Double? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return Double(trimmed)
    }

    /// Merges the top-level object and its nested `mobile` override object (mobile wins) into one
    /// normalized-key dictionary.
    private static func buildFields(from raw: [String: AnyCodable]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in raw where key != "mobile" {
            if let str = stringify(value) {
                result[normalizeKey(key)] = str
            }
        }
        if let mobileAny = raw["mobile"], let mobileDict = mobileAny.value as? [String: AnyCodable] {
            for (key, value) in mobileDict {
                if let str = stringify(value) {
                    result[normalizeKey(key)] = str
                }
            }
        }
        return result
    }

    // MARK: - Trigger type resolution

    /// Resolved trigger type string, ignoring the `isCardTrigger` heuristic fallback (used internally
    /// to avoid recursion between `triggerType` and `isCardTrigger`).
    private var rawTriggerType: String? {
        field("trigger-type")?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The resolved trigger type (e.g. "box", "pill", "card"), respecting mobile overrides if present.
    public var triggerType: String? {
        if let raw = rawTriggerType {
            return raw
        }
        return isCardTrigger ? "card" : nil
    }

    /// Convenience check for box trigger type.
    public var isBoxTrigger: Bool {
        rawTriggerType == "box"
    }

    /// Convenience check for pill trigger type.
    public var isPillTrigger: Bool {
        rawTriggerType == "pill"
    }

    /// Convenience check for card trigger type (rounded slideover/card trigger).
    public var isCardTrigger: Bool {
        if isBoxTrigger || isPillTrigger {
            return false
        }
        if let raw = rawTriggerType, raw == "card" || raw == "slideover" || raw == Self.cardDesignType2025 {
            return true
        }
        let designType = floatingDesignType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if designType == Self.cardDesignType2025 || designType == "card" || designType == "slideover" {
            return true
        }
        let displayType = floatingDisplayType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if displayType == "slideover" || displayType == "card" {
            return true
        }
        if floatingTitle != nil || floatingDesc != nil {
            return true
        }
        return false
    }

    /// Convenience check whether initial state should be active (auto-expand then auto-collapse).
    public var isInitialActive: Bool {
        floatingInitialPosition?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "active"
    }

    /// Convenience check whether the trigger should start in its expanded state at all
    /// (`active`, which also auto-collapses, or `expanded`, which stays open).
    public var isInitialExpanded: Bool {
        let value = floatingInitialPosition?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value == "active" || value == "expanded"
    }

    // MARK: - identity / iframe query params (passed through to the WebView URL)

    /// Free-form content identifier passed to the widget page, respecting mobile overrides.
    public var content: String? {
        field("widget-content")
    }

    /// Custom identifier passed to the widget page, respecting mobile overrides.
    public var customId: String? {
        field("widget-custom-id")
    }

    /// Location/placement identifier passed to the widget page, respecting mobile overrides.
    public var loc: String? {
        field("widget-loc")
    }

    /// Result-fit display mode (`off`/`sc`/`fit`/`vf`) passed to the widget page.
    public var resultfit: String? {
        field("widget-resultfit")
    }

    /// Disclaimer display mode (`on`/`off`) passed to the widget page.
    public var disclaimer: String? {
        field("widget-disclaimer")
    }

    // MARK: - common

    /// Design type version identifier (e.g. "2025-01"), respecting mobile overrides.
    public var floatingDesignType: String? {
        field("floating-design-type")
    }

    /// Display type identifier (e.g. "slideover", "modal"), respecting mobile overrides.
    public var floatingDisplayType: String? {
        field("floating-display-type")
    }

    /// Floating background color string (e.g. "rgb(174, 174, 209)" or "#00A3FF"), respecting mobile overrides.
    public var floatingBgColor: String? {
        field("floating-bgcolor", "floating-bg-color")
    }

    /// Background color for the expanded panel's content surface, respecting mobile overrides.
    public var widgetBg: String? {
        field("widget-bgcolor")
    }

    /// Background image URL for the expanded panel, respecting mobile overrides.
    public var widgetBgImage: String? {
        field("widget-bg-image")
    }

    /// Title for card trigger, respecting mobile overrides if present.
    public var floatingTitle: String? {
        field("floating-title")
    }

    /// Description text for card trigger, respecting mobile overrides if present.
    public var floatingDesc: String? {
        field("floating-desc")
    }

    /// Raw z-index string, respecting mobile overrides. Prefer `floatingZindex` for numeric use.
    public var floatingZindexRaw: String? {
        field("floating-zindex")
    }

    /// Parsed z-index value (default 100, matching the documented default).
    public var floatingZindex: Double {
        Self.numericValue(floatingZindexRaw) ?? 100
    }

    /// Custom font family name, respecting mobile overrides. Falls back to the system font if the
    /// named font isn't registered in the host app.
    public var floatingFontFamily: String? {
        field("floating-font-family")
    }

    /// Border radius specification, respecting mobile overrides.
    public var floatingMobileTopBorderRadius: String? {
        field("floating-mobile-top-border-radius")
    }

    /// Whether the entire floating trigger should be suppressed, respecting mobile overrides.
    public var hideButton: Bool {
        Self.boolValue(field("floating-hide-button"), default: false)
    }

    /// Screen dock position (e.g. "bottom-right"), respecting mobile overrides.
    public var floatingPosition: String? {
        field("floating-position")
    }

    /// Vertical component of `floatingPosition` (`top`/`center`/`bottom`), default `bottom`.
    public var verticalPosition: String {
        String((floatingPosition ?? "bottom-right").split(separator: "-", maxSplits: 1).first ?? "bottom")
    }

    /// Horizontal component of `floatingPosition` (`left`/`right`), default `right`.
    public var horizontalPosition: String {
        let parts = (floatingPosition ?? "bottom-right").split(separator: "-", maxSplits: 1)
        return parts.count > 1 ? String(parts[1]) : "right"
    }

    /// Initial trigger position / state (e.g. "active", "collapsed", "expanded"), respecting mobile overrides.
    public var floatingInitialPosition: String? {
        field("floating-initial-position")
    }

    /// Scroll offset (px) at which the JS SDK reveals the trigger. No native equivalent (there's no
    /// generic host-scroll hook); decoded for parity only.
    public var floatingScrollThreshold: Double {
        Self.numericValue(field("floating-scroll-threshold")) ?? 300
    }

    /// SVG asset path or URL for floating trigger, respecting mobile overrides if present.
    public var floatingSvg: String? {
        field("floating-svg")
    }

    /// Whether the product-card variant is enabled. No native product_card trigger exists yet;
    /// decoded for parity only.
    public var productCardEnabled: Bool {
        Self.boolValue(field("floating-product-card-enabled"), default: false)
    }

    // MARK: - card

    /// Action button label for card trigger, respecting mobile overrides if present.
    public var floatingButtonText: String? {
        field("floating-buttontext", "floating-button-text", "floating-bar-text-button")
    }

    /// Floating text color string (e.g. "white" or "#FFFFFF"), respecting mobile overrides.
    public var floatingTextColor: String? {
        field("floating-textcolor", "floating-text-color")
    }

    /// Floating icon color string (e.g. "#1E3D54"), respecting mobile overrides.
    public var floatingIconColor: String? {
        field("floating-icon-color", "floating-widget-icon-color")
    }

    // MARK: - pill

    /// First pill text segment (e.g. "Try our"), respecting mobile overrides.
    public var textFirst: String? {
        field("floating-text-first")
    }

    /// Second pill text segment (e.g. "PRODUCT"), respecting mobile overrides.
    public var textSecond: String? {
        field("floating-text-second")
    }

    /// Third pill text segment (e.g. "FINDER"), respecting mobile overrides.
    public var textThird: String? {
        field("floating-text-third")
    }

    /// Color for `textFirst`, respecting mobile overrides.
    public var textColorFirst: String? {
        field("floating-text-color-first")
    }

    /// Color for `textSecond`, respecting mobile overrides.
    public var textColorSecond: String? {
        field("floating-text-color-second")
    }

    /// Color for `textThird`, respecting mobile overrides.
    public var textColorThird: String? {
        field("floating-text-color-third")
    }

    /// Pulsate ring color, respecting mobile overrides.
    public var pulsateColor: String? {
        field("floating-pulsate-color")
    }

    /// Whether the pulsate animation is shown (default true), respecting mobile overrides.
    public var showPulsate: Bool {
        Self.boolValue(field("floating-show-pulsate"), default: true)
    }

    /// Initial pill state (`closed`/`open`), respecting mobile overrides.
    public var pillStartMode: String? {
        field("floating-pill-start-mode")
    }

    /// Whether the pill shows an explicit close button (default false), respecting mobile overrides.
    public var pillShowCloseButton: Bool {
        Self.boolValue(field("floating-pill-show-close-button"), default: false)
    }

    /// Hours to suppress the trigger after an explicit close (default 48), respecting mobile overrides.
    public var pillCloseRememberDuration: Double {
        Self.numericValue(field("floating-pill-close-remember-duration")) ?? 48
    }

    // MARK: - box

    /// Image path or URL for floating trigger, respecting mobile overrides if present.
    public var floatingImg: String? {
        field("floating-img")
    }

    /// First header text line for floating box trigger, respecting mobile overrides if present.
    public var floatingBoxTextFirst: String? {
        field("floating-box-text-first")
    }

    /// Second footer text line for floating box trigger, respecting mobile overrides if present.
    public var floatingBoxTextSecond: String? {
        field("floating-box-text-second")
    }

    /// Color for the box header text, respecting mobile overrides.
    public var boxTextColorFirst: String? {
        field("floating-box-text-color-first")
    }

    /// Color for the box footer text, respecting mobile overrides.
    public var boxTextColorSecond: String? {
        field("floating-box-text-color-second")
    }

    /// Background color for the box's outer chrome, respecting mobile overrides.
    public var boxBgColorFirst: String? {
        field("floating-box-bg-color-first")
    }

    /// Background color for the box's inner content surface, respecting mobile overrides.
    public var boxBgColorSecond: String? {
        field("floating-box-bg-color-second")
    }

    /// Raw CSS font size for the box header text (e.g. "1rem"), respecting mobile overrides.
    public var boxTextFirstFontSizeRaw: String? {
        field("floating-box-text-first-font-size")
    }

    /// Raw CSS font weight for the box header text (e.g. "700"), respecting mobile overrides.
    public var boxTextFirstFontWeightRaw: String? {
        field("floating-box-text-first-font-weight")
    }

    /// Raw CSS font size for the box footer text (e.g. "1.25rem"), respecting mobile overrides.
    public var boxTextSecondFontSizeRaw: String? {
        field("floating-box-text-second-font-size")
    }

    /// Raw CSS font weight for the box footer text (e.g. "700"), respecting mobile overrides.
    public var boxTextSecondFontWeightRaw: String? {
        field("floating-box-text-second-font-weight")
    }

    /// Raw CSS text alignment for the box header text (`flex-start`/`center`/`flex-end`), respecting mobile overrides.
    public var boxTextAlignFirstRaw: String? {
        field("floating-box-text-align-first")
    }

    /// Raw CSS text alignment for the box footer text, respecting mobile overrides.
    public var boxTextAlignSecondRaw: String? {
        field("floating-box-text-align-second")
    }

    /// Initial box state (`closed`/`open`), respecting mobile overrides.
    public var boxStartMode: String? {
        field("floating-box-start-mode")
    }

    /// Whether the box should auto-expand on host scroll (default true). No generic host-scroll hook
    /// is available natively; decoded for parity only.
    public var boxOpenOnScroll: Bool {
        Self.boolValue(field("floating-box-open-on-scroll"), default: true)
    }

    /// Milliseconds after which the box auto-expands once, if set. `nil` disables auto-expand.
    public var boxOpenOnTime: Double? {
        Self.numericValue(field("floating-box-open-on-time"))
    }

    /// Whether the box shows an explicit close button (default false), respecting mobile overrides.
    public var boxShowCloseButton: Bool {
        Self.boolValue(field("floating-box-show-close-button"), default: false)
    }

    /// Hours to suppress the trigger after an explicit close (default 48), respecting mobile overrides.
    public var boxCloseRememberDuration: Double {
        Self.numericValue(field("floating-box-close-remember-duration")) ?? 48
    }

    /// Uniform scale factor applied to the box trigger's dimensions (default 1), respecting mobile overrides.
    public var boxResize: Double {
        Self.numericValue(field("floating-box-resize")) ?? 1
    }

    /// Whether the banner image should fill the entire expanded card (default false), respecting mobile overrides.
    public var boxFullImageMode: Bool {
        Self.boolValue(field("floating-box-full-image-mode"), default: false)
    }

    // MARK: - product_card (decoded for parity; no native product_card trigger exists yet)

    public var productParent: String? {
        field("floating-product-parent")
    }

    public var productParentNumber: String? {
        field("floating-product-parent-number")
    }

    public var productSibling: String? {
        field("floating-product-sibling")
    }

    public var productChildNumber: String? {
        field("floating-product-child-number")
    }

    public var productImage: String? {
        field("floating-product-image")
    }

    // MARK: - iframe (decoded for parity; DOM-embedding only, no native equivalent)

    public var parentId: String? {
        field("floating-parent-id")
    }

    public var parentClassName: String? {
        field("floating-parent-class-name")
    }

    public var parentHeight: String? {
        field("floating-parent-height")
    }

    #if canImport(UIKit)
        /// Resolved background color with fallback to Poltio vibrant blue (`#00A3FF`).
        public var resolvedBgColor: UIColor {
            if let colorStr = floatingBgColor, let color = PoltioColorParser.parse(colorStr) {
                return color
            }
            return UIColor(red: 0.0, green: 0.64, blue: 0.98, alpha: 1.0)
        }

        /// Resolved text color with fallback to white.
        public var resolvedTextColor: UIColor {
            if let colorStr = floatingTextColor, let color = PoltioColorParser.parse(colorStr) {
                return color
            }
            return .white
        }

        /// Resolved icon/accent color with fallback to deep navy (`#1E3D54`).
        public var resolvedIconColor: UIColor {
            if let colorStr = floatingIconColor, let color = PoltioColorParser.parse(colorStr) {
                return color
            }
            return UIColor(red: 0.12, green: 0.24, blue: 0.33, alpha: 1.0)
        }

        /// Resolved widget/panel background color with fallback to white.
        public var resolvedWidgetBgColor: UIColor {
            if let colorStr = widgetBg, let color = PoltioColorParser.parse(colorStr) {
                return color
            }
            return .white
        }

        /// Resolves a raw color string against `PoltioColorParser`, falling back to a caller-provided default.
        public static func resolvedColor(_ raw: String?, fallback: UIColor) -> UIColor {
            guard let raw, let color = PoltioColorParser.parse(raw) else {
                return fallback
            }
            return color
        }

        /// Resolves a custom font family name, falling back to the system font of the same size/weight
        /// if the named font isn't registered in the host app (custom fonts can't be downloaded natively).
        public func resolvedFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
            if let family = floatingFontFamily?.trimmingCharacters(in: .whitespacesAndNewlines), !family.isEmpty,
               let font = UIFont(name: family, size: size)
            {
                return font
            }
            return .systemFont(ofSize: size, weight: weight)
        }

        /// Parses a CSS length string (`"1.75em"`, `"1rem"`, `"16px"`, `"16"`) into points.
        /// `em`/`rem` are resolved against a 16pt base, matching typical browser defaults.
        public static func cssLength(_ raw: String?, default defaultValue: CGFloat) -> CGFloat {
            guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !trimmed.isEmpty else {
                return defaultValue
            }
            if trimmed.hasSuffix("rem") {
                return Double(trimmed.dropLast(3)).map { CGFloat($0) * 16.0 } ?? defaultValue
            }
            if trimmed.hasSuffix("em") {
                return Double(trimmed.dropLast(2)).map { CGFloat($0) * 16.0 } ?? defaultValue
            }
            if trimmed.hasSuffix("px") {
                return Double(trimmed.dropLast(2)).map { CGFloat($0) } ?? defaultValue
            }
            return Double(trimmed).map { CGFloat($0) } ?? defaultValue
        }

        /// Maps a CSS numeric font-weight string (`"400"`…`"900"`) to `UIFont.Weight`.
        public static func fontWeight(_ raw: String?, default defaultValue: UIFont.Weight) -> UIFont.Weight {
            guard let value = numericValue(raw) else { return defaultValue }
            switch value {
            case ..<250: return .ultraLight
            case 250 ..< 350: return .thin
            case 350 ..< 450: return .light
            case 450 ..< 550: return .regular
            case 550 ..< 650: return .medium
            case 650 ..< 720: return .semibold
            case 720 ..< 850: return .bold
            case 850 ..< 950: return .heavy
            default: return .black
            }
        }

        /// Maps a CSS flexbox alignment keyword (`flex-start`/`center`/`flex-end`, or `left`/`right`) to `NSTextAlignment`.
        public static func textAlignment(_ raw: String?, default defaultValue: NSTextAlignment) -> NSTextAlignment {
            guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !value.isEmpty else {
                return defaultValue
            }
            switch value {
            case "flex-start", "left", "start": return .left
            case "center": return .center
            case "flex-end", "right", "end": return .right
            default: return defaultValue
            }
        }

        /// Parsed box header font size (default 16pt / "1rem").
        public var boxTextFirstFontSize: CGFloat {
            Self.cssLength(boxTextFirstFontSizeRaw, default: 16)
        }

        /// Parsed box header font weight (default bold / "700").
        public var boxTextFirstFontWeight: UIFont.Weight {
            Self.fontWeight(boxTextFirstFontWeightRaw, default: .bold)
        }

        /// Parsed box footer font size (default 20pt / "1.25rem").
        public var boxTextSecondFontSize: CGFloat {
            Self.cssLength(boxTextSecondFontSizeRaw, default: 20)
        }

        /// Parsed box footer font weight (default bold / "700").
        public var boxTextSecondFontWeight: UIFont.Weight {
            Self.fontWeight(boxTextSecondFontWeightRaw, default: .bold)
        }

        /// Parsed box header text alignment (default `.left` / "flex-start").
        public var boxTextAlignFirst: NSTextAlignment {
            Self.textAlignment(boxTextAlignFirstRaw, default: .left)
        }

        /// Parsed box footer text alignment (default `.left` / "flex-start").
        public var boxTextAlignSecond: NSTextAlignment {
            Self.textAlignment(boxTextAlignSecondRaw, default: .left)
        }

        /// Parsed top-corner radius (default 28pt / "1.75em").
        public var resolvedMobileTopBorderRadius: CGFloat {
            Self.cssLength(floatingMobileTopBorderRadius, default: 28)
        }
    #endif

    /// Resolves the full URL for `floatingImg` or `floatingSvg`.
    /// If `floatingImg` or `floatingSvg` is an absolute URL (`http://` or `https://`), it is returned directly.
    /// If it is a relative path (e.g. `widget/1787042301.079.svg`), it is resolved using the CDN prefix:
    /// - For pill triggers / `floatingSvg`: `https://cdn.poltio.com/40x40/`
    /// - For box triggers: `https://cdn.poltio.com/240x120/`
    public func resolvedImageUrl(cdnPrefix: String? = nil) -> URL? {
        let rawImgPath = [floatingSvg, floatingImg]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let path = rawImgPath else {
            return nil
        }

        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }

        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let hasValidSvg = !(floatingSvg?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let defaultPrefix = if isPillTrigger || hasValidSvg || cleanPath.hasSuffix(".svg") {
            "https://cdn.poltio.com/40x40"
        } else {
            "https://cdn.poltio.com/240x120"
        }

        let effectivePrefix = cdnPrefix ?? defaultPrefix
        let cleanPrefix = effectivePrefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(cleanPrefix)/\(cleanPath)")
    }

    // MARK: - Init

    /// Memberwise initializer for manual construction (e.g. unit tests). Every parameter maps to its
    /// documented API field; pass `mobile` to simulate per-platform overrides.
    public init(
        triggerType: String? = nil,
        floatingBoxTextFirst: String? = nil,
        floatingBoxTextSecond: String? = nil,
        floatingImg: String? = nil,
        floatingSvg: String? = nil,
        floatingInitialPosition: String? = nil,
        floatingTitle: String? = nil,
        floatingDesc: String? = nil,
        floatingButtonText: String? = nil,
        floatingBgColor: String? = nil,
        floatingTextColor: String? = nil,
        floatingIconColor: String? = nil,
        floatingDesignType: String? = nil,
        floatingDisplayType: String? = nil,
        floatingPosition: String? = nil,
        floatingMobileTopBorderRadius: String? = nil,
        content: String? = nil,
        customId: String? = nil,
        loc: String? = nil,
        resultfit: String? = nil,
        disclaimer: String? = nil,
        widgetBg: String? = nil,
        widgetBgImage: String? = nil,
        floatingZindex: String? = nil,
        floatingFontFamily: String? = nil,
        hideButton: String? = nil,
        floatingScrollThreshold: String? = nil,
        productCardEnabled: String? = nil,
        textFirst: String? = nil,
        textSecond: String? = nil,
        textThird: String? = nil,
        textColorFirst: String? = nil,
        textColorSecond: String? = nil,
        textColorThird: String? = nil,
        pulsateColor: String? = nil,
        showPulsate: String? = nil,
        pillStartMode: String? = nil,
        pillShowCloseButton: String? = nil,
        pillCloseRememberDuration: String? = nil,
        boxTextColorFirst: String? = nil,
        boxTextColorSecond: String? = nil,
        boxBgColorFirst: String? = nil,
        boxBgColorSecond: String? = nil,
        boxTextFirstFontSize: String? = nil,
        boxTextFirstFontWeight: String? = nil,
        boxTextSecondFontSize: String? = nil,
        boxTextSecondFontWeight: String? = nil,
        boxTextAlignFirst: String? = nil,
        boxTextAlignSecond: String? = nil,
        boxStartMode: String? = nil,
        boxOpenOnScroll: String? = nil,
        boxOpenOnTime: String? = nil,
        boxShowCloseButton: String? = nil,
        boxCloseRememberDuration: String? = nil,
        boxResize: String? = nil,
        boxFullImageMode: String? = nil,
        productParent: String? = nil,
        productParentNumber: String? = nil,
        productSibling: String? = nil,
        productChildNumber: String? = nil,
        productImage: String? = nil,
        parentId: String? = nil,
        parentClassName: String? = nil,
        parentHeight: String? = nil,
        mobile: [String: AnyCodable]? = nil
    ) {
        var built: [String: String] = [:]
        func set(_ key: String, _ value: String?) {
            guard let value else { return }
            built[key] = value
        }

        set("trigger-type", triggerType)
        set("floating-box-text-first", floatingBoxTextFirst)
        set("floating-box-text-second", floatingBoxTextSecond)
        set("floating-img", floatingImg)
        set("floating-svg", floatingSvg)
        set("floating-initial-position", floatingInitialPosition)
        set("floating-title", floatingTitle)
        set("floating-desc", floatingDesc)
        set("floating-buttontext", floatingButtonText)
        set("floating-bgcolor", floatingBgColor)
        set("floating-textcolor", floatingTextColor)
        set("floating-icon-color", floatingIconColor)
        set("floating-design-type", floatingDesignType)
        set("floating-display-type", floatingDisplayType)
        set("floating-position", floatingPosition)
        set("floating-mobile-top-border-radius", floatingMobileTopBorderRadius)
        set("widget-content", content)
        set("widget-custom-id", customId)
        set("widget-loc", loc)
        set("widget-resultfit", resultfit)
        set("widget-disclaimer", disclaimer)
        set("widget-bgcolor", widgetBg)
        set("widget-bg-image", widgetBgImage)
        set("floating-zindex", floatingZindex)
        set("floating-font-family", floatingFontFamily)
        set("floating-hide-button", hideButton)
        set("floating-scroll-threshold", floatingScrollThreshold)
        set("floating-product-card-enabled", productCardEnabled)
        set("floating-text-first", textFirst)
        set("floating-text-second", textSecond)
        set("floating-text-third", textThird)
        set("floating-text-color-first", textColorFirst)
        set("floating-text-color-second", textColorSecond)
        set("floating-text-color-third", textColorThird)
        set("floating-pulsate-color", pulsateColor)
        set("floating-show-pulsate", showPulsate)
        set("floating-pill-start-mode", pillStartMode)
        set("floating-pill-show-close-button", pillShowCloseButton)
        set("floating-pill-close-remember-duration", pillCloseRememberDuration)
        set("floating-box-text-color-first", boxTextColorFirst)
        set("floating-box-text-color-second", boxTextColorSecond)
        set("floating-box-bg-color-first", boxBgColorFirst)
        set("floating-box-bg-color-second", boxBgColorSecond)
        set("floating-box-text-first-font-size", boxTextFirstFontSize)
        set("floating-box-text-first-font-weight", boxTextFirstFontWeight)
        set("floating-box-text-second-font-size", boxTextSecondFontSize)
        set("floating-box-text-second-font-weight", boxTextSecondFontWeight)
        set("floating-box-text-align-first", boxTextAlignFirst)
        set("floating-box-text-align-second", boxTextAlignSecond)
        set("floating-box-start-mode", boxStartMode)
        set("floating-box-open-on-scroll", boxOpenOnScroll)
        set("floating-box-open-on-time", boxOpenOnTime)
        set("floating-box-show-close-button", boxShowCloseButton)
        set("floating-box-close-remember-duration", boxCloseRememberDuration)
        set("floating-box-resize", boxResize)
        set("floating-box-full-image-mode", boxFullImageMode)
        set("floating-product-parent", productParent)
        set("floating-product-parent-number", productParentNumber)
        set("floating-product-sibling", productSibling)
        set("floating-product-child-number", productChildNumber)
        set("floating-product-image", productImage)
        set("floating-parent-id", parentId)
        set("floating-parent-class-name", parentClassName)
        set("floating-parent-height", parentHeight)

        if let mobile {
            for (key, value) in mobile {
                if let str = Self.stringify(value) {
                    built[Self.normalizeKey(key)] = str
                }
            }
        }

        fields = built
    }

    public init(from decoder: Decoder) throws {
        let raw = try [String: AnyCodable](from: decoder)
        fields = Self.buildFields(from: raw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKeys.self)
        for (key, value) in fields.sorted(by: { $0.key < $1.key }) {
            guard let codingKey = DynamicCodingKeys(stringValue: key) else { continue }
            try container.encode(value, forKey: codingKey)
        }
    }
}

#if canImport(UIKit)
    /// Utility to parse Hex, RGB, RGBA, and named CSS color strings into `UIColor`.
    enum PoltioColorParser {
        static func parse(_ raw: String?) -> UIColor? {
            guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                return nil
            }

            let lower = raw.lowercased()

            // 1. Named colors
            switch lower {
            case "white": return .white
            case "black": return .black
            case "clear", "transparent": return .clear
            case "red": return .systemRed
            case "green": return .systemGreen
            case "blue": return .systemBlue
            case "gray", "grey": return .systemGray
            case "yellow": return .systemYellow
            case "orange": return .systemOrange
            case "purple": return .systemPurple
            default: break
            }

            // 2. RGB / RGBA: "rgb(174, 174, 209)" or "rgba(0, 163, 255, 0.9)"
            if lower.hasPrefix("rgb") {
                return parseRgbOrRgba(lower)
            }

            // 3. Hex: "#1E3D54", "#FFF", "#00A3FF"
            return parseHex(lower)
        }

        private static func parseRgbOrRgba(_ str: String) -> UIColor? {
            guard let start = str.firstIndex(of: "("), let end = str.lastIndex(of: ")"), start < end else {
                return nil
            }
            let inner = str[str.index(after: start) ..< end]
            let components = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard components.count >= 3 else { return nil }

            guard let r = Double(components[0]),
                  let g = Double(components[1]),
                  let b = Double(components[2])
            else {
                return nil
            }

            var a = 1.0
            if components.count >= 4, let parsedAlpha = Double(components[3]) {
                a = parsedAlpha
            }

            return UIColor(
                red: CGFloat(r / 255.0),
                green: CGFloat(g / 255.0),
                blue: CGFloat(b / 255.0),
                alpha: CGFloat(a)
            )
        }

        private static func parseHex(_ str: String) -> UIColor? {
            var hex = str.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            guard !hex.isEmpty else { return nil }

            // Support 3-digit hex (e.g. "FFF" -> "FFFFFF")
            if hex.count == 3 {
                hex = hex.map { "\($0)\($0)" }.joined()
            }

            var hexValue: UInt64 = 0
            let scanner = Scanner(string: hex)
            guard scanner.scanHexInt64(&hexValue) else { return nil }

            if hex.count == 6 {
                let r = CGFloat((hexValue & 0xFF0000) >> 16) / 255.0
                let g = CGFloat((hexValue & 0x00FF00) >> 8) / 255.0
                let b = CGFloat(hexValue & 0x0000FF) / 255.0
                return UIColor(red: r, green: g, blue: b, alpha: 1.0)
            } else if hex.count == 8 {
                // 8-digit hex follows the CSS Color Module Level 4 format: #RRGGBBAA.
                let r = CGFloat((hexValue & 0xFF00_0000) >> 24) / 255.0
                let g = CGFloat((hexValue & 0x00FF_0000) >> 16) / 255.0
                let b = CGFloat((hexValue & 0x0000_FF00) >> 8) / 255.0
                let a = CGFloat(hexValue & 0x0000_00FF) / 255.0
                return UIColor(red: r, green: g, blue: b, alpha: a)
            }

            return nil
        }
    }
#endif

/// Helper for dynamic JSON dictionary decoding.
struct DynamicCodingKeys: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        self.intValue = intValue
        stringValue = "\(intValue)"
    }
}

/// Type-erased Codable value container for arbitrary JSON values.
public struct AnyCodable: Codable, Equatable {
    public let value: Any

    public var stringValue: String? {
        value as? String
    }

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            value = str
        } else if let intVal = try? container.decode(Int.self) {
            value = intVal
        } else if let doubleVal = try? container.decode(Double.self) {
            value = doubleVal
        } else if let boolVal = try? container.decode(Bool.self) {
            value = boolVal
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array
        } else {
            value = ""
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let str = value as? String {
            try container.encode(str)
        } else if let intVal = value as? Int {
            try container.encode(intVal)
        } else if let doubleVal = value as? Double {
            try container.encode(doubleVal)
        } else if let boolVal = value as? Bool {
            try container.encode(boolVal)
        } else if let dict = value as? [String: AnyCodable] {
            try container.encode(dict)
        } else if let array = value as? [AnyCodable] {
            try container.encode(array)
        } else {
            try container.encode("\(value)")
        }
    }

    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        if let lhsStr = lhs.value as? String, let rhsStr = rhs.value as? String {
            return lhsStr == rhsStr
        } else if let lhsInt = lhs.value as? Int, let rhsInt = rhs.value as? Int {
            return lhsInt == rhsInt
        } else if let lhsDouble = lhs.value as? Double, let rhsDouble = rhs.value as? Double {
            return lhsDouble == rhsDouble
        } else if let lhsBool = lhs.value as? Bool, let rhsBool = rhs.value as? Bool {
            return lhsBool == rhsBool
        } else if let lhsDict = lhs.value as? [String: AnyCodable], let rhsDict = rhs.value as? [String: AnyCodable] {
            return lhsDict == rhsDict
        } else if let lhsArray = lhs.value as? [AnyCodable], let rhsArray = rhs.value as? [AnyCodable] {
            return lhsArray == rhsArray
        }
        return false
    }
}
