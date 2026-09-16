package com.poltio.sdk

import android.view.Gravity
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

// JSONObject's real implementation (not the "not mocked" stub) is only available under Robolectric.
@RunWith(RobolectricTestRunner::class)
class PoltioOverlayOptionsTest {
    private fun options(json: String): PoltioOverlayOptions = PoltioOverlayOptions.fromJson(JSONObject(json))

    @Test
    fun `resolves explicit trigger type`() {
        assertTrue(options("""{"trigger_type": "pill"}""").isPillTrigger)
        assertTrue(options("""{"trigger_type": "box"}""").isBoxTrigger)
        assertTrue(options("""{"trigger_type": "card"}""").isCardTrigger)
    }

    @Test
    fun `mobile overrides win over top-level fields`() {
        val opts = options(
            """{"floating_title": "Web Title", "mobile": {"floating_title": "Mobile Title"}}""",
        )
        assertEquals("Mobile Title", opts.floatingTitle)
    }

    @Test
    fun `card trigger heuristic fires when title or description present without explicit type`() {
        val opts = options("""{"floating_title": "Hello"}""")
        assertTrue(opts.isCardTrigger)
        assertEquals("card", opts.triggerType)
    }

    @Test
    fun `slideover design type resolves as card`() {
        assertTrue(options("""{"floating_design_type": "slideover"}""").isCardTrigger)
        assertTrue(options("""{"floating_display_type": "slideover"}""").isCardTrigger)
    }

    @Test
    fun `no trigger type and no card heuristic resolves to null`() {
        assertNull(options("{}").triggerType)
        assertFalse(options("{}").isBoxTrigger)
        assertFalse(options("{}").isPillTrigger)
        assertFalse(options("{}").isCardTrigger)
    }

    @Test
    fun `boolean fields default correctly and parse true-ish values`() {
        val defaults = options("{}")
        assertFalse(defaults.hideButton)
        assertTrue(defaults.showPulsate)

        assertTrue(options("""{"floating_hide_button": "true"}""").hideButton)
        assertTrue(options("""{"floating_hide_button": "1"}""").hideButton)
        assertFalse(options("""{"floating_show_pulsate": "false"}""").showPulsate)
    }

    @Test
    fun `numeric fields fall back to documented defaults`() {
        val opts = options("{}")
        assertEquals(100.0, opts.floatingZindex, 0.0)
        assertEquals(48.0, opts.pillCloseRememberDuration, 0.0)
        assertEquals(48.0, opts.boxCloseRememberDuration, 0.0)
        assertEquals(1.0, opts.boxResize, 0.0)
    }

    @Test
    fun `floating position splits into vertical and horizontal components`() {
        val opts = options("""{"floating_position": "top-left"}""")
        assertEquals("top", opts.verticalPosition)
        assertEquals("left", opts.horizontalPosition)

        val defaults = options("{}")
        assertEquals("bottom", defaults.verticalPosition)
        assertEquals("right", defaults.horizontalPosition)
    }

    @Test
    fun `css length parses px, em, rem, and bare numbers`() {
        assertEquals(16f, PoltioOverlayOptions.cssLength("16px", 0f), 0f)
        assertEquals(16f, PoltioOverlayOptions.cssLength("1rem", 0f), 0f)
        assertEquals(24f, PoltioOverlayOptions.cssLength("1.5em", 0f), 0f)
        assertEquals(20f, PoltioOverlayOptions.cssLength("20", 0f), 0f)
        assertEquals(10f, PoltioOverlayOptions.cssLength(null, 10f), 0f)
    }

    @Test
    fun `text alignment maps css keywords to gravity`() {
        assertEquals(Gravity.START, PoltioOverlayOptions.textAlignment("flex-start", Gravity.END))
        assertEquals(Gravity.CENTER_HORIZONTAL, PoltioOverlayOptions.textAlignment("center", Gravity.END))
        assertEquals(Gravity.END, PoltioOverlayOptions.textAlignment("flex-end", Gravity.START))
        assertEquals(Gravity.START, PoltioOverlayOptions.textAlignment(null, Gravity.START))
    }

    @Test
    fun `resolved image url resolves relative paths against the correct CDN prefix`() {
        val pill = options("""{"trigger_type": "pill", "floating_svg": "widget/icon.svg"}""")
        assertEquals("https://cdn.poltio.com/40x40/widget/icon.svg", pill.resolvedImageUrl())

        val box = options("""{"trigger_type": "box", "floating_img": "widget/banner.png"}""")
        assertEquals("https://cdn.poltio.com/240x120/widget/banner.png", box.resolvedImageUrl())

        val absolute = options("""{"floating_img": "https://cdn.example.com/x.png"}""")
        assertEquals("https://cdn.example.com/x.png", absolute.resolvedImageUrl())
    }

    @Test
    fun `equal fields produce equal instances`() {
        val a = options("""{"trigger_type": "pill", "floating_title": "Hi"}""")
        val b = options("""{"trigger_type": "pill", "floating_title": "Hi"}""")
        assertEquals(a, b)
        assertEquals(a.hashCode(), b.hashCode())
    }
}
