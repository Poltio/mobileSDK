plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("com.vanniktech.maven.publish")
}

// Pinned to 0.34.0 — see android/build.gradle.kts for the AGP/Gradle compatibility note.

// The real version is injected at publish time via -PlibVersion=<release tag>
// (see .github/workflows/publish-maven.yaml). This default only backs local
// assembleRelease/lintDebug runs, which don't need a real Maven Central version.
version = (findProperty("libVersion") as String?) ?: "0.0.1-SNAPSHOT"

android {
    namespace = "com.poltio.sdk"
    compileSdk = 34

    defaultConfig {
        minSdk = 24

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        consumerProguardFiles("consumer-rules.pro")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        buildConfig = true
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            // Tests that don't opt into Robolectric still touch stubbed android.jar methods
            // (e.g. android.util.Log via PoltioLogger) — return defaults instead of throwing.
            isReturnDefaultValues = true
        }
    }
}

dependencies {
    // Only the foundational AndroidX artifact (window insets / view compat helpers) —
    // effectively ubiquitous in host apps, kept to a single lightweight dependency by design.
    implementation("androidx.core:core-ktx:1.12.0")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.11.1")
    testImplementation("androidx.test:core:1.5.0")
}

mavenPublishing {
    publishToMavenCentral()
    signAllPublications()

    coordinates("com.poltio", "poltio-sdk", version.toString())

    pom {
        name.set("Poltio SDK")
        description.set("Poltio Mobile SDK for Android")
        inceptionYear.set("2025")
        url.set("https://github.com/Poltio/mobileSDK")

        licenses {
            license {
                name.set("MIT License")
                url.set("https://opensource.org/license/mit")
                distribution.set("repo")
            }
        }

        developers {
            developer {
                id.set("poltio")
                name.set("Poltio")
                email.set("dev@poltio.com")
            }
        }

        scm {
            url.set("https://github.com/Poltio/mobileSDK")
            connection.set("scm:git:git://github.com/Poltio/mobileSDK.git")
            developerConnection.set("scm:git:ssh://git@github.com/Poltio/mobileSDK.git")
        }
    }
}
