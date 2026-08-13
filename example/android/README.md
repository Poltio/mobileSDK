# Poltio Android Example App (`TechStore`)

An e-commerce sample application built with **Kotlin** and **Jetpack Compose** demonstrating integration with the **Poltio Mobile SDK**.

> 📖 **Full Setup Guide**: For complete JDK, Android Studio, and AVD Emulator setup instructions, see [**docs/ANDROID.md**](../../docs/ANDROID.md).

---

## 🚀 Quick Start

Run from the root directory of the monorepo:

```bash
# Check if your system tools and Android SDK are ready
make check

# Build debug APK
make build-example-android

# Open in Android Studio
make open-example-android

# Build, install, and launch on a connected emulator / device
make run-example-android
```

---

## 📱 Setting Up an Android Virtual Device (AVD / Emulator)

When opening Android Studio for the first time on a new Mac, follow these steps to create an emulator:

### Step 1: Open Virtual Device Manager
1. Open **Android Studio**.
2. On the top right toolbar (or Welcome screen), click **Device Manager** (or navigate to `Tools` -> `Device Manager`).
3. Click **Create Virtual Device** (or `+`).

### Step 2: Choose Hardware Profile
1. Select **Phone** under Category.
2. Select **Pixel 8** (or **Pixel 7**) and click **Next**.

### Step 3: Download System Image
1. Select the **API Level 34** system image (e.g., `UpsideDownCake` - Android 14.0, ARM 64 v8a).
2. If the **Download** link appears next to the release name, click it and accept the license agreement.
3. Once downloaded, select **API 34** and click **Next**.

### Step 4: Finish & Launch
1. Name your virtual device (e.g., `Pixel_8_API_34`).
2. Click **Finish**.
3. In the Device Manager list, click the **Play ▶️** button next to your new device to boot the simulator.

---

## 🛠 Features Demonstrated
- **Interactive Landing Page**: Screen tracking for Poltio TAG targeting.
- **Category PLPs**: Category-specific Poltio Quiz overlay banners (Phones, TVs, Laptops).
- **Product PDPs**: Spec sheets with dynamic Poltio Widget trigger buttons.
- **SDK Activity Inspector**: Live event stream for SDK events and screen views.
