# Poltio Mobile SDK Monorepo

Welcome to the **Poltio Mobile SDK** monorepo. This repository houses native mobile SDKs and integrated sample applications for bringing the interactive **Poltio TAG** web experience to mobile apps.

---

## 🏗 Repository Structure

```
.
├── Makefile                # Universal entrypoint for builds, tests, & examples
├── docs/                   # Developer setup & integration guides
│   ├── ANDROID.md          # Android SDK & AVD setup guide
│   └── IOS.md              # iOS SDK & Simulator setup guide
├── ios/                    # Pure Swift SDK (Swift Package Manager & CocoaPods)
├── android/                # Pure Kotlin SDK (Gradle & Maven Central)
├── react-native/           # React Native SDK wrapper (npm)
├── example/                # Integrated sample apps
│   ├── ios/                # iOS TechStore E-Commerce App (SwiftUI)
│   ├── android/            # Android TechStore E-Commerce App (Jetpack Compose)
│   └── rn/                 # React Native Sample App
└── scripts/                # Utility scripts (environment checker)
```

---

## ⚡️ Quick Start

### 1. Environment Check
Validate toolchains and dependencies across all platforms:
```bash
make check
```

### 2. Run Example Applications
Launch sample apps directly on simulators/emulators with a single Makefile command:

- **iOS**: [`make run-example-ios`](docs/IOS.md)
- **Android**: [`make run-example-android`](docs/ANDROID.md)
- **React Native**: `make run-example-rn`

---

## 💻 Usage Example

### iOS (Swift)

```swift
import PoltioSDK

// 1. Configure the SDK at app launch (e.g., inside AppDelegate or App init)
PoltioSDK.configure(clientKey: "poltio_test_pk_12345")

// 2. (Optional) Identify logged-in user with developer-provided user ID (puid)
PoltioSDK.identify(puid: "user_12345")

// 3. Track screen/view events (automatically includes internal sdk_id and puid)
PoltioSDK.track(event: "view", params: ["url": "https://www.poltio.com/pdp"])

// 4. Track conversion events
PoltioSDK.track(event: "TrackConversion", params: ["value": 99.99, "currency": "USD"])
```

---

## 📚 Documentation & Platform Setup Guides
- 📖 [**Android Setup Guide** (`docs/ANDROID.md`)](docs/ANDROID.md) - JDK 17, Android Studio, and AVD Emulator setup.
- 📖 [**iOS Setup Guide** (`docs/IOS.md`)](docs/IOS.md) - Xcode, Swift Package Manager, and iOS Simulator setup.

---

## 🛠 Universal Makefile Reference

| Target | Description |
| :--- | :--- |
| `make check` | Check developer toolchain & platform requirements |
| `make build` | Build all SDKs (iOS, Android, React Native) |
| `make build-ios` | Build iOS Swift SDK |
| `make build-android` | Build Android Kotlin SDK |
| `make build-rn` | Build React Native SDK |
| `make test` | Run test suites across all platforms |
| `make test-ios` | Run iOS unit tests |
| `make test-android` | Run Android unit tests |
| `make lint-ios` | Lint Swift source files with swiftformat |
| `make lint-pod` | Lint CocoaPods podspec |
| `make lint-actions` | Lint GitHub Actions workflows with zizmor |
| `make run-example-ios` | Launch iOS Example App in simulator |
| `make run-example-android` | Launch Android Example App in emulator |
| `make run-example-rn` | Launch React Native Example App |
| `make version` | Bump version across all SDK manifests |
| `make submit-version` | Tag release and trigger publishing |
| `make publish-cocoapods` | Publish iOS SDK to CocoaPods Trunk |
