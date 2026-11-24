// The sample reaches the SDK's internal classes; fine for this debug-only demo and nothing else.
@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

package com.poltio.exampleapp.services

import com.poltio.sdk.PoltioExecutors
import com.poltio.sdk.PoltioOverlayOptions
import com.poltio.sdk.PoltioSDK
import com.poltio.sdk.PoltioWidgetResponse
import com.poltio.sdk.ui.PoltioOverlayManager
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger

/**
 * A hand-made stack ("Multi") trigger, until stage has a stack widget saved on a screen URL. Its
 * cards open the contents of the demo screens' own stage widgets, so each one opens for real.
 */
object SampleStackWidget {
    private val demoUrls = listOf("poltiodemo://home", "poltiodemo://plp/phones", "poltiodemo://plp/tvs")
    private val looks = listOf(
        listOf("Shopping Assistant", "Let's find what fits you", "#f2a38f", "#b8324a", "60"),
        listOf("Phone Finder", "Pick your next phone", "#8fb8f2", "#2a4fa0", "60"),
        listOf("TV Finder", "The right screen for your room", "#9be0c0", "#1f7a55", "60"),
    )

    fun show(format: String, status: (String) -> Unit) {
        val key = PoltioSDK.clientKey ?: return status("Configure the SDK first.")
        val resolved = ConcurrentHashMap<Int, PoltioWidgetResponse>()
        val pending = AtomicInteger(demoUrls.size)
        demoUrls.forEachIndexed { index, url ->
            PoltioSDK.apiClient.resolveMobileWidget(key, PoltioSDK.sdkId, url) { result ->
                result.getOrNull()?.let { resolved[index] = it }
                if (pending.decrementAndGet() == 0) {
                    PoltioExecutors.runOnMain { showResolved(resolved.toSortedMap().values.toList(), format, status) }
                }
            }
        }
    }

    private fun showResolved(widgets: List<PoltioWidgetResponse>, format: String, status: (String) -> Unit) {
        if (widgets.size < 2) {
            return status("Sample stack needs at least two demo screens with a stage widget; found ${widgets.size}.")
        }
        val cards = JSONArray()
        widgets.zip(looks).forEach { (widget, look) ->
            val (title, desc, bg, buttonBg, opacity) = look
            cards.put(
                JSONObject()
                    .put("content", widget.publicId)
                    .put("title", title)
                    .put("desc", desc)
                    .put("button", "Start")
                    .put("bg", bg)
                    .put("button_bg", buttonBg)
                    .put("opacity", opacity)
                    .put("image", widget.overlayOptions.floatingImg ?: ""),
            )
        }
        val options = PoltioOverlayOptions.fromJson(
            JSONObject()
                .put("trigger-type", "stack")
                .put("floating-initial-position", "active")
                .put("floating-position", "bottom-right")
                .put("floating-stack-format", format)
                .put("floating-stack-cards", cards.toString()),
        )
        PoltioOverlayManager.showTrigger(PoltioWidgetResponse(widgets[0].publicId, options, widgetId = widgets[0].widgetId), PoltioSDK.puid)
        status("Showing the sample $format stack with ${cards.length()} cards.")
    }
}
