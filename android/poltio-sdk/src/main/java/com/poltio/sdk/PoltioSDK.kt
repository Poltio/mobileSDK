package com.poltio.sdk

import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.SharedPreferences
import androidx.annotation.VisibleForTesting
import com.poltio.sdk.ui.PoltioOverlayManager
import java.util.UUID
import java.util.concurrent.atomic.AtomicLong

/**
 * Receives bridge events emitted by the widget WebView (e.g. "close", "complete", "leadSubmit").
 * A `fun interface`, so Kotlin callers can pass a lambda and Java callers an anonymous class or
 * lambda, with no `kotlin.jvm.functions` types in the signature.
 */
fun interface PoltioWidgetEventListener {
    /**
     * @param event The bridge event name.
     * @param data The event payload, converted to plain `Map`/`List` values, or `null` if none.
     */
    fun onWidgetEvent(event: String, data: Map<String, Any?>?)
}

/**
 * Main entry point for the Poltio Android SDK. A plain Kotlin `object` since the SDK is
 * process-wide singleton state — there is no `PoltioSDK.shared` indirection like on iOS. Every
 * public member is `@JvmStatic`, so Java callers use `PoltioSDK.configure(...)` directly rather
 * than `PoltioSDK.INSTANCE.configure(...)`.
 */
object PoltioSDK {
    private const val PREFS_NAME = "com.poltio.sdk.prefs"
    private const val SDK_ID_KEY = "sdk_id"
    private const val PUID_KEY = "puid"

    private val lock = Any()
    private var applicationContext: Context? = null
    private var _clientKey: String? = null
    private var _isInitialized: Boolean = false
    private var _sdkId: String? = null
    private var _puid: String? = null
    private var _puidLoaded: Boolean = false
    private var _apiClient: PoltioAPIClient? = null

    private val widgetCache = PoltioWidgetCache()
    private val currentViewRequestId = AtomicLong(0)
    private var activeCall: PoltioAPIClient.Call? = null

    /** The semantic version of this SDK build (e.g. "1.0.0"), also sent with every API request. */
    @JvmStatic
    val version: String get() = BuildConfig.SDK_VERSION

    /** The active log level for the SDK (default: [PoltioLogLevel.WARNING]). */
    @JvmStatic
    var logLevel: PoltioLogLevel
        get() = PoltioLogger.logLevel
        set(value) { PoltioLogger.logLevel = value }

    /** Time-to-live in seconds for widget resolution in-memory cache (default: 300 seconds / 5 minutes). */
    @JvmStatic
    var cacheTTL: Double
        get() = widgetCache.defaultTTL
        set(value) { widgetCache.defaultTTL = value }

    /** Maximum number of widget responses retained in the in-memory cache (default: 100). */
    @JvmStatic
    var cacheLimit: Int
        get() = widgetCache.countLimit
        set(value) { widgetCache.countLimit = value }

    /** Clears the in-memory widget resolution cache. */
    @JvmStatic
    fun clearCache() = widgetCache.clear()

    /** Internal access to the widget cache (for unit testing). */
    @VisibleForTesting
    internal fun widgetCacheForTesting(): PoltioWidgetCache = widgetCache

    /** The client key configured for this SDK session. */
    @JvmStatic
    val clientKey: String? get() = synchronized(lock) { _clientKey }

    /** Indicates whether the SDK has been configured. */
    @JvmStatic
    val isInitialized: Boolean get() = synchronized(lock) { _isInitialized }

