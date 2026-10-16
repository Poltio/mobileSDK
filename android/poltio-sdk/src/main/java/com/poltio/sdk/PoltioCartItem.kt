package com.poltio.sdk

import android.net.Uri

/** A product the user added to their cart from the widget; see [PoltioSDK.onAddToCart]. */
data class PoltioCartItem(
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
            val productId = when (val raw = data["productId"]) {
                is String -> raw.trim().ifEmpty { null }
                is Int, is Long -> raw.toString()
                else -> null
            }
            val url = (data["url"] as? String)?.trim()?.let(Uri::parse)
                ?.takeIf { it.scheme?.lowercase() == "https" || it.scheme?.lowercase() == "http" }
            if (productId == null && url == null) return null
            val quantity = (data["quantity"] as? Number)?.toInt()?.takeIf { it > 0 } ?: 1
            return PoltioCartItem(productId, url, quantity, data)
        }
    }
}
