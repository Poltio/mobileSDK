import Foundation

/// A product the user added to their cart from the widget; see `PoltioSDK.onAddToCart`.
public struct PoltioCartItem {
    /// The product's ID in your catalog (the widget's data-source item ID), if the widget sent one.
    public let productId: String?

    /// The product page (http/https only); also opened as the fallback when no handler adds the item.
    public let url: URL?

    /// How many to add; at least 1.
    public let quantity: Int

    /// The full `addToCart` payload, including any extra fields such as `sku`, `variant` or `price`.
    public let data: [String: Any]

    /// Parses the widget's `addToCart` payload; `nil` when it names neither a product nor a link.
    init?(data: [String: Any]) {
        func trimmed(_ value: Any?) -> String? {
            ((value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        }
        // Accept numbers or numeric strings, truncating fractions — same as Android.
        func integer(_ value: Any?) -> Int? {
            (value as? NSNumber)?.intValue ?? trimmed(value).flatMap { Int($0) }
        }

        productId = trimmed(data["productId"]) ?? (data["productId"] as? Int).map(String.init)
        url = trimmed(data["url"]).flatMap { URL(string: $0) }.flatMap { url in
            ["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.host?.isEmpty == false ? url : nil
        }
        guard productId != nil || url != nil else { return nil }
        quantity = integer(data["quantity"]).flatMap { $0 > 0 ? $0 : nil } ?? 1
        self.data = data
    }
}