    /**
     * SDK-generated unique identifier (source of truth for device tracking). Generated
     * automatically on first access and persisted in `SharedPreferences`. Requires [configure] to
     * have run at least once (to have a `Context` to persist against); before that, a fresh,
     * non-persisted id is minted on every call.
     *
     * [configure] preloads this on a background thread, so reading it afterwards is a cheap
     * in-memory lookup; the very first read before that preload finishes may touch disk.
     */
    @JvmStatic
    val sdkId: String
        get() {
            synchronized(lock) { _sdkId?.let { return it } }

            // Disk read happens outside the lock so a slow first `SharedPreferences` load never
            // blocks other threads (e.g. the main thread checking `isInitialized`) waiting on it.
            val prefs = synchronized(lock) { applicationContext }?.let(::prefsFor)
            val persisted = prefs?.getString(SDK_ID_KEY, null)

            synchronized(lock) {
                _sdkId?.let { return it }
                if (!persisted.isNullOrEmpty()) {
                    _sdkId = persisted
                    return persisted
                }

                val newId = UUID.randomUUID().toString()
                if (prefs == null) {
                    PoltioLogger.warning { "sdkId requested before configure(context, ...) — using a non-persisted id for this call." }
                } else {
                    prefs.edit().putString(SDK_ID_KEY, newId).apply()
                    _sdkId = newId
                }
                return newId
            }
        }

    /** Developer-provided optional user identifier (PUID). */
    @JvmStatic
    val puid: String?
        get() {
            synchronized(lock) { if (_puidLoaded) return _puid }

            val context = synchronized(lock) { applicationContext } ?: return null
            val persisted = prefsFor(context).getString(PUID_KEY, null)

            synchronized(lock) {
                if (_puidLoaded) return _puid
                _puid = persisted
                _puidLoaded = true
                return persisted
            }
        }

    /** The API client instance used for backend requests. */
    internal var apiClient: PoltioAPIClient
        get() = synchronized(lock) {
            _apiClient ?: PoltioAPIClient().also { _apiClient = it }
        }
        set(value) = synchronized(lock) { _apiClient = value }

