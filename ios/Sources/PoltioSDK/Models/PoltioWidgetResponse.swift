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
public struct PoltioOverlayOptions: Codable, Equatable {
    private let _triggerType: String?
    private let _floatingBoxTextFirst: String?
    private let _floatingBoxTextSecond: String?
    private let _floatingImg: String?
    private let _floatingSvg: String?
    private let _floatingInitialPosition: String?
    private let _floatingTitle: String?
    private let _floatingDesc: String?
    private let _floatingButtonText: String?
    private let _floatingBgColor: String?
    private let _floatingTextColor: String?
    private let _floatingIconColor: String?
    private let _floatingDesignType: String?
    private let _floatingDisplayType: String?
    private let _floatingPosition: String?
    private let _floatingMobileTopBorderRadius: String?
    private let _mobile: [String: AnyCodable]?

    /// The resolved trigger type (e.g. "box", "pill", "card"), respecting mobile overrides if present.
    public var triggerType: String? {
        if let mobile = _mobile, let val = mobile["trigger-type"]?.stringValue ?? mobile["trigger_type"]?.stringValue {
            return val
        }
        if let type = _triggerType {
            return type
        }
        if isCardTrigger {
            return "card"
        }
        return nil
    }

    /// First header text line for floating box trigger, respecting mobile overrides if present.
    public var floatingBoxTextFirst: String? {
        if let mobile = _mobile,
           let val = mobile["floating-box-text-first"]?.stringValue ?? mobile["floating_box_text_first"]?.stringValue
        {
            return val
        }
        return _floatingBoxTextFirst
    }

    /// Second footer text line for floating box trigger, respecting mobile overrides if present.
    public var floatingBoxTextSecond: String? {
        if let mobile = _mobile,
           let val = mobile["floating-box-text-second"]?.stringValue ?? mobile["floating_box_text_second"]?.stringValue
        {
            return val
        }
        return _floatingBoxTextSecond
    }

    /// Image path or URL for floating trigger, respecting mobile overrides if present.
    public var floatingImg: String? {
        if let mobile = _mobile,
           let val = mobile["floating-img"]?.stringValue ?? mobile["floating_img"]?.stringValue
        {
            return val
        }
        return _floatingImg
    }

    /// SVG asset path or URL for floating trigger, respecting mobile overrides if present.
    public var floatingSvg: String? {
        if let mobile = _mobile,
           let val = mobile["floating-svg"]?.stringValue ?? mobile["floating_svg"]?.stringValue
        {
            return val
        }
        return _floatingSvg
    }

    /// Initial trigger position / state (e.g. "active", "collapsed"), respecting mobile overrides if present.
    public var floatingInitialPosition: String? {
        if let mobile = _mobile,
           let val = mobile["floating-initial-position"]?.stringValue ?? mobile["floating_initial_position"]?.stringValue
        {
            return val
        }
        return _floatingInitialPosition
    }

    /// Title for card trigger, respecting mobile overrides if present.
    public var floatingTitle: String? {
        if let mobile = _mobile,
           let val = mobile["floating-title"]?.stringValue ?? mobile["floating_title"]?.stringValue
        {
            return val
        }
        return _floatingTitle
    }

    /// Description text for card trigger, respecting mobile overrides if present.
    public var floatingDesc: String? {
        if let mobile = _mobile,
           let val = mobile["floating-desc"]?.stringValue ?? mobile["floating_desc"]?.stringValue
        {
            return val
        }
        return _floatingDesc
    }

    /// Action button label for card trigger, respecting mobile overrides if present.
    public var floatingButtonText: String? {
        if let mobile = _mobile,
           let val = mobile["floating-buttontext"]?.stringValue
           ?? mobile["floating_buttontext"]?.stringValue
           ?? mobile["floating-button-text"]?.stringValue
           ?? mobile["floating_button_text"]?.stringValue
           ?? mobile["floating-bar-text-button"]?.stringValue
        {
            return val
        }
        return _floatingButtonText
    }

    /// Floating background color string (e.g. "rgb(174, 174, 209)" or "#00A3FF"), respecting mobile overrides.
    public var floatingBgColor: String? {
        if let mobile = _mobile,
           let val = mobile["floating-bgcolor"]?.stringValue
           ?? mobile["floating_bgcolor"]?.stringValue
           ?? mobile["floating-bg-color"]?.stringValue
           ?? mobile["floating_bg_color"]?.stringValue
        {
            return val
        }
        return _floatingBgColor
    }

    /// Floating text color string (e.g. "white" or "#FFFFFF"), respecting mobile overrides.
    public var floatingTextColor: String? {
        if let mobile = _mobile,
           let val = mobile["floating-textcolor"]?.stringValue
           ?? mobile["floating_textcolor"]?.stringValue
           ?? mobile["floating-text-color"]?.stringValue
           ?? mobile["floating_text_color"]?.stringValue
        {
            return val
        }
        return _floatingTextColor
    }

