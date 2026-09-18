package com.poltio.sdk

/** A single line item included in a purchase reported via [PoltioSDK.recordPurchase]. */
data class PoltioPurchaseItem(
    /** Product/SKU identifier. */
    val id: String,
    /** Product display name. */
    val name: String? = null,
    /** Product category. */
    val category: String? = null,
    /** Quantity purchased. */
    val quantity: Int? = null,
    /** Monetary value of this line item. */
    val value: Double? = null,
)
