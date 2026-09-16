pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "PoltioExampleApp"
include(":app")

// The Poltio Android SDK lives in its own top-level Gradle project (`/android`), not nested
// under `example/android` — include it here by explicit path so the example app can depend on
// the real library module instead of a placeholder.
include(":poltio-sdk")
project(":poltio-sdk").projectDir = File(rootDir, "../../android/poltio-sdk")
