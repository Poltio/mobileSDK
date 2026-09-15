package com.poltio.sdk

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

// JSONObject's real implementation (not the "not mocked" stub) is only available under Robolectric.
@RunWith(RobolectricTestRunner::class)
class PoltioWidgetCacheTest {
    private fun widget(publicId: String) = PoltioWidgetResponse(
        publicId = publicId,
        overlayOptions = PoltioOverlayOptions.fromJson(org.json.JSONObject()),
    )

    @Test
    fun `stores and retrieves a cached widget`() {
        val cache = PoltioWidgetCache()
        cache.set(CachedWidgetResult.Widget(widget("abc")), "https://example.com/a")

        val result = cache.get("https://example.com/a")
        assertEquals(CachedWidgetResult.Widget(widget("abc")), result)
    }

    @Test
    fun `zero TTL disables caching`() {
        val cache = PoltioWidgetCache(defaultTTLSeconds = 0.0)
        cache.set(CachedWidgetResult.NoWidget, "https://example.com/a")
        assertNull(cache.get("https://example.com/a"))
    }

    @Test
    fun `expired entries are evicted on read`() {
        val cache = PoltioWidgetCache(defaultTTLSeconds = 300.0)
        cache.set(CachedWidgetResult.NoWidget, "https://example.com/a", ttlSeconds = -1.0)
        // A negative effective TTL is rejected by set(); verify get() also treats it as absent.
        assertNull(cache.get("https://example.com/a"))
    }

    @Test
    fun `count limit evicts the least recently used entry`() {
        val cache = PoltioWidgetCache(countLimit = 2)
        cache.set(CachedWidgetResult.NoWidget, "a")
        cache.set(CachedWidgetResult.NoWidget, "b")
        cache.get("a") // touch "a" so "b" becomes least-recently-used
        cache.set(CachedWidgetResult.NoWidget, "c")

        assertEquals(CachedWidgetResult.NoWidget, cache.get("a"))
        assertNull(cache.get("b"))
        assertEquals(CachedWidgetResult.NoWidget, cache.get("c"))
    }

    @Test
    fun `clear removes all entries`() {
        val cache = PoltioWidgetCache()
        cache.set(CachedWidgetResult.NoWidget, "a")
        cache.clear()
        assertNull(cache.get("a"))
    }

    @Test
    fun `remove deletes a single entry`() {
        val cache = PoltioWidgetCache()
        cache.set(CachedWidgetResult.NoWidget, "a")
        cache.set(CachedWidgetResult.NoWidget, "b")
        cache.remove("a")
        assertNull(cache.get("a"))
        assertEquals(CachedWidgetResult.NoWidget, cache.get("b"))
    }
}