    private fun prefsFor(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** Resets the SDK state. Used exclusively for unit testing to prevent state pollution. */
    @VisibleForTesting
    internal fun reset() {
        synchronized(lock) {
            activeCall?.cancel()
            activeCall = null
            currentViewRequestId.set(0)
            applicationContext?.let { prefsFor(it).edit().clear().apply() }
            applicationContext = null
            _clientKey = null
            _isInitialized = false
            _puid = null
            _puidLoaded = false
            _sdkId = null
            _apiClient = null
            widgetCache.clear()
            widgetCache.defaultTTL = 300.0
            widgetCache.countLimit = 100
        }
        PoltioLogger.logLevel = PoltioLogLevel.WARNING
    }

    // MARK: - Public Configuration API

    /**
     * Configures the Poltio SDK with your publishable client key and optional log level. Cheap
     * enough to call from `Application.onCreate()` on the main thread: it performs no disk or
     * network I/O itself — persisted identifiers are preloaded on a background thread.
     *
     * Call it from `Application.onCreate()` (recommended). If you call it later, pass the current
     * `Activity` as [context] so the SDK can attach triggers to it straight away; otherwise
     * triggers start appearing from the next Activity that resumes.
     *
     * @param context Any `Context`; only its `applicationContext` is retained, so passing an
     * `Activity` is safe and will not leak it.
     * @param clientKey Poltio client key (e.g. "poltio_test_pk...")
     * @param useStage Forces the stage (`true`) or production (`false`) API endpoint. Defaults to
     * `null`, which auto-detects the environment from the app's `android:debuggable` flag: debug
     * builds resolve to stage, release builds resolve to production. Pass an explicit value to
     * override this detection.
     * @param logLevel Verbosity level of Logcat logging (defaults to [PoltioLogLevel.WARNING]). Use
     * [PoltioLogLevel.DEBUG] during integration to inspect requests, responses, and identifiers.
     */
    @JvmStatic
    @JvmOverloads
    fun configure(
        context: Context,
        clientKey: String,
        useStage: Boolean? = null,
        logLevel: PoltioLogLevel = PoltioLogLevel.WARNING,
    ) {
        val trimmedKey = clientKey.trim()
        PoltioLogger.logLevel = logLevel

        if (trimmedKey.isEmpty()) {
            PoltioLogger.error { "Client key cannot be empty." }
            return
        }

        val appContext = context.applicationContext
        val environment = PoltioEnvironment.resolve(appContext, useStage)

        synchronized(lock) {
            applicationContext = appContext
            _clientKey = trimmedKey
            _isInitialized = true
            _apiClient = PoltioAPIClient(baseURL = environment.baseURL)
        }

        // Warm the persisted identifiers off the caller's thread, so neither configure() nor the
        // first track() call ever performs the initial SharedPreferences disk read on main.
        PoltioExecutors.serial.execute {
            val id = sdkId
            puid
            PoltioLogger.debug { "SDK ID: $id" }
        }

        (appContext as? Application)?.let { PoltioOverlayManager.attach(it) }
            ?: PoltioLogger.warning { "configure() was not given an Application context — floating triggers cannot be attached to host activities." }
        (context as? Activity)?.let { PoltioOverlayManager.seedCurrentActivity(it) }

        if (environment == PoltioEnvironment.STAGE) {
            PoltioLogger.info {
                "Using STAGE API endpoint (${environment.baseURL}). Pass useStage = false to configure() once you're ready to point at production."
            }
        }

        PoltioLogger.info { "Configured successfully (SDK version $version)." }
    }

    // MARK: - Public User Identification API

    /**
     * Identifies the user with an optional developer-provided user identifier (PUID). Pass `null`
     * or a blank string to clear it.
     */
    @JvmStatic
    fun identify(puid: String?) {
        val trimmedPuid = puid?.trim()?.takeIf { it.isNotEmpty() }

        val context = synchronized(lock) {
            _puid = trimmedPuid
            _puidLoaded = true
            applicationContext
        }

        // Persist off the caller's thread; the in-memory value above is already authoritative.
        context?.let {
            PoltioExecutors.serial.execute {
                val editor = prefsFor(it).edit()
                if (trimmedPuid != null) editor.putString(PUID_KEY, trimmedPuid) else editor.remove(PUID_KEY)
                editor.apply()
            }
        }

        if (trimmedPuid != null) {
            PoltioLogger.debug { "Identified user with PUID: '$trimmedPuid'." }
        } else {
            PoltioLogger.debug { "Cleared PUID." }
        }
    }

    // MARK: - Public Event Tracking API

    /**
     * Tracks an in-app event with optional parameters.
     *
     * Screen views (`"view"`, `"viewContent"`, `"view_content"`, case-insensitive) are the events
     * that drive the SDK: each one resolves the widget configured for the screen's `url` (or
     * `screen`/`page`) param via `/sdk/mobile/v1/widget` and shows or hides its floating trigger.
     * Other event names are currently accepted and logged locally only — they are **not** sent to
     * the Poltio API. To report a purchase for conversion attribution, use [recordPurchase].
     *
     * Returns immediately; all work happens on a background thread, in call order.
     *
     * @param event The event name (e.g. "view").
     * @param params Map of event properties (e.g. `mapOf("url" to "myapp://products/123")`).
     */
    @JvmStatic
    @JvmOverloads
    fun track(event: String, params: Map<String, Any?>? = null) {
        val trimmedEvent = event.trim()
        if (trimmedEvent.isEmpty()) {
            PoltioLogger.error { "Event name cannot be empty." }
            return
        }

        val key = clientKey
        if (!isInitialized || key == null) {
            PoltioLogger.warning { "track() called before configuration. Call PoltioSDK.configure(context, clientKey) first." }
            return
        }

        // Snapshot the caller's map before hopping threads, so later mutation by the host can't race us.
        val paramsSnapshot = params?.let { LinkedHashMap(it) }

        PoltioExecutors.serial.execute {
            val currentSdkId = sdkId
            PoltioLogger.debug {
                val enriched = LinkedHashMap<String, Any?>(paramsSnapshot ?: emptyMap())
                enriched["sdk_id"] = currentSdkId
                puid?.let { enriched["puid"] = it }
                "Event tracked: '$trimmedEvent', params: $enriched"
            }

            if (isViewEvent(trimmedEvent)) {
                handleViewEvent(key, currentSdkId, paramsSnapshot)
            }
        }
    }

    private fun handleViewEvent(clientKey: String, deviceId: String, params: Map<String, Any?>?) {
        val rawUrl = (params?.get("url") ?: params?.get("screen") ?: params?.get("page"))?.toString() ?: ""
        val targetURL = sanitizeOrFormatURL(rawUrl)
        val activePuid = puid

        val cached = widgetCache.get(targetURL)
        if (cached != null) {
            synchronized(lock) {
                activeCall?.cancel()
                activeCall = null
                currentViewRequestId.incrementAndGet()
            }
            when (cached) {
                is CachedWidgetResult.Widget -> {
                    PoltioLogger.debug { "Using cached widget response for '$targetURL' (public_id: ${cached.response.publicId})." }
                    PoltioOverlayManager.showTrigger(cached.response, activePuid)
                }
                CachedWidgetResult.NoWidget -> {
                    PoltioLogger.debug { "Using cached negative widget resolution for '$targetURL' (no widget)." }
                    PoltioOverlayManager.hideTrigger()
                }
            }
            return
        }

        // The new request id is taken from the same locked increment, so two concurrent view events
        // can never end up sharing an id.
        val thisRequestId = synchronized(lock) {
            activeCall?.cancel()
            activeCall = null
            currentViewRequestId.incrementAndGet()
        }

        val call = apiClient.resolveMobileWidget(clientKey, deviceId, targetURL) { result ->
            val isLatest = currentViewRequestId.get() == thisRequestId
            if (!isLatest) {
                PoltioLogger.debug { "Ignoring outdated widget resolution result for '$targetURL' (newer screen was already requested)." }
                return@resolveMobileWidget
            }

            result.onSuccess { widget ->
                widgetCache.set(CachedWidgetResult.Widget(widget), targetURL)
                PoltioOverlayManager.showTrigger(widget, activePuid)
            }.onFailure { error ->
                PoltioOverlayManager.hideTrigger()
                if (error is PoltioNoWidgetException) {
                    widgetCache.set(CachedWidgetResult.NoWidget, targetURL)
                }
                PoltioLogger.warning { "Widget resolution skipped/failed for '$targetURL': ${error.message}" }
            }
        }

        synchronized(lock) {
            if (currentViewRequestId.get() == thisRequestId) {
                activeCall = call
            } else {
                // A newer screen already superseded this request before it could be stored;
                // cancel it explicitly instead of letting it run to completion unused.
                call.cancel()
            }
        }
    }

    // MARK: - Public Conversion Tracking API

    /**
     * Records a completed purchase for conversion attribution ("recordMobilePurchase"). Books
     * the purchase against the Poltio session already recorded for this device (via
     * `track(event = "view", ...)`), crediting revenue back to the recommendation that led to
     * it. Fire-and-forget: performs the request on a background thread, suppresses all errors,
     * and never blocks or throws — safe to call from a checkout-success handler.
     *
     * @param orderId Unique order/transaction identifier. Used by the backend as a deduplication
     * key — retrying with the same `orderId` records the purchase once. Reusing an `orderId`
     * across distinct purchases silently drops revenue, so always pass a fresh one per order.
     * @param value Total monetary value of the purchase. Must be greater than zero.
     * @param url The checkout/success screen URL or deep link (e.g. "myapp://checkout/complete").
     * Must include a scheme and host.
     * @param currency Optional ISO 4217 currency code (e.g. "USD").
     * @param items Optional line items included in the purchase.
     * @param eventTimeSeconds Optional unix timestamp (seconds) the purchase actually occurred.
     */
    @JvmStatic
    @JvmOverloads
    fun recordPurchase(
        orderId: String,
        value: Double,
        url: String,
        currency: String? = null,
        items: List<PoltioPurchaseItem> = emptyList(),
        eventTimeSeconds: Long? = null,
    ) {
        val trimmedOrderId = orderId.trim()
        if (trimmedOrderId.isEmpty()) {
            PoltioLogger.error { "recordPurchase requires a non-empty orderId." }
            return
        }
        if (value <= 0 || !value.isFinite()) {
            PoltioLogger.error { "recordPurchase requires a positive, finite value (received $value)." }
            return
        }
        val trimmedURL = url.trim()
        if (!isValidConversionURL(trimmedURL)) {
            PoltioLogger.error { "recordPurchase requires a valid url with a scheme and host (e.g. 'myapp://checkout/complete'); received '$url'." }
            return
        }

        val key = clientKey
        if (!isInitialized || key == null) {
            PoltioLogger.warning { "recordPurchase() called before configuration. Call PoltioSDK.configure(context, clientKey) first." }
            return
        }

        val validItems = items.filter { item ->
            val hasValidId = item.id.trim().isNotEmpty()
            val hasValidValue = item.value == null || (item.value.isFinite() && item.value >= 0)
            val hasValidQuantity = item.quantity == null || item.quantity > 0
            val isValid = hasValidId && hasValidValue && hasValidQuantity
            if (!isValid) {
                PoltioLogger.warning { "recordPurchase ignoring invalid item '${item.id}' for order '$trimmedOrderId'." }
            }
            isValid
        }

        PoltioExecutors.serial.execute {
            apiClient.recordPurchase(
                clientKey = key,
                deviceId = sdkId,
                url = trimmedURL,
                orderId = trimmedOrderId,
                value = value,
                currency = currency,
                eventTimeSeconds = eventTimeSeconds,
                items = validItems,
            )
        }
    }

    // MARK: - Public Trigger Control

    /**
     * Hides the floating trigger currently on screen, if any (e.g. while the host app shows its own
     * full-screen flow). The next `track("view", ...)` resolves and shows triggers as usual.
     */
    @JvmStatic
    fun hideTrigger() = PoltioOverlayManager.hideTrigger()

    // MARK: - Internal Impression Reporting

    /**
     * Reports a widget impression ("cta-view") to the backend. Called exactly once by
     * [PoltioOverlayManager] each time a floating trigger is actually displayed on screen
     * (including when the widget came from cache) — never on resolution alone, and never for a
     * trigger that's suppressed (`floating-hide-button`, within its close-remember window, or an
     * unsupported type). Fire-and-forget and safe to call before configuration; never blocks or throws.
     */
    internal fun reportCtaView(widget: PoltioWidgetResponse) {
        val key = clientKey
        if (!isInitialized || key == null) {
            PoltioLogger.debug { "reportCtaView skipped — SDK not configured." }
            return
        }
        PoltioExecutors.serial.execute {
            apiClient.reportCtaView(key, sdkId, widget.publicId, widget.widgetId)
        }
    }

    // MARK: - Public Widget Event Bridge

    /**
     * Optional listener invoked when the widget WebView emits a bridge event (e.g. "close",
     * "complete", "leadSubmit"). Delivered on the main thread. Set this once, e.g. alongside
     * `configure()`:
     *
     * ```kotlin
     * PoltioSDK.onWidgetEvent = PoltioWidgetEventListener { event, data -> /* ... */ }
     * ```
     */
    @JvmStatic
    @Volatile
    var onWidgetEvent: PoltioWidgetEventListener? = null

    // MARK: - Internal Helpers

    /** Checks whether an event name corresponds to a view event. */
    internal fun isViewEvent(eventName: String): Boolean {
        val lower = eventName.lowercase()
        return lower == "view" || lower == "viewcontent" || lower == "view_content"
    }
}
