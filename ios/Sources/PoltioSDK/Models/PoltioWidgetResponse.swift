import Foundation

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
    private let _floatingInitialPosition: String?
    private let _mobile: [String: AnyCodable]?

    /// The resolved trigger type (e.g. "box", "pill", "bar"), respecting mobile overrides if present.
    public var triggerType: String? {
        if let mobile = _mobile, let val = mobile["trigger-type"]?.stringValue ?? mobile["trigger_type"]?.stringValue {
            return val
        }
        return _triggerType
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

    /// Initial trigger position / state (e.g. "active", "collapsed"), respecting mobile overrides if present.
    public var floatingInitialPosition: String? {
        if let mobile = _mobile,
           let val = mobile["floating-initial-position"]?.stringValue ?? mobile["floating_initial_position"]?.stringValue
        {
            return val
        }
        return _floatingInitialPosition
    }

    /// Convenience check for box trigger type.
    public var isBoxTrigger: Bool {
        return triggerType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "box"
    }

    /// Convenience check whether initial state should be active / expanded.
    public var isInitialActive: Bool {
        return floatingInitialPosition?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "active"
    }

    /// Resolves the full URL for `floatingImg`.
    /// If `floatingImg` is an absolute URL (`http://` or `https://`), it is returned directly.
    /// If it is a relative path (e.g. `widget/box-default.png`), it is resolved using the CDN prefix (default: `https://cdn.poltio.com/240x120/`).
    public func resolvedImageUrl(cdnPrefix: String = "https://cdn.poltio.com/240x120") -> URL? {
        guard let rawImgPath = floatingImg?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawImgPath.isEmpty
        else {
            return nil
        }

        if rawImgPath.hasPrefix("http://") || rawImgPath.hasPrefix("https://") {
            return URL(string: rawImgPath)
        }

        let cleanPath = rawImgPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let cleanPrefix = cdnPrefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(cleanPrefix)/\(cleanPath)")
    }

    public init(
        triggerType: String? = nil,
        floatingBoxTextFirst: String? = nil,
        floatingBoxTextSecond: String? = nil,
        floatingImg: String? = nil,
        floatingInitialPosition: String? = nil,
        mobile: [String: AnyCodable]? = nil
    ) {
        _triggerType = triggerType
        _floatingBoxTextFirst = floatingBoxTextFirst
        _floatingBoxTextSecond = floatingBoxTextSecond
        _floatingImg = floatingImg
        _floatingInitialPosition = floatingInitialPosition
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
        _floatingInitialPosition = decodeString(forKeys: ["floating-initial-position", "floating_initial_position", "floatingInitialPosition"])

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
        if let pos = _floatingInitialPosition, let key = DynamicCodingKeys(stringValue: "floating-initial-position") {
            try container.encode(pos, forKey: key)
        }
        if let mobile = _mobile, let key = DynamicCodingKeys(stringValue: "mobile") {
            try container.encode(mobile, forKey: key)
        }
    }
}

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
        } else {
            try container.encode("\(value)")
        }
    }

    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        String(describing: lhs.value) == String(describing: rhs.value)
    }
}
