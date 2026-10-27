package com.poltio.sdk.ui

import android.app.Activity
import android.app.Application
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.test.core.app.ApplicationProvider
import com.poltio.sdk.PoltioOverlayOptions
import com.poltio.sdk.PoltioWidgetResponse
import java.util.concurrent.TimeUnit
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertNull
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

    private fun boxWidget(position: String) = PoltioWidgetResponse(
        publicId = "box_widget",
        overlayOptions = PoltioOverlayOptions.fromJson(JSONObject("""{"trigger-type":"box","floating-position":"$position"}""")),
        widgetId = 7,
    )

    /** The trigger the overlay manager attached to [activity], if any. */
    private fun shownTrigger(activity: Activity): View? {
        val contentRoot = activity.findViewById<FrameLayout>(android.R.id.content)
        val container = (0 until contentRoot.childCount).map(contentRoot::getChildAt).lastOrNull() as? ViewGroup ?: return null
        return (0 until container.childCount).map(container::getChildAt).firstOrNull { it is PoltioTriggerPresentable }
    }

    @Test
    fun `triggers keep their physical side in a right-to-left layout`() {
        val application = ApplicationProvider.getApplicationContext<Application>()
        PoltioOverlayManager.attach(application)
        val controller = Robolectric.buildActivity(Activity::class.java).create().start().resume()
        val activity = controller.get()

        for ((position, onLeft) in listOf("bottom-left" to true, "bottom-right" to false)) {
            PoltioOverlayManager.showTrigger(boxWidget(position), puid = null)
            idleMain()
            val trigger = shownTrigger(activity)!!
            val container = trigger.parent as ViewGroup
            container.layoutDirection = View.LAYOUT_DIRECTION_RTL
            container.measure(View.MeasureSpec.makeMeasureSpec(1080, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(1920, View.MeasureSpec.EXACTLY))
            container.layout(0, 0, 1080, 1920)

            if (onLeft) assertEquals(position, 0, trigger.left) else assertEquals(position, 1080, trigger.right)
            PoltioOverlayManager.hideTrigger()
            idleMain()
        }
        controller.destroy()
    }

    @Test
    fun `the widget sheet never hosts the trigger, which waits for the host to resume`() {
        val application = ApplicationProvider.getApplicationContext<Application>()
        PoltioOverlayManager.attach(application)
        val host = Robolectric.buildActivity(Activity::class.java).create().start().resume()

        // The host is paused under the widget sheet, as after a rotation rebuilds it behind the sheet.
        host.pause()
        val sheetIntent = PoltioWebViewActivity.newIntent(application, "box_widget", 7, null, null)
        val sheet = Robolectric.buildActivity(PoltioWebViewActivity::class.java, sheetIntent).setup()

        PoltioOverlayManager.showTrigger(boxWidget("bottom-left"), puid = null)
        idleMain()
        assertNull("The sheet must not host the trigger", shownTrigger(sheet.get()))
        assertNull("The paused host can't show it yet", shownTrigger(host.get()))

        // Closing the sheet resumes the host, which then shows the widget it was kept for.
        sheet.pause().stop().destroy()
        host.resume()
        idleMain()
        assertNotNull("The trigger must show once the host resumes", shownTrigger(host.get()))

        PoltioOverlayManager.hideTrigger()
        idleMain()
        host.destroy()
    }

    /** Runs [block] with trigger views counted into a list of widget ids, then restores the reporter.
     * Inline so a failing assertion inside [block] reports its own line. */
    private inline fun countingViews(block: (reported: List<Int?>) -> Unit) {
        val original = PoltioOverlayManager.ctaViewReporter
        val reported = mutableListOf<Int?>()
        PoltioOverlayManager.ctaViewReporter = { reported += it.widgetId }
        try {
            block(reported)
        } finally {
            PoltioOverlayManager.ctaViewReporter = original
        }
    }

    @Test
    fun `rebuilding the host behind the widget sheet brings the trigger back visible once the sheet closes`() = countingViews { reported ->
        val application = ApplicationProvider.getApplicationContext<Application>()
        PoltioOverlayManager.attach(application)
        val host = Robolectric.buildActivity(Activity::class.java).create().start().resume()
        PoltioOverlayManager.showTrigger(boxWidget("bottom-left"), puid = null)
        idleMain()

        // Opening the widget hides the trigger, and the translucent sheet covers the paused host.
        PoltioOverlayManager.presentWidgetWebView("box_widget", 7, puid = null)
        idleMain()
        host.pause()
        val sheetIntent = PoltioWebViewActivity.newIntent(application, "box_widget", 7, null, null)
        val sheet = Robolectric.buildActivity(PoltioWebViewActivity::class.java, sheetIntent).setup()

        // A rotation rebuilds the host behind the sheet: it resumes for a moment and pauses again.
        host.recreate()
        idleMain()
        assertNull("Nothing may attach under the sheet", shownTrigger(host.get()))

        // Closing the sheet resumes the host, and only then is the finished sheet destroyed.
        sheet.pause()
        host.resume()
        idleMain()
        sheet.stop().destroy()
        shadowOf(Looper.getMainLooper()).idleFor(1, TimeUnit.SECONDS)

        val trigger = shownTrigger(host.get())
        assertNotNull("The trigger must come back", trigger)
        assertEquals("It must settle on screen, not beside it", 0f, trigger!!.translationX, 0f)
        assertEquals(1f, trigger.alpha, 0f)
        assertEquals("Counted once, before the rotation", listOf<Int?>(7), reported)

        PoltioOverlayManager.hideTrigger()
        idleMain()
        host.destroy()
    }

    @Test
    fun `a rotation keeps the trigger without counting it again`() = countingViews { reported ->
        val application = ApplicationProvider.getApplicationContext<Application>()
        PoltioOverlayManager.attach(application)
        val host = Robolectric.buildActivity(Activity::class.java).create().start().resume()
        PoltioOverlayManager.showTrigger(boxWidget("bottom-left"), puid = null)
        idleMain()

        host.recreate()
        idleMain()
        val carriedOver = shownTrigger(host.get())
        assertNotNull("The rebuilt host gets the trigger back", carriedOver)
        assertEquals("The rotation itself isn't a new view", listOf<Int?>(7), reported)

        // A host that tracks its screen again after rotating still counts that one view, as before.
        PoltioOverlayManager.showTrigger(boxWidget("bottom-left"), puid = null)
        idleMain()
        assertSame(carriedOver, shownTrigger(host.get()))
        assertEquals(listOf<Int?>(7, 7), reported)

        PoltioOverlayManager.hideTrigger()
        idleMain()
        host.destroy()
    }

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
