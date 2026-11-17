package com.poltio.sdk

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

// JSONObject's real implementation (not the "not mocked" stub) is only available under Robolectric.
@RunWith(RobolectricTestRunner::class)
class PoltioWidgetResponseTest {
    @Test
    fun `fromJson decodes the numeric widget id`() {
        val json = JSONObject(
            """
            {
              "id": 8801,
              "public_id": "test-uuid-12345",
              "overlay_options": { "trigger-type": "box" }
            }
            """.trimIndent(),
        )

        val decoded = PoltioWidgetResponse.fromJson(json)

        assertEquals("test-uuid-12345", decoded.publicId)
        assertEquals(8801, decoded.widgetId)
    }

    @Test
    fun `fromJson leaves widgetId null when id is absent`() {
        val json = JSONObject(
            """
            {
              "public_id": "test-uuid-no-id",
              "overlay_options": { "trigger-type": "pill" }
            }
            """.trimIndent(),
        )

        val decoded = PoltioWidgetResponse.fromJson(json)

        assertNull(decoded.widgetId)
    }

    @Test
    fun `fromJson decodes a numeric string id instead of throwing`() {
        val json = JSONObject(
            """
            {
              "id": "8801",
              "public_id": "test-uuid-string-id",
              "overlay_options": { "trigger-type": "box" }
            }
            """.trimIndent(),
        )

        assertEquals(8801, PoltioWidgetResponse.fromJson(json).widgetId)
    }

    @Test
    fun `fromJson leaves widgetId null instead of throwing when id has an unexpected type`() {
        val json = JSONObject(
            """
            {
              "id": true,
              "public_id": "test-uuid-bad-id",
              "overlay_options": { "trigger-type": "box" }
            }
            """.trimIndent(),
        )

        // Must not throw JSONException — a malformed id should degrade to a missing widgetId,
        // not take down decoding of the whole widget response.
        assertNull(PoltioWidgetResponse.fromJson(json).widgetId)
    }

    private fun stackOptions(cards: String) =
        PoltioOverlayOptions.fromJson(JSONObject().put("trigger-type", "stack").put("floating-stack-cards", cards))

    @Test
    fun `stack cards decode from the JSON string field`() {
        val cards = """[{"content":" content_a ","title":"Skincare","desc":"Glow","button":"Go","text_color":"#111111","bg":"#f2a38f","button_bg":"#b8324a","opacity":"80","image":"widget/a.png"},{"content":"content_b","title":"Hair","opacity":20,"image":"https://example.com/b.png"}]"""
        val json = JSONObject()
            .put("public_id", "content_a")
            .put(
                "overlay_options",
                JSONObject()
                    .put("trigger-type", "stack")
                    .put("floating-title", "ignored by the stack")
                    .put("floating-stack-cards", cards)
                    .put("mobile", JSONObject().put("floating-stack-format", "compact")),
            )

        val options = PoltioWidgetResponse.fromJson(json).overlayOptions

        assertTrue(options.isStackTrigger)
        assertFalse("a stack's own copy must not make it a card trigger", options.isCardTrigger)
        assertEquals("stack", options.triggerType)
        assertTrue(options.isStackCompact)
        val stack = options.stackCards!!
        assertEquals(
            PoltioStackCard("content_a", "Skincare", "widget/a.png", "Glow", "Go", "#111111", "#f2a38f", "#b8324a", 80.0),
            stack[0],
        )
        assertEquals("https://cdn.poltio.com/160x160/widget/a.png", stack[0].imageUrl)
        assertEquals("https://example.com/b.png", stack[1].imageUrl)
        assertEquals(0.8f, stack[0].alpha, 0.001f)
        assertEquals("opacity below the panel's 40 is clamped", 0.4f, stack[1].alpha, 0.001f)
        assertFalse("expanded is the default format", stackOptions(cards).isStackCompact)
    }

    @Test
    fun `unreadable stack card lists are skipped`() {
        val sixCards = (1..6).joinToString(",", "[", "]") { """{"content":"c$it","title":"T"}""" }
        for (raw in listOf("", "not json", "{}", """[{"content":"a","title":"A"}]""", sixCards, """[{"content":"a","title":"A"},{"content":"b"}]""", """[{"content":"a","title":"A"},{"content":" ","title":"B"}]""")) {
            assertNull(raw, stackOptions(raw).stackCards)
        }
        assertNotNull(stackOptions("""[{"content":"a","title":"A"},{"content":"b","title":"B"}]""").stackCards)
    }

    @Test
    fun `a stack reports every other card's content once, never the widget's own`() {
        val options = stackOptions("""[{"content":"x","title":"A"},{"content":"y","title":"B"},{"content":"z","title":"C"},{"content":"y","title":"D"},{"content":"x","title":"E"}]""")
        assertEquals(listOf("y", "z"), options.otherStackContents("x"))
        assertEquals(emptyList<String>(), PoltioOverlayOptions.fromJson(JSONObject("""{"trigger-type":"pill"}""")).otherStackContents("x"))
    }
}
