package com.poltio.sdk

import android.os.Handler
import android.os.Looper
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.ThreadFactory
import java.util.concurrent.atomic.AtomicInteger

/**
 * Shared background execution primitives for the SDK. A single small cached thread pool backs
 * every network/image request instead of spinning up ad-hoc threads or executors per call site,
 * keeping the SDK's footprint predictable in the host app.
 */
internal object PoltioExecutors {
    private val threadCounter = AtomicInteger(0)

    val io = Executors.newCachedThreadPool(
        ThreadFactory { runnable ->
            Thread(runnable, "PoltioSDK-IO-${threadCounter.incrementAndGet()}").apply {
                isDaemon = true
            }
        },
    )

    /**
     * Single-threaded queue for SDK state work that must not run on the caller's (usually main)
     * thread — `SharedPreferences` reads/writes and the per-screen widget-resolution bookkeeping.
     * Serial, so `track()` calls are processed in the order they were made: a fast A→B navigation
     * always resolves B last, exactly as if it had run inline.
     */
    val serial: ExecutorService = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "PoltioSDK-State").apply { isDaemon = true }
    }

    val main: Handler by lazy { Handler(Looper.getMainLooper()) }

    /** Posts [block] to the main thread, running it immediately if already on it. */
    fun runOnMain(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            block()
        } else {
            main.post(block)
        }
    }
}
