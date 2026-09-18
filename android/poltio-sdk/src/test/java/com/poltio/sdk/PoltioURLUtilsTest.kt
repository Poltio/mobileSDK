package com.poltio.sdk

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

// `android.net.Uri`'s real implementation (not the "not mocked" stub) is only available under Robolectric.
@RunWith(RobolectricTestRunner::class)
class PoltioURLUtilsTest {
    @Test
    fun `blank input falls back to default URL`() {
        assertEquals("https://app.poltio.com/default", sanitizeOrFormatURL(""))
        assertEquals("https://app.poltio.com/default", sanitizeOrFormatURL("   "))
    }

    @Test
    fun `well-formed absolute URL passes through unchanged`() {
        assertEquals("https://www.poltio.com/pdp", sanitizeOrFormatURL("https://www.poltio.com/pdp"))
    }

    @Test
    fun `path without scheme is anchored under the default host`() {
        assertEquals("https://app.poltio.com/pdp", sanitizeOrFormatURL("pdp"))
        assertEquals("https://app.poltio.com/pdp", sanitizeOrFormatURL("/pdp/"))
    }

    @Test
    fun `spaces in an absolute URL are percent-encoded`() {
        assertEquals("https://app.poltio.com/50%25%20off", sanitizeOrFormatURL("https://app.poltio.com/50% off"))
    }

    @Test
    fun `already percent-encoded sequences are not double-encoded`() {
        assertEquals("https://app.poltio.com/a%20b", sanitizeOrFormatURL("https://app.poltio.com/a%20b"))
    }

    @Test
    fun `stray percent signs are escaped`() {
        assertEquals("https://app.poltio.com/50%25off", sanitizeOrFormatURL("https://app.poltio.com/50%off"))
    }

    @Test
    fun `characters outside the BMP are encoded as whole code points, not split surrogates`() {
        // U+1F600 GRINNING FACE is a surrogate pair in UTF-16; a naive Char-by-Char encoder
        // mangles each half into a replacement byte (%EF%BF%BD) instead of the real UTF-8 bytes.
        assertEquals("https://app.poltio.com/%F0%9F%98%80", sanitizeOrFormatURL("https://app.poltio.com/😀"))
    }

    @Test
    fun `isValidConversionURL accepts absolute URLs and deep links with scheme and host`() {
        assertTrue(isValidConversionURL("https://www.poltio.com/checkout/complete"))
        assertTrue(isValidConversionURL("myapp://checkout/complete"))
        assertTrue(isValidConversionURL("myapp://checkout"))
    }

    @Test
    fun `isValidConversionURL rejects blank input and bare paths without a fallback`() {
        assertFalse(isValidConversionURL(""))
        assertFalse(isValidConversionURL("checkout/complete"))
        assertFalse(isValidConversionURL("/checkout/complete"))
    }
}
