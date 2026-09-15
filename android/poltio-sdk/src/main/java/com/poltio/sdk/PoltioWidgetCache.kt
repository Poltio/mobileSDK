package com.poltio.sdk

/** Cached outcome of a widget resolution request for a target URL. */
internal sealed class CachedWidgetResult {
    /** Successfully resolved widget metadata. */
    data class Widget(val response: PoltioWidgetResponse) : CachedWidgetResult()

    /** Explicitly verified that no widget is configured for this URL (404 Not Found). */
    object NoWidget : CachedWidgetResult()
}

/**
 * Lightweight, in-memory ephemeral cache manager for widget resolutions. Automatically limits its
 * memory footprint via an access-ordered LRU map and expires entries after the configured TTL.
 */
internal class PoltioWidgetCache(
    defaultTTLSeconds: Double = 300.0,
    countLimit: Int = 100,
) {
    private data class Entry(val result: CachedWidgetResult, val expiresAtMs: Long)

    private val lock = Any()

    /** Default Time-To-Live in seconds for cached widget responses (default is 300s / 5 minutes). */
    @Volatile
    var defaultTTL: Double = defaultTTLSeconds

    /** Maximum number of items retained in the cache before older items are evicted (default is 100). */
    var countLimit: Int = countLimit
        set(value) {
            field = value
            synchronized(lock) { trimToLimit() }
        }

    private val map = object : LinkedHashMap<String, Entry>(16, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Entry>): Boolean {
            return size > countLimit
        }
    }

    /** Retrieves the cached widget result for the specified URL if present and unexpired. */
    fun get(url: String): CachedWidgetResult? {
        val ttl = defaultTTL
        if (ttl <= 0) return null

        synchronized(lock) {
            val entry = map[url] ?: return null
            if (System.currentTimeMillis() >= entry.expiresAtMs) {
                map.remove(url)
                PoltioLogger.debug { "Cache entry expired for '$url'." }
                return null
            }
            return entry.result
        }
    }

    /** Stores a widget resolution outcome in the cache. */
    fun set(result: CachedWidgetResult, url: String, ttlSeconds: Double? = null) {
        val effectiveTTL = ttlSeconds ?: defaultTTL
        if (effectiveTTL <= 0) return

        synchronized(lock) {
            map[url] = Entry(result, System.currentTimeMillis() + (effectiveTTL * 1000).toLong())
        }
        PoltioLogger.debug { "Cached widget resolution for '$url' (TTL: ${effectiveTTL.toInt()}s)." }
    }

    /** Removes the cached entry for a specific URL. */
    fun remove(url: String) {
        synchronized(lock) { map.remove(url) }
    }

    /** Clears all entries from the in-memory cache. */
    fun clear() {
        synchronized(lock) { map.clear() }
        PoltioLogger.debug { "Widget cache cleared." }
    }

    private fun trimToLimit() {
        val iterator = map.entries.iterator()
        while (map.size > countLimit && iterator.hasNext()) {
            iterator.next()
            iterator.remove()
        }
    }
}
