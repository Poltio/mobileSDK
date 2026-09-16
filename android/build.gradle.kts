plugins {
    id("com.android.library") version "8.2.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false
    // Pinned to 0.34.0: newer releases raise the minimum AGP to 8.13.0+ / Gradle to 9.x,
    // which this project's toolchain (AGP 8.2.2, Gradle 8.5) doesn't meet yet.
    id("com.vanniktech.maven.publish") version "0.34.0" apply false
}
