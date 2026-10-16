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
        if let id = data["productId"] as? String, !id.trimmingCharacters(in: .whitespaces).isEmpty {
            productId = id.trimmingCharacters(in: .whitespaces)
        } else if let id = data["productId"] as? Int {
            productId = String(id)
        } else {
            productId = nil
        }
        url = (data["url"] as? String)
            .flatMap { URL(string: $0.trimmingCharacters(in: .whitespaces)) }
            .flatMap { ["http", "https"].contains($0.scheme?.lowercased() ?? "") ? $0 : nil }
        guard productId != nil || url != nil else { return nil }
        quantity = (data["quantity"] as? Int).flatMap { $0 > 0 ? $0 : nil } ?? 1
        self.data = data
    }
}
