package com.poltio.sdk

import android.graphics.Color
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class PoltioColorParserTest {
    @Test
    fun `parses named colors`() {
        assertEquals(Color.WHITE, PoltioColorParser.parse("white"))
        assertEquals(Color.BLACK, PoltioColorParser.parse("black"))
        assertEquals(Color.TRANSPARENT, PoltioColorParser.parse("transparent"))
    }

    @Test
    fun `parses 6-digit hex`() {
        assertEquals(Color.rgb(0x1E, 0x3D, 0x54), PoltioColorParser.parse("#1E3D54"))
    }

    @Test
    fun `parses 3-digit hex by expansion`() {
        assertEquals(Color.rgb(0xFF, 0xFF, 0xFF), PoltioColorParser.parse("#FFF"))
    }

    @Test
    fun `parses 8-digit hex as RRGGBBAA`() {
        assertEquals(Color.argb(0x80, 0x00, 0xA3, 0xFF), PoltioColorParser.parse("#00A3FF80"))
    }

    @Test
    fun `parses rgb and rgba`() {
        assertEquals(Color.rgb(174, 174, 209), PoltioColorParser.parse("rgb(174, 174, 209)"))
        assertEquals(Color.argb(230, 0, 163, 255), PoltioColorParser.parse("rgba(0, 163, 255, 0.9)"))
    }

    @Test
    fun `returns null for blank or garbage input`() {
        assertNull(PoltioColorParser.parse(null))
        assertNull(PoltioColorParser.parse(""))
        assertNull(PoltioColorParser.parse("not-a-color"))
    }
}
