package com.poltio.sdk

import android.content.Context
import android.content.pm.ApplicationInfo

/**
 * Backend API environment the SDK talks to.
 *
 * By default the SDK auto-detects the environment from the host app's `android:debuggable` flag
 * (set automatically by the Android Gradle Plugin for debug vs. release build types) — the
 * closest Android equivalent of iOS's Debug/Release build-configuration detection. Developers can
 * override this via `PoltioSDK.configure(context, clientKey, useStage = ...)`.
 */
internal enum class PoltioEnvironment(val baseURL: String) {
    PRODUCTION(PoltioAPIClient.PRODUCTION_BASE_URL),
    STAGE(PoltioAPIClient.STAGE_BASE_URL),
    ;

    companion object {
        /** Automatically resolves the environment from the host app's debuggable flag. */
        fun automatic(context: Context): PoltioEnvironment {
            val isDebuggable = (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
            return if (isDebuggable) STAGE else PRODUCTION
        }

        /**
         * Resolves the environment from a developer-provided override, falling back to automatic
         * detection (debuggable -> stage, release -> production) when `useStage` is `null`.
         */
        fun resolve(context: Context, useStage: Boolean?): PoltioEnvironment {
            if (useStage == null) return automatic(context)
            return if (useStage) STAGE else PRODUCTION
        }
    }
}
