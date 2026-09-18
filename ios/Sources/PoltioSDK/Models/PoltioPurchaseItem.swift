import Foundation

/// A single line item included in a purchase reported via `PoltioSDK.recordPurchase`.
public struct PoltioPurchaseItem {
    /// Product/SKU identifier.
    public let id: String

    /// Product display name.
    public let name: String?

    /// Product category.
    public let category: String?

    /// Quantity purchased.
    public let quantity: Int?

    /// Monetary value of this line item.
    public let value: Double?

    public init(
        id: String,
        name: String? = nil,
        category: String? = nil,
        quantity: Int? = nil,
        value: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.quantity = quantity
        self.value = value
    }
}
