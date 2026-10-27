package com.poltio.sdk.ui

import android.content.Context
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import androidx.test.core.app.ApplicationProvider
import com.poltio.sdk.PoltioOverlayOptions
import com.poltio.sdk.PoltioWidgetResponse
import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class PoltioEdgeTabTriggerTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    private fun widget(triggerType: String, position: String?) = PoltioWidgetResponse(
        publicId = "edge_tab",
        overlayOptions = PoltioOverlayOptions.fromJson(
            JSONObject().apply {
                put("trigger-type", triggerType)
                position?.let { put("floating-position", it) }
            },
        ),
    )

    private fun edgeGravity(view: View) = (view.layoutParams as FrameLayout.LayoutParams).gravity and Gravity.RELATIVE_HORIZONTAL_GRAVITY_MASK

    private fun cornerRadii(view: View) = (view.background as GradientDrawable).cornerRadii

    @Test
    fun `only bottom-left and its siblings dock on the left`() {
        assertTrue(widget("box", "bottom-left").overlayOptions.isLeftDocked)
        assertTrue(widget("box", "center-left").overlayOptions.isLeftDocked)
        assertFalse(widget("box", "bottom-right").overlayOptions.isLeftDocked)
        assertFalse(widget("box", null).overlayOptions.isLeftDocked)
    }

    @Test
    fun `edge tabs round only the corners facing the screen`() {
        // GradientDrawable order: top-left, top-right, bottom-right, bottom-left (x, y each).
        assertArrayEquals(floatArrayOf(7f, 7f, 0f, 0f, 0f, 0f, 7f, 7f), edgeTabCornerRadii(7f, isLeftDocked = false), 0f)
        assertArrayEquals(floatArrayOf(0f, 0f, 7f, 7f, 7f, 7f, 0f, 0f), edgeTabCornerRadii(7f, isLeftDocked = true), 0f)
    }

    @Test
    fun `box trigger mirrors on the left edge`() {
        for ((position, left) in listOf(null to false, "bottom-right" to false, "bottom-left" to true, "center-left" to true)) {
            val box = PoltioFloatingBoxTriggerView(context, widget("box", position), onOpenWidget = {})
            // Child 0 is the collapsed edge tab, child 1 the expanded card.
            val tab = box.getChildAt(0)
            val expanded = box.getChildAt(1)
            val label = "box at ${position ?: "default"}"
            val r = context.dp(14f).toFloat()

            assertArrayEquals(label, edgeTabCornerRadii(r, left), cornerRadii(tab), 0f)
            assertEquals(label, if (left) Gravity.START else Gravity.END, edgeGravity(tab))
            assertEquals(label, if (left) Gravity.START else Gravity.END, edgeGravity(expanded))
            assertEquals(label, if (left) 90f else -90f, (tab as FrameLayout).getChildAt(0).rotation, 0f)
        }
    }

    @Test
    fun `card trigger mirrors on the left edge`() {
        for ((position, left) in listOf(null to false, "bottom-right" to false, "bottom-left" to true)) {
            val card = PoltioFloatingCardTriggerView(context, widget("card", position), onOpenWidget = {})
            val tab = card.getChildAt(0)
            val expanded = card.getChildAt(1)
            val label = "card at ${position ?: "default"}"
            val r = context.dp(24f).toFloat()
            val margin = context.dp(16f)
            val expandedParams = expanded.layoutParams as FrameLayout.LayoutParams

            assertArrayEquals(label, edgeTabCornerRadii(r, left), cornerRadii(tab), 0f)
            assertEquals(label, if (left) Gravity.START else Gravity.END, edgeGravity(tab))
            assertEquals(label, if (left) Gravity.START else Gravity.END, edgeGravity(expanded))
            assertEquals(label, if (left) margin else 0, expandedParams.leftMargin)
            assertEquals(label, if (left) 0 else margin, expandedParams.rightMargin)
        }
    }
}
