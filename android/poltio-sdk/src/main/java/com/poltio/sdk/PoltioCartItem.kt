package com.poltio.sdk

import android.net.Uri

/**
 * A product the user added to their cart from the widget; see [PoltioSDK.onAddToCart]. A plain
 * class with an internal constructor (like iOS), so new fields never break host binaries.
 */
class PoltioCartItem internal constructor(
    /** The product's ID in your catalog (the widget's data-source item ID), if the widget sent one. */
    val productId: String?,
    /** The product page (http/https only); also opened as the fallback when no handler adds the item. */
    val url: Uri?,
    /** How many to add; at least 1. */
    val quantity: Int,
    /** The full `addToCart` payload, including any extra fields such as `sku`, `variant` or `price`. */
    val data: Map<String, Any?>,
) {
    internal companion object {
        /** Parses the widget's `addToCart` payload; `null` when it names neither a product nor a link. */
        fun from(data: Map<String, Any?>): PoltioCartItem? {
            fun trimmed(value: Any?) = (value as? String)?.trim()?.ifEmpty { null }

            val productId = trimmed(data["productId"]) ?: (data["productId"] as? Int ?: data["productId"] as? Long)?.toString()
            val url = trimmed(data["url"])?.let(Uri::parse)
                ?.takeIf { it.scheme?.lowercase() in setOf("http", "https") && !it.host.isNullOrEmpty() }
            if (productId == null && url == null) return null
            // Numbers or numeric strings, truncating fractions — same as iOS.
            val quantity = ((data["quantity"] as? Number)?.toInt() ?: trimmed(data["quantity"])?.toIntOrNull())?.takeIf { it > 0 } ?: 1
            return PoltioCartItem(productId, url, quantity, data)
        }
    }
}
