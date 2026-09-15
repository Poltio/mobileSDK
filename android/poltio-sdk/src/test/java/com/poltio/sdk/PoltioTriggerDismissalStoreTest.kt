package com.poltio.sdk

import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class PoltioTriggerDismissalStoreTest {
    private val context = ApplicationProvider.getApplicationContext<android.content.Context>()

    @After
    fun tearDown() {
        PoltioTriggerDismissalStore.reset(context)
    }

    @Test
    fun `not dismissed by default`() {
        assertFalse(PoltioTriggerDismissalStore.isDismissed(context, "widget-1"))
    }

    @Test
    fun `recording a dismissal suppresses within the window`() {
        val now = 1_000_000L
        PoltioTriggerDismissalStore.recordDismissal(context, "widget-1", hours = 1.0, nowMs = now)

        assertTrue(PoltioTriggerDismissalStore.isDismissed(context, "widget-1", nowMs = now + 1_000))
        assertFalse(PoltioTriggerDismissalStore.isDismissed(context, "widget-1", nowMs = now + 3_600_001))
    }

    @Test
    fun `zero or negative hours does not record a dismissal`() {
        PoltioTriggerDismissalStore.recordDismissal(context, "widget-1", hours = 0.0)
        assertFalse(PoltioTriggerDismissalStore.isDismissed(context, "widget-1"))
    }

    @Test
    fun `dismissals persist across store instances via SharedPreferences`() {
        PoltioTriggerDismissalStore.recordDismissal(context, "widget-2", hours = 2.0)
        // A fresh lookup re-reads from SharedPreferences rather than any in-memory cache.
        assertTrue(PoltioTriggerDismissalStore.isDismissed(context, "widget-2"))
    }
}
