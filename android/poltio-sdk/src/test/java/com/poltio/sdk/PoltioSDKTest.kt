package com.poltio.sdk

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class PoltioSDKTest {
    private val application = ApplicationProvider.getApplicationContext<Application>()

    @After
    fun tearDown() {
        PoltioSDK.reset()
    }

    @Test
    fun `not initialized before configure`() {
        assertFalse(PoltioSDK.isInitialized)
        assertNull(PoltioSDK.clientKey)
    }

    @Test
    fun `configure trims the client key and marks the SDK initialized`() {
        PoltioSDK.configure(application, clientKey = "  poltio_test_pk_123  ")
        assertTrue(PoltioSDK.isInitialized)
        assertEquals("poltio_test_pk_123", PoltioSDK.clientKey)
    }

    @Test
    fun `blank client key is rejected and leaves the SDK uninitialized`() {
        PoltioSDK.configure(application, clientKey = "   ")
        assertFalse(PoltioSDK.isInitialized)
        assertNull(PoltioSDK.clientKey)
    }

    @Test
    fun `sdkId is stable across repeated access and looks like a UUID`() {
        PoltioSDK.configure(application, clientKey = "poltio_test_pk_123")
        val first = PoltioSDK.sdkId
        val second = PoltioSDK.sdkId
        assertEquals(first, second)
        assertTrue(first.matches(Regex("[0-9a-f-]{36}")))
    }

    @Test
    fun `identify sets and clears puid`() {
        PoltioSDK.configure(application, clientKey = "poltio_test_pk_123")

        PoltioSDK.identify("user-42")
        assertEquals("user-42", PoltioSDK.puid)

        PoltioSDK.identify(null)
        assertNull(PoltioSDK.puid)

        PoltioSDK.identify("  ")
        assertNull(PoltioSDK.puid)
    }

    @Test
    fun `isViewEvent recognizes all documented aliases case-insensitively`() {
        assertTrue(PoltioSDK.isViewEvent("view"))
        assertTrue(PoltioSDK.isViewEvent("VIEW"))
        assertTrue(PoltioSDK.isViewEvent("viewContent"))
        assertTrue(PoltioSDK.isViewEvent("view_content"))
        assertFalse(PoltioSDK.isViewEvent("TrackConversion"))
    }

    @Test
    fun `track before configure is a no-op and does not throw`() {
        PoltioSDK.track("view", mapOf("url" to "https://example.com"))
        // No assertion beyond "did not throw" — the SDK must never crash the host app.
    }

    @Test
    fun `track with a blank event name is a no-op and does not throw`() {
        PoltioSDK.configure(application, clientKey = "poltio_test_pk_123")
        PoltioSDK.track("   ")
    }

    @Test
    fun `clearCache and cache configuration do not throw`() {
        PoltioSDK.cacheTTL = 60.0
        PoltioSDK.cacheLimit = 10
        PoltioSDK.clearCache()
        assertEquals(60.0, PoltioSDK.cacheTTL, 0.0)
        assertEquals(10, PoltioSDK.cacheLimit)
    }
}
