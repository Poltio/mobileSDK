package com.poltio.exampleapp

import android.app.Application
import com.poltio.sdk.PoltioSDK

class TechStoreApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Initialize Poltio TAG SDK
        PoltioSDK.configure(this, clientKey = BuildConfig.POLTIO_CLIENT_KEY)
    }
}
