package com.poltio.sdk.ui

import android.app.Activity
import android.os.Looper
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf

@RunWith(RobolectricTestRunner::class)
class PoltioTriggerIconLoaderTest {
    /** Lays [icon] over a clickable "trigger", taps the middle of it, and reports whether the trigger got the click. */
    private fun tapReachesTrigger(makeIcon: (Activity) -> View): Boolean {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        var clicked = false
        val trigger = FrameLayout(activity).apply {
            isClickable = true
            setOnClickListener { clicked = true }
        }
        // Covers the whole trigger, like the SVG icon covering most of the collapsed pill.
        trigger.addView(makeIcon(activity), FrameLayout.LayoutParams(200, 200))
        activity.setContentView(trigger, FrameLayout.LayoutParams(200, 200))
        trigger.measure(
            View.MeasureSpec.makeMeasureSpec(200, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(200, View.MeasureSpec.EXACTLY),
        )
        trigger.layout(0, 0, 200, 200)
        shadowOf(Looper.getMainLooper()).idle()

        val downTime = SystemClock.uptimeMillis()
        val down = MotionEvent.obtain(downTime, downTime, MotionEvent.ACTION_DOWN, 100f, 100f, 0)
        val up = MotionEvent.obtain(downTime, downTime + 50, MotionEvent.ACTION_UP, 100f, 100f, 0)
        trigger.dispatchTouchEvent(down)
        trigger.dispatchTouchEvent(up)
        shadowOf(Looper.getMainLooper()).idle()
        down.recycle()
        up.recycle()
        return clicked
    }

    // Note: Robolectric's WebView is a shadow that doesn't consume touches like the real one does,
    // so the original bug (a plain WebView swallowing the tap) only reproduces on a device/emulator.
    // This pins the passthrough contract that the fix relies on.
    @Test
    fun `svg icon webview lets taps fall through to the trigger underneath`() {
        assertTrue(tapReachesTrigger { PoltioNonInteractiveWebView(it) })
    }
}
