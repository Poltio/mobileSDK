package com.poltio.sdk

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
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
}
