# Poltio iOS SDK & Sample App Setup Guide

This guide provides step-by-step instructions for setting up your development environment and running the Poltio iOS SDK and sample app.

---

## 🛠 1. Prerequisites & Environment Setup

Run the automated environment check from the root of the project:

```bash
make check
```

### Required Software
1. **macOS** 13.0+
2. **Xcode 15+** (Includes Swift 5.9+, iOS 17 SDK, and iOS Simulator).
3. **CocoaPods** (Optional, for Podspec release verification):
   ```bash
   sudo gem install cocoapods
   ```

---

## 🚀 2. Makefile Developer Commands

All builds, tests, and example apps are run via the universal root `Makefile`:

| Target | Command | Description |
| :--- | :--- | :--- |
| **Check Env** | `make check` | Validates Xcode, Swift compiler, and iOS Simulator. |
| **Build SDK** | `make build-ios` | Compiles the Swift package SDK (`swift build`). |
| **Test SDK** | `make test-ios` | Runs the full unit test suite on an iOS Simulator (`xcodebuild test`); `make test-ios-macos` runs the host-only subset (`swift test`). |
| **Lint Podspec** | `make lint-pod` | Validates CocoaPods podspec (`pod lib lint`). |
| **Publish Pod** | `make publish-cocoapods` | Pushes podspec to CocoaPods Trunk (`pod trunk push`). |
| **Build Example** | `make build-example-ios` | Compiles `ExampleApp.app` bundle via `xcodebuild`. |
| **Open Xcode** | `make open-example-ios` | Opens `example/ios/ExampleApp.xcodeproj` in Xcode. |
| **Run Example** | `make run-example-ios` | Boots iOS Simulator (`iPhone 17 Pro`), installs `.app`, and launches app. |

---

## 📁 3. Project Structure & Distribution

```
poltio-mobile-sdk/
├── LICENSE             # MIT License
├── Package.swift       # Swift Package Manager Manifest (root entrypoint)
├── PoltioSDK.podspec   # CocoaPods spec (root, so `pod lib lint` resolves source paths)
├── ios/                # Poltio Core iOS Library (Swift)
│   └── Sources/PoltioSDK/
│       ├── Resources/PrivacyInfo.xcprivacy
│       └── ...
└── example/ios/        # Sample E-Commerce App (TechStore - SwiftUI)
    └── ExampleApp.xcodeproj/
```

---

## 📦 4. Integrating Poltio iOS SDK

### Option A: Swift Package Manager (Recommended)

#### In an Xcode Application Project:
1. Open your project in Xcode.
2. Select **File** > **Add Package Dependencies...** (or select your target project in the navigator > **Package Dependencies** tab > **+**).
3. Paste the repository URL:
   ```text
   https://github.com/Poltio/mobileSDK.git
   ```
4. Set the **Dependency Rule**:
   - For release versions: Select **Up to Next Major Version** with `1.0.0`.
   - For testing/pre-release: Select **Branch** and specify `main`.
5. Click **Add Package** and select **PoltioSDK** as a linked framework for your target.

#### In a `Package.swift` Manifest:
```swift
dependencies: [
    .package(url: "https://github.com/Poltio/mobileSDK.git", from: "1.0.0")
],
targets: [
    .target(
        name: "YourAppTarget",
        dependencies: [
            .product(name: "PoltioSDK", package: "mobileSDK")
        ]
    )
]
```

### Option B: CocoaPods

Add `PoltioSDK` to your `Podfile`:

```ruby
target 'YourAppTarget' do
  use_frameworks!
  pod 'PoltioSDK', '~> 1.0.0'
end
```

Then install the dependencies:
```bash
pod install
```

---

## 🚀 5. Publishing to CocoaPods Trunk

### One-Time Setup:
```bash
# Register account with CocoaPods Trunk
pod trunk register dev@poltio.com "Poltio" --description="Release Machine"
# Check email to verify account, then confirm session
pod trunk me
```

### Validation & Release:
```bash
# 1. Validate the podspec locally
make lint-pod

# 2. Tag release in git and push
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0

# 3. Publish to CocoaPods Trunk (or triggered automatically via GitHub Actions)
make publish-cocoapods
```

---

## 💡 6. Basic SDK Usage

```swift
import PoltioSDK

// 1. Configure in AppDelegate / App initialization
PoltioSDK.configure(clientKey: "YOUR_CLIENT_KEY") // logLevel defaults to .warning; pass .debug while integrating

// By default the SDK auto-detects the API environment from your app's build configuration:
// Debug builds use https://sdk-stage.poltio.com, Release builds (incl. TestFlight/App Store)
// use https://sdk.poltio.com. Pass `useStage` to override this detection explicitly, e.g. to
// test production from a Debug build, or stage from a Release build:
// PoltioSDK.configure(clientKey: "YOUR_CLIENT_KEY", useStage: false)

// 2. Identify user (optional)
PoltioSDK.identify(puid: "user_12345")

// 3. Track screen / view events (cached in-memory for 5 minutes)
PoltioSDK.track(event: "view", params: ["url": "https://app.poltio.com/home"])

// 4. Cache management (optional)
// PoltioSDK.cacheTTL = 300.0  // Default: 5 minutes (300 seconds)
// PoltioSDK.cacheLimit = 100   // Default: 100 entries max
// PoltioSDK.clearCache()       // Clear cache manually
```

---

## Privacy Manifest

The SDK ships a `PrivacyInfo.xcprivacy` that Xcode merges into your app's privacy report:

| Declaration | Value | Why |
| :--- | :--- | :--- |
| Required-reason API | `UserDefaults` (`CA92.1`) | Persists `sdk_id`, `puid`, and trigger-dismissal windows, read only by the SDK. |
| Device ID | Not linked, not tracking | SDK-generated per-install `sdk_id`, used for widget resolution and attribution. |
| User ID | Linked, not tracking | Only when you call `PoltioSDK.identify(puid:)`. |
| Purchase History | Not linked, not tracking | Only when you call `PoltioSDK.recordPurchase(...)`. |
| Product Interaction | Not linked, not tracking | Screen views and widget impressions. |

`NSPrivacyTracking` is `false`. Review these against your own data practices when you fill in your
App Store privacy labels.
