package com.poltio.sdk

import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class PoltioEnvironmentTest {
    private val context = ApplicationProvider.getApplicationContext<android.content.Context>()

    @Test
    fun `explicit override wins regardless of debuggable flag`() {
        assertEquals(PoltioEnvironment.STAGE, PoltioEnvironment.resolve(context, useStage = true))
        assertEquals(PoltioEnvironment.PRODUCTION, PoltioEnvironment.resolve(context, useStage = false))
    }

    @Test
    fun `null override falls back to automatic detection`() {
        assertEquals(PoltioEnvironment.automatic(context), PoltioEnvironment.resolve(context, useStage = null))
    }

    @Test
    fun `base URLs match the documented endpoints`() {
        assertEquals("https://sdk.poltio.com", PoltioEnvironment.PRODUCTION.baseURL)
        assertEquals("https://sdk-stage.poltio.com", PoltioEnvironment.STAGE.baseURL)
    }
}
