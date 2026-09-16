plugins {
    id("com.android.application") version "8.2.2" apply false
    // Needed because :poltio-sdk (included from ../../android/poltio-sdk, see settings.gradle.kts)
    // is a com.android.library module and resolves its plugin versions from this build's root.
    id("com.android.library") version "8.2.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false
}
