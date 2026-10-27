package com.poltio.sdk.ui

import android.app.Activity
import android.app.Application
import android.os.Looper
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.test.core.app.ApplicationProvider
import com.poltio.sdk.PoltioOverlayOptions
import com.poltio.sdk.PoltioWidgetResponse
import org.json.JSONObject
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf

@RunWith(RobolectricTestRunner::class)
class PoltioOverlayManagerTest {
    private fun widget(triggerType: String = "pill") = PoltioWidgetResponse(
        publicId = "shared_widget",
        overlayOptions = PoltioOverlayOptions.fromJson(JSONObject("""{"trigger-type":"$triggerType"}""")),
    )

    private fun idleMain() = shadowOf(Looper.getMainLooper()).idle()

    /** A card widget on the shared content; [widgetId] tells two such widgets apart. */
    private fun cardWidget(widgetId: Int) = PoltioWidgetResponse(
        publicId = "shared_widget",
        overlayOptions = PoltioOverlayOptions.fromJson(JSONObject("""{"trigger-type":"card"}""")),
        widgetId = widgetId,
    )

    @Test
    fun `a different widget on the same content and trigger type replaces the trigger`() {
        val application = ApplicationProvider.getApplicationContext<Application>()
        PoltioOverlayManager.attach(application)
        val controller = Robolectric.buildActivity(Activity::class.java).create().start().resume()
        val contentRoot = controller.get().findViewById<FrameLayout>(android.R.id.content)
        fun shownCard(): PoltioFloatingCardTriggerView? {
            val container = contentRoot.getChildAt(contentRoot.childCount - 1) as? ViewGroup ?: return null
            return (0 until container.childCount).map(container::getChildAt).filterIsInstance<PoltioFloatingCardTriggerView>().singleOrNull()
        }

        PoltioOverlayManager.showTrigger(cardWidget(widgetId = 1), puid = null)
        idleMain()
        val first = shownCard()
        assertNotNull(first)

        // The same widget again (a revisit, or one widget on two screens) keeps the trigger as it is.
        PoltioOverlayManager.showTrigger(cardWidget(widgetId = 1), puid = null)
        idleMain()
        assertSame(first, shownCard())

        // Another widget showing the same content as a card has its own copy, colors and position.
        PoltioOverlayManager.showTrigger(cardWidget(widgetId = 2), puid = null)
        idleMain()
        val second = shownCard()
        assertNotNull(second)
        assertNotSame(first, second)

        PoltioOverlayManager.hideTrigger()
        idleMain()
        controller.destroy()
    }

    @Test
    fun `showTrigger reattaches to a newly resumed Activity instead of reusing a backstacked one`() {
        val application = ApplicationProvider.getApplicationContext<Application>()
        PoltioOverlayManager.attach(application)

        // Activity 1 resolves the widget and gets the trigger attached to its content view.
        val controller1 = Robolectric.buildActivity(Activity::class.java).create().start().resume()
        val activity1 = controller1.get()

        PoltioOverlayManager.showTrigger(widget(), puid = null)
        idleMain()

        val contentRoot1 = activity1.findViewById<FrameLayout>(android.R.id.content)
        assertTrue("Trigger should be attached to Activity 1's content view", contentRoot1.childCount > 0)

        // Navigate to a *new* Activity — Activity 1 is only paused/stopped (backstacked), never
        // destroyed, so its stale overlay container is still attached to its (now off-screen)
        // content view. The same widget resolves again on Activity 2.
        controller1.pause().stop()

        val controller2 = Robolectric.buildActivity(Activity::class.java).create().start().resume()
        val activity2 = controller2.get()

        PoltioOverlayManager.showTrigger(widget(), puid = null)
        idleMain()

        val contentRoot2 = activity2.findViewById<FrameLayout>(android.R.id.content)
        assertTrue(
            "Trigger must be (re)attached to the newly resumed Activity, not left on the backstacked one",
            contentRoot2.childCount > 0,
        )

        PoltioOverlayManager.hideTrigger()
        idleMain()
        controller1.destroy()
        controller2.destroy()
    }
}