    /// Floating icon color string (e.g. "#1E3D54"), respecting mobile overrides.
    public var floatingIconColor: String? {
        if let mobile = _mobile,
           let val = mobile["floating-icon-color"]?.stringValue
           ?? mobile["floating_icon_color"]?.stringValue
           ?? mobile["floating-widget-icon-color"]?.stringValue
           ?? mobile["floating_widget_icon_color"]?.stringValue
        {
            return val
        }
        return _floatingIconColor
    }

    /// Design type version identifier (e.g. "2025-01"), respecting mobile overrides.
    public var floatingDesignType: String? {
        if let mobile = _mobile,
           let val = mobile["floating-design-type"]?.stringValue ?? mobile["floating_design_type"]?.stringValue
        {
            return val
        }
        return _floatingDesignType
    }

    /// Display type identifier (e.g. "slideover", "card"), respecting mobile overrides.
    public var floatingDisplayType: String? {
        if let mobile = _mobile,
           let val = mobile["floating-display-type"]?.stringValue ?? mobile["floating_display_type"]?.stringValue
        {
            return val
        }
        return _floatingDisplayType
    }

    /// Screen dock position (e.g. "bottom-right"), respecting mobile overrides.
    public var floatingPosition: String? {
        if let mobile = _mobile,
           let val = mobile["floating-position"]?.stringValue ?? mobile["floating_position"]?.stringValue
        {
            return val
        }
        return _floatingPosition
    }

    /// Border radius specification, respecting mobile overrides.
    public var floatingMobileTopBorderRadius: String? {
        if let mobile = _mobile,
           let val = mobile["floating-mobile-top-border-radius"]?.stringValue ?? mobile["floating_mobile_top_border_radius"]?.stringValue
        {
            return val
        }
        return _floatingMobileTopBorderRadius
    }

    /// Design type version identifier for the card/slideover trigger, e.g. "2025-01".
    private static let cardDesignType2025 = "2025-01"

