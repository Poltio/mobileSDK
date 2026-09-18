package com.poltio.sdk

import android.app.Application
import android.content.Context
import android.content.SharedPreferences
import androidx.annotation.VisibleForTesting
import com.poltio.sdk.ui.PoltioOverlayManager
import java.util.UUID
import java.util.concurrent.atomic.AtomicLong

/**
 * Main entry point for the Poltio Android SDK. A plain Kotlin `object` since the SDK is
 * process-wide singleton state — there is no `PoltioSDK.shared` indirection like on iOS.
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

    /** The active log level for the SDK. */
    var logLevel: PoltioLogLevel
        get() = PoltioLogger.logLevel
        set(value) { PoltioLogger.logLevel = value }

    /** Time-to-live in seconds for widget resolution in-memory cache (default: 300 seconds / 5 minutes). */
    var cacheTTL: Double
        get() = widgetCache.defaultTTL
        set(value) { widgetCache.defaultTTL = value }

    /** Maximum number of widget responses retained in the in-memory cache (default: 100). */
    var cacheLimit: Int
        get() = widgetCache.countLimit
        set(value) { widgetCache.countLimit = value }

    /** Clears the in-memory widget resolution cache. */
    fun clearCache() = widgetCache.clear()

    /** Internal access to the widget cache (for unit testing). */
    @VisibleForTesting
    internal fun widgetCacheForTesting(): PoltioWidgetCache = widgetCache

    /** The client key configured for this SDK session. */
    val clientKey: String? get() = synchronized(lock) { _clientKey }

    /** Indicates whether the SDK has been configured. */
    val isInitialized: Boolean get() = synchronized(lock) { _isInitialized }

    /**
     * SDK-generated unique identifier (source of truth for device tracking). Generated
     * automatically on first access and persisted in `SharedPreferences`. Requires [configure] to
     * have run at least once (to have a `Context` to persist against); before that, a fresh,
     * non-persisted id is minted on every call.
     */
    val sdkId: String
        get() {
            synchronized(lock) {
                _sdkId?.let { return it }

                val prefs = applicationContext?.let(::prefsFor)
                if (prefs != null) {
                    val persisted = prefs.getString(SDK_ID_KEY, null)
                    if (!persisted.isNullOrEmpty()) {
                        _sdkId = persisted
                        return persisted
                    }
                }

                val newId = UUID.randomUUID().toString()
                prefs?.edit()?.putString(SDK_ID_KEY, newId)?.apply()
                if (prefs == null) {
                    PoltioLogger.warning { "sdkId requested before configure(context, ...) — using a non-persisted id for this call." }
                } else {
                    _sdkId = newId
                }
                return newId
            }
        }

    /** Developer-provided optional user identifier (PUID). */
    val puid: String?
        get() {
            synchronized(lock) {
                if (_puidLoaded) return _puid
                val persisted = applicationContext?.let(::prefsFor)?.getString(PUID_KEY, null)
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
        PoltioLogger.logLevel = PoltioLogLevel.INFO
    }

    // MARK: - Public Configuration API

    /**
     * Configures the Poltio SDK with your publishable client key and optional log level.
     *
     * @param context Any `Context`; only its `applicationContext` is retained, so passing an
     * `Activity` is safe and will not leak it.
     * @param clientKey Poltio client key (e.g. "poltio_test_pk...")
     * @param useStage Forces the stage (`true`) or production (`false`) API endpoint. Defaults to
     * `null`, which auto-detects the environment from the app's `android:debuggable` flag: debug
     * builds resolve to stage, release builds resolve to production. Pass an explicit value to
     * override this detection.
     * @param logLevel Verbosity level of console logging (defaults to `.INFO`).
     */
    fun configure(
        context: Context,
        clientKey: String,
        useStage: Boolean? = null,
        logLevel: PoltioLogLevel = PoltioLogLevel.INFO,
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

        (appContext as? Application)?.let { PoltioOverlayManager.attach(it) }
            ?: PoltioLogger.warning { "configure() was not given an Application context — floating triggers cannot be attached to host activities." }

        if (environment == PoltioEnvironment.STAGE) {
            PoltioLogger.info {
                "Using STAGE API endpoint (${environment.baseURL}). Pass useStage = false to configure() once you're ready to point at production."
            }
        }

        PoltioLogger.info { "Configured successfully (SDK ID: $sdkId)." }
    }

    // MARK: - Public User Identification API

    /** Identifies the user with an optional developer-provided user identifier (PUID). */
    fun identify(puid: String?) {
        val trimmedPuid = puid?.trim()

        synchronized(lock) {
            val prefs = applicationContext?.let(::prefsFor)
            if (!trimmedPuid.isNullOrEmpty()) {
                _puid = trimmedPuid
                prefs?.edit()?.putString(PUID_KEY, trimmedPuid)?.apply()
                PoltioLogger.info { "Identified user with PUID: '$trimmedPuid'." }
            } else {
                _puid = null
                prefs?.edit()?.remove(PUID_KEY)?.apply()
                PoltioLogger.info { "Cleared PUID." }
            }
            _puidLoaded = true
        }
    }

    // MARK: - Public Event Tracking API

    /**
     * Tracks an in-app event with optional parameters. Automatically attaches `sdk_id` and `puid`
     * (when available) to the event parameters. For `view` events, triggers backend widget
     * resolution via `/sdk/mobile/v1/widget`.
     *
     * @param event The event name (e.g. "view", "TrackConversion")
     * @param params Map of event properties (e.g. `mapOf("url" to "https://www.poltio.com/pdp")`)
     */
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

        val enrichedParams = LinkedHashMap<String, Any?>(params ?: emptyMap())
        val currentSdkId = sdkId
        enrichedParams["sdk_id"] = currentSdkId
        puid?.let { enrichedParams["puid"] = it }

        PoltioLogger.info { "Event tracked: '$trimmedEvent', params: $enrichedParams" }

        if (isViewEvent(trimmedEvent)) {
            handleViewEvent(key, currentSdkId, params)
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

        synchronized(lock) {
            activeCall?.cancel()
            activeCall = null
            currentViewRequestId.incrementAndGet()
        }
        val thisRequestId = currentViewRequestId.get()

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
        apiClient.reportCtaView(key, sdkId, widget.publicId, widget.widgetId)
    }

    // MARK: - Public Widget Event Bridge

    /**
     * Optional callback invoked when the widget WebView emits a bridge event (e.g. "close",
     * "complete", "leadSubmit"). Delivered on the main thread. Set this once, e.g. alongside
     * `configure()`.
     */
    var onWidgetEvent: ((event: String, data: Map<String, Any?>?) -> Unit)? = null

    // MARK: - Internal Helpers

    /** Checks whether an event name corresponds to a view event. */
    internal fun isViewEvent(eventName: String): Boolean {
        val lower = eventName.lowercase()
        return lower == "view" || lower == "viewcontent" || lower == "view_content"
    }
}
