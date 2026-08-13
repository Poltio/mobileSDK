# Poltio Android SDK & Sample App Setup Guide

This guide provides step-by-step instructions for setting up your development environment, creating an Android Virtual Device (AVD / Emulator), and building the Poltio Android SDK and sample app.

---

## 🛠 1. Prerequisites & Environment Setup

Run the automated environment check from the root of the project:

```bash
make check
```

### Required Software
1. **macOS** (Recommended) or Linux/Windows.
2. **Java JDK 17+**:
   ```bash
   brew install openjdk@17
   ```
3. **Android Studio**:
   ```bash
   brew install --cask android-studio
   ```

---

## 📱 2. Setting Up an Android Virtual Device (AVD Emulator)

Follow these steps once on a fresh Android Studio installation:

### Step 1: Open Device Manager
1. Launch **Android Studio**.
2. On the top-right toolbar or Welcome screen, click **Device Manager** (or go to `Tools` ➔ `Device Manager`).
3. Click **Create Virtual Device** (or the `+` button).

### Step 2: Select Hardware Profile
1. Select **Phone** under Category.
2. Choose **Pixel 8** (or **Pixel 7**) and click **Next**.

### Step 3: Download System Image
1. Select **API Level 34** (`UpsideDownCake` - Android 14.0, ARM64).
2. If a **Download ⬇️** link appears next to the release name, click it to download the system image (~1.4 GB).
3. Once downloaded, select **API 34** and click **Next**.

### Step 4: Finish Setup
1. Keep default device settings and click **Finish**.
2. Click the **Play ▶️** button next to your new device in Device Manager to verify it boots up.

---

## 🚀 3. Makefile Developer Commands

All builds, tests, and example apps are run via the universal root `Makefile`:

| Target | Command | Description |
| :--- | :--- | :--- |
| **Check Env** | `make check` | Validates JDK, Android Studio, and ADB availability. |
| **Build SDK** | `make build-android` | Compiles the Android Kotlin SDK library (`:poltio-sdk`). |
| **Test SDK** | `make test-android` | Runs Android Kotlin unit test suites. |
| **Build Example** | `make build-example-android` | Compiles the `TechStore` sample APK (`app-debug.apk`). |
| **Open Studio** | `make open-example-android` | Opens `example/android` in Android Studio. |
| **Run Example** | `make run-example-android` | Auto-detects AVD, boots emulator, installs APK, and launches app. |

---

## 📁 4. Project Structure (`/android` & `/example/android`)

```
poltio-mobile-sdk/
├── android/            # Poltio Core Android Library (Kotlin)
│   ├── poltio-sdk/     # SDK Module (AAR distribution)
│   └── build.gradle.kts
└── example/android/    # Sample E-Commerce App (TechStore - Jetpack Compose)
    ├── app/            # App Module
    ├── gradlew         # Executable Gradle Wrapper
    └── local.properties# Local SDK path configuration
```