    /// Resolved trigger type string, respecting mobile overrides if present.
    private var resolvedRawTriggerType: String? {
        if let mobile = _mobile,
           let val = mobile["trigger-type"]?.stringValue ?? mobile["trigger_type"]?.stringValue
        {
            return val.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        return _triggerType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Convenience check for box trigger type.
    public var isBoxTrigger: Bool {
        resolvedRawTriggerType == "box"
    }

    /// Convenience check for pill trigger type.
    public var isPillTrigger: Bool {
        resolvedRawTriggerType == "pill"
    }

    /// Convenience check for card trigger type (rounded slideover/card trigger).
    public var isCardTrigger: Bool {
        if isBoxTrigger || isPillTrigger {
            return false
        }
        let rawType = resolvedRawTriggerType
        if rawType == "card" || rawType == "slideover" || rawType == Self.cardDesignType2025 {
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

    /// Convenience check whether initial state should be active / expanded.
    public var isInitialActive: Bool {
        floatingInitialPosition?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "active"
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
        mobile: [String: AnyCodable]? = nil
    ) {
        _triggerType = triggerType
        _floatingBoxTextFirst = floatingBoxTextFirst
        _floatingBoxTextSecond = floatingBoxTextSecond
        _floatingImg = floatingImg
        _floatingSvg = floatingSvg
        _floatingInitialPosition = floatingInitialPosition
        _floatingTitle = floatingTitle
        _floatingDesc = floatingDesc
        _floatingButtonText = floatingButtonText
        _floatingBgColor = floatingBgColor
        _floatingTextColor = floatingTextColor
        _floatingIconColor = floatingIconColor
        _floatingDesignType = floatingDesignType
        _floatingDisplayType = floatingDisplayType
        _floatingPosition = floatingPosition
        _floatingMobileTopBorderRadius = floatingMobileTopBorderRadius
        _mobile = mobile
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKeys.self)

        func decodeString(forKeys keys: [String]) -> String? {
            for key in keys {
                if let codingKey = DynamicCodingKeys(stringValue: key),
                   let val = try? container.decode(String.self, forKey: codingKey)
                {
                    return val
                }
            }
            return nil
        }

        _triggerType = decodeString(forKeys: ["trigger-type", "trigger_type", "triggerType"])
        _floatingBoxTextFirst = decodeString(forKeys: ["floating-box-text-first", "floating_box_text_first", "floatingBoxTextFirst"])
        _floatingBoxTextSecond = decodeString(forKeys: ["floating-box-text-second", "floating_box_text_second", "floatingBoxTextSecond"])
        _floatingImg = decodeString(forKeys: ["floating-img", "floating_img", "floatingImg"])
        _floatingSvg = decodeString(forKeys: ["floating-svg", "floating_svg", "floatingSvg"])
        _floatingInitialPosition = decodeString(forKeys: ["floating-initial-position", "floating_initial_position", "floatingInitialPosition"])
        _floatingTitle = decodeString(forKeys: ["floating-title", "floating_title", "floatingTitle"])
        _floatingDesc = decodeString(forKeys: ["floating-desc", "floating_desc", "floatingDesc"])
        _floatingButtonText = decodeString(forKeys: [
            "floating-buttontext", "floating_buttontext", "floatingButtonText",
            "floating-button-text", "floating_button_text", "floating-bar-text-button",
        ])
        _floatingBgColor = decodeString(forKeys: [
            "floating-bgcolor", "floating_bgcolor", "floatingBgColor",
            "floating-bg-color", "floating_bg_color",
        ])
        _floatingTextColor = decodeString(forKeys: [
            "floating-textcolor", "floating_textcolor", "floatingTextColor",
            "floating-text-color", "floating_text_color",
        ])
        _floatingIconColor = decodeString(forKeys: [
            "floating-icon-color", "floating_icon_color", "floatingIconColor",
            "floating-widget-icon-color", "floating_widget_icon_color",
        ])
        _floatingDesignType = decodeString(forKeys: ["floating-design-type", "floating_design_type", "floatingDesignType"])
        _floatingDisplayType = decodeString(forKeys: ["floating-display-type", "floating_display_type", "floatingDisplayType"])
        _floatingPosition = decodeString(forKeys: ["floating-position", "floating_position", "floatingPosition"])
        _floatingMobileTopBorderRadius = decodeString(forKeys: ["floating-mobile-top-border-radius", "floating_mobile_top_border_radius", "floatingMobileTopBorderRadius"])

        if let mobileKey = DynamicCodingKeys(stringValue: "mobile"),
           let mobileDict = try? container.decode([String: AnyCodable].self, forKey: mobileKey)
        {
            _mobile = mobileDict
        } else {
            _mobile = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKeys.self)
        if let triggerType = _triggerType, let key = DynamicCodingKeys(stringValue: "trigger-type") {
            try container.encode(triggerType, forKey: key)
        }
        if let textFirst = _floatingBoxTextFirst, let key = DynamicCodingKeys(stringValue: "floating-box-text-first") {
            try container.encode(textFirst, forKey: key)
        }
        if let textSecond = _floatingBoxTextSecond, let key = DynamicCodingKeys(stringValue: "floating-box-text-second") {
            try container.encode(textSecond, forKey: key)
        }
        if let img = _floatingImg, let key = DynamicCodingKeys(stringValue: "floating-img") {
            try container.encode(img, forKey: key)
        }
        if let svg = _floatingSvg, let key = DynamicCodingKeys(stringValue: "floating-svg") {
            try container.encode(svg, forKey: key)
        }
        if let pos = _floatingInitialPosition, let key = DynamicCodingKeys(stringValue: "floating-initial-position") {
            try container.encode(pos, forKey: key)
        }
        if let title = _floatingTitle, let key = DynamicCodingKeys(stringValue: "floating-title") {
            try container.encode(title, forKey: key)
        }
        if let desc = _floatingDesc, let key = DynamicCodingKeys(stringValue: "floating-desc") {
            try container.encode(desc, forKey: key)
        }
        if let btn = _floatingButtonText, let key = DynamicCodingKeys(stringValue: "floating-buttontext") {
            try container.encode(btn, forKey: key)
        }
        if let bg = _floatingBgColor, let key = DynamicCodingKeys(stringValue: "floating-bgcolor") {
            try container.encode(bg, forKey: key)
        }
        if let textCol = _floatingTextColor, let key = DynamicCodingKeys(stringValue: "floating-textcolor") {
            try container.encode(textCol, forKey: key)
        }
        if let iconCol = _floatingIconColor, let key = DynamicCodingKeys(stringValue: "floating-icon-color") {
            try container.encode(iconCol, forKey: key)
        }
        if let dType = _floatingDesignType, let key = DynamicCodingKeys(stringValue: "floating-design-type") {
            try container.encode(dType, forKey: key)
        }
        if let dispType = _floatingDisplayType, let key = DynamicCodingKeys(stringValue: "floating-display-type") {
            try container.encode(dispType, forKey: key)
        }
        if let pos = _floatingPosition, let key = DynamicCodingKeys(stringValue: "floating-position") {
            try container.encode(pos, forKey: key)
        }
        if let rad = _floatingMobileTopBorderRadius, let key = DynamicCodingKeys(stringValue: "floating-mobile-top-border-radius") {
            try container.encode(rad, forKey: key)
        }
        if let mobile = _mobile, let key = DynamicCodingKeys(stringValue: "mobile") {
            try container.encode(mobile, forKey: key)
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
