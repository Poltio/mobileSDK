import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// `local.properties` is git-ignored (see .gitignore), exactly like the `sdk.dir` entry Android
// Studio already writes there — the same pattern the iOS example app uses via its git-ignored
// `*.xcscheme` (POLTIO_CLIENT_KEY environment variable). Add a line there to point the example
// app at a real client key without ever committing it:
//   POLTIO_CLIENT_KEY=poltio_pk_live_...
val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) file.inputStream().use(::load)
}

android {
    namespace = "com.poltio.exampleapp"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.poltio.exampleapp"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables {
            useSupportLibrary = true
        }

        // Precedence: CI/shell env var > local.properties > harmless placeholder (a fresh clone
        // still builds and runs with no real client key configured — it just won't resolve any
        // real widgets, matching how the SDK itself treats an unrecognized key).
        val clientKey = System.getenv("POLTIO_CLIENT_KEY")
            ?: localProperties.getProperty("POLTIO_CLIENT_KEY")
            ?: "poltio_test_pk_12345"
        buildConfigField("String", "POLTIO_CLIENT_KEY", "\"$clientKey\"")
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
        compose = true
        buildConfig = true
    }
    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.8"
    }
    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.7.0")
    implementation("androidx.activity:activity-compose:1.8.2")
    implementation(platform("androidx.compose:compose-bom:2024.02.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.navigation:navigation-compose:2.7.7")

    // Local Android SDK dependency
    implementation(project(":poltio-sdk"))
}
