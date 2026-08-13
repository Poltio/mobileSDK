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
| **Test SDK** | `make test-ios` | Runs Swift PM unit test suite (`swift test`). |
| **Build Example** | `make build-example-ios` | Compiles `ExampleApp.app` bundle via `xcodebuild`. |
| **Open Xcode** | `make open-example-ios` | Opens `example/ios/ExampleApp.xcodeproj` in Xcode. |
| **Run Example** | `make run-example-ios` | Boots iOS Simulator (`iPhone 17 Pro`), installs `.app`, and launches app. |

---

## 📁 3. Project Structure (`/ios` & `/example/ios`)

```
poltio-mobile-sdk/
├── ios/                # Poltio Core iOS Library (Swift)
│   ├── Package.swift   # Swift Package Manager Manifest
│   ├── PoltioSDK.podspec
│   └── Sources/PoltioSDK/
└── example/ios/        # Sample E-Commerce App (TechStore - SwiftUI)
    └── ExampleApp.xcodeproj/
```
