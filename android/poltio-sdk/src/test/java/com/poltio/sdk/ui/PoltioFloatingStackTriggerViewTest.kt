package com.poltio.sdk.ui

import android.app.Activity
import android.app.Application
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.test.core.app.ApplicationProvider
import com.poltio.sdk.PoltioOverlayOptions
import com.poltio.sdk.PoltioTriggerDismissalStore
import com.poltio.sdk.PoltioWidgetResponse
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf

@RunWith(RobolectricTestRunner::class)
class PoltioFloatingStackTriggerViewTest {
    private val application = ApplicationProvider.getApplicationContext<Application>()

    @After
    fun tearDown() {
        PoltioTriggerDismissalStore.reset(application)
        PoltioOverlayManager.hideTrigger()
        idleMain()
    }

    private fun idleMain() = shadowOf(Looper.getMainLooper()).idle()

    private fun stackWidget(cards: String = CARDS, position: String = "bottom-right", initialPosition: String? = null) = PoltioWidgetResponse(
        publicId = "content_a",
        overlayOptions = PoltioOverlayOptions.fromJson(
            JSONObject()
                .put("trigger-type", "stack")
                .put("floating-position", position)
                .put("floating-stack-cards", cards)
                .apply { initialPosition?.let { put("floating-initial-position", it) } },
        ),
        widgetId = 77,
    )

    private fun stackView(widget: PoltioWidgetResponse = stackWidget(), onOpen: (String) -> Unit = {}): PoltioFloatingStackTriggerView {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        return PoltioFloatingStackTriggerView(activity, widget, widget.overlayOptions.stackCards!!) { onOpen(it.content) }
    }

    private fun shownTrigger(activity: Activity): View? {
        val contentRoot = activity.findViewById<FrameLayout>(android.R.id.content)
        val container = (0 until contentRoot.childCount).map(contentRoot::getChildAt).lastOrNull() as? ViewGroup ?: return null
        return (0 until container.childCount).map(container::getChildAt).firstOrNull { it is PoltioTriggerPresentable }
    }

    @Test
    fun `the overlay draws a stack, opens a back card's own content, and skips an unreadable card list`() {
        PoltioOverlayManager.attach(application)
        val controller = Robolectric.buildActivity(Activity::class.java).create().start().resume()
        val activity = controller.get()
        val reported = mutableListOf<String>()
        val original = PoltioOverlayManager.ctaViewReporter
        PoltioOverlayManager.ctaViewReporter = { reported += it.publicId }
        try {
            PoltioOverlayManager.showTrigger(stackWidget(), puid = "user_1")
            idleMain()
            val stack = shownTrigger(activity) as PoltioFloatingStackTriggerView
            assertEquals(listOf("content_a"), reported)

            stack.cardViews[2].performClick()
            idleMain()
            val intent = shadowOf(activity).nextStartedActivity
            assertEquals("content_c", intent.getStringExtra("com.poltio.sdk.extra.PUBLIC_ID"))
            assertEquals("77", intent.getStringExtra("com.poltio.sdk.extra.WIDGET_ID"))

            PoltioOverlayManager.hideTrigger()
            idleMain()
            PoltioOverlayManager.showTrigger(stackWidget(cards = "[]"), puid = null)
            idleMain()
            assertNull(shownTrigger(activity))
            assertEquals("an unreadable stack is never counted", listOf("content_a"), reported)
        } finally {
            PoltioOverlayManager.ctaViewReporter = original
            controller.destroy()
        }
    }

    @Test
    fun `every card is an accessible button and opens its own content`() {
        val opened = mutableListOf<String>()
        val view = stackView { opened += it }

        assertEquals(PoltioFloatingStackTriggerView.TriggerState.FANNED, view.state)
        view.cardViews[1].performClick()
        view.cardViews[0].performClick()
        assertEquals(listOf("content_b", "content_a"), opened)
        view.cardViews.forEach { card ->
            assertTrue(card.isClickable)
            assertTrue(card.contentDescription.contains(card.card.title))
        }
        assertEquals("Close", view.closeButton.contentDescription)
        assertTrue("the × draws over the front card", view.closeButton.elevation > view.cardViews[0].elevation)
    }

    @Test
    fun `the fan leans toward the middle of the screen`() {
        fun backCardShift(position: String): Pair<Float, Float> {
            val view = stackView(stackWidget(position = position))
            val probe = View(view.context)
            view.applyFanPose(probe, 1)
            return probe.translationX to probe.translationY
        }
        backCardShift("bottom-right").let { (x, y) -> assertTrue(x < 0 && y < 0) }
        backCardShift("bottom-left").let { (x, y) -> assertTrue(x > 0 && y < 0) }
        assertTrue(backCardShift("top-right").second > 0)
    }

    @Test
    fun `the fold is remembered for 48 hours without hiding the trigger`() {
        val view = stackView()
        view.closeButton.performClick()
        assertEquals(PoltioFloatingStackTriggerView.TriggerState.FOLDED, view.state)
        assertTrue(view.cardViews.none { it.isGlowing })

        val key = PoltioFloatingStackTriggerView.foldKey("content_a")
        val now = System.currentTimeMillis()
        assertTrue(PoltioTriggerDismissalStore.isDismissed(application, key, now + 47 * 3_600_000L))
        assertFalse(PoltioTriggerDismissalStore.isDismissed(application, key, now + 49 * 3_600_000L))
        assertFalse("a fold keeps the trigger on screen", PoltioTriggerDismissalStore.isDismissed(application, "content_a"))

        // Later screens start folded; the pill fans the cards out again.
        val next = stackView()
        assertEquals(PoltioFloatingStackTriggerView.TriggerState.FOLDED, next.state)
        next.pillView.performClick()
        assertEquals(PoltioFloatingStackTriggerView.TriggerState.FANNED, next.state)
    }

    @Test
    fun `a collapsed start shows the pill`() {
        assertEquals(PoltioFloatingStackTriggerView.TriggerState.FOLDED, stackView(stackWidget(initialPosition = "collapsed")).state)
    }

    private companion object {
        const val CARDS = """[{"content":"content_a","title":"Skincare","desc":"Let's find your routine","bg":"#f2a38f","opacity":"80"},{"content":"content_b","title":"Hair Care"},{"content":"content_c","title":"Sun Care"}]"""
    }
}
