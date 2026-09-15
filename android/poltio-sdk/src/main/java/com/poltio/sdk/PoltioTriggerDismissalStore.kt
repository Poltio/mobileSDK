package com.poltio.sdk

import android.content.Context
import org.json.JSONObject

/**
 * Persists explicit user dismissals of the pill/box "remember for N hours" close button
 * (`pillCloseRememberDuration` / `boxCloseRememberDuration`), so a widget the user explicitly
 * closed doesn't reappear until the remember window elapses. Mirrors the `SharedPreferences`-backed
 * persistence pattern already used for `sdkId`/`puid` in [PoltioSDK].
 */
internal object PoltioTriggerDismissalStore {
    private const val PREFS_NAME = "com.poltio.sdk.prefs"
    private const val STORAGE_KEY = "trigger_dismissals"

    /** Returns whether [publicId] is currently within an active "remember" dismissal window. */
    fun isDismissed(context: Context, publicId: String, nowMs: Long = System.currentTimeMillis()): Boolean {
        val dismissedUntil = load(context)[publicId] ?: return false
        return nowMs < dismissedUntil
    }

    /** Records that [publicId] was explicitly closed; it will be suppressed for [hours] from now. */
    fun recordDismissal(context: Context, publicId: String, hours: Double, nowMs: Long = System.currentTimeMillis()) {
        if (hours <= 0) return
        val stored = load(context).toMutableMap()
        stored[publicId] = nowMs + (hours * 3_600_000.0).toLong()
        save(context, stored)
    }

    /** Clears all persisted dismissals. Used exclusively for unit testing. */
    fun reset(context: Context) {
        prefs(context).edit().remove(STORAGE_KEY).apply()
    }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun load(context: Context): Map<String, Long> {
        val json = prefs(context).getString(STORAGE_KEY, null) ?: return emptyMap()
        return try {
            val obj = JSONObject(json)
            val result = LinkedHashMap<String, Long>()
            obj.keys().forEach { key -> result[key] = obj.getLong(key) }
            result
        } catch (error: Exception) {
            emptyMap()
        }
    }

    private fun save(context: Context, map: Map<String, Long>) {
        val obj = JSONObject()
        map.forEach { (key, value) -> obj.put(key, value) }
        prefs(context).edit().putString(STORAGE_KEY, obj.toString()).apply()
    }
}
