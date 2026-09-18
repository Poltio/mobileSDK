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
├── react-native/           # React Native SDK wrapper (npm) (WIP)
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

- [X] **iOS**: [`make run-example-ios`](docs/IOS.md)
- [X] **Android**: [`make run-example-android`](docs/ANDROID.md)
- [ ] **React Native**: `make run-example-rn` (WIP)

---

## 📦 Installation

### iOS

#### Option 1: Swift Package Manager (Recommended)

##### In Xcode:
1. Open your project in Xcode.
2. Navigate to **File** > **Add Package Dependencies...** (or select your project in the Project Navigator > **Package Dependencies** > **+**).
3. Enter the repository URL:
   ```text
   https://github.com/Poltio/mobileSDK.git
   ```
4. Set the **Dependency Rule** to **Up to Next Major Version** starting from `1.0.0`.
5. Select **PoltioSDK** and add it to your application target.

##### In `Package.swift`:
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

#### Option 2: CocoaPods

Add `PoltioSDK` to your project's `Podfile`:

```ruby
target 'YourAppTarget' do
  use_frameworks!
  pod 'PoltioSDK', '~> 1.0.0'
end
```

Then install the pod:
```bash
pod install
```

### Android

Add the Maven Central dependency to your app module's build script.

**Kotlin DSL** (`build.gradle.kts`):
```kotlin
dependencies {
    implementation("com.poltio:poltio-sdk:1.0.0")
}
```

**Groovy DSL** (`build.gradle`):
```groovy
dependencies {
    implementation 'com.poltio:poltio-sdk:1.0.0'
}
```

Maven Central is included by default via `mavenCentral()` in most projects' repositories block, so no extra repository setup is needed.

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

// 4. Record a completed purchase for conversion attribution (e.g. on checkout success)
PoltioSDK.recordPurchase(
    orderId: "ORD-90211",
    value: 249.90,
    url: "myapp://checkout/complete",
    currency: "USD",
    items: [
        PoltioPurchaseItem(id: "SKU-1", name: "Running Shoe", category: "footwear", quantity: 2, value: 124.95)
    ]
)
```

### Android (Kotlin)

```kotlin
import com.poltio.sdk.PoltioSDK
import com.poltio.sdk.PoltioPurchaseItem

// 1. Configure the SDK at app launch (e.g., inside your Application.onCreate())
PoltioSDK.configure(context = this, clientKey = "poltio_test_pk_12345")

// 2. (Optional) Identify logged-in user with developer-provided user ID (puid)
PoltioSDK.identify(puid = "user_12345")

// 3. Track screen/view events (automatically includes internal sdk_id and puid)
PoltioSDK.track(event = "view", params = mapOf("url" to "https://www.poltio.com/pdp"))

// 4. Record a completed purchase for conversion attribution (e.g. on checkout success)
PoltioSDK.recordPurchase(
    orderId = "ORD-90211",
    value = 249.90,
    url = "myapp://checkout/complete",
    currency = "USD",
    items = listOf(
        PoltioPurchaseItem(id = "SKU-1", name = "Running Shoe", category = "footwear", quantity = 2, value = 124.95)
    )
)
```

> **Note:** Call `configure()` once at app startup — e.g. from a custom `Application` subclass, as
> shown above — and pass it an `Application` context so the SDK can attach the floating trigger
> overlay to whichever Activity is on screen. Passing an `Activity` (or other) context is safe too,
> since only `applicationContext` is retained, but the overlay won't attach without one.

---

## 💰 Conversion Tracking (`recordPurchase`)

Both SDKs expose a dedicated `recordPurchase` API that reports a completed purchase to
`POST /sdk/mobile/v1/purchase` for conversion attribution — the native counterpart of the
[web SDK's `Purchase` event](https://platform.poltio.com/docs/conversion/). Call it once a purchase
has actually completed (e.g. from your checkout-success screen or order-confirmation handler).

| Parameter | Type | Required | Notes |
| :--- | :--- | :--- | :--- |
| `orderId` | `String` | Yes | Unique order/transaction identifier. This is the backend's **deduplication key** — retrying with the same `orderId` records the purchase once, but reusing it across two distinct purchases silently drops the second one's revenue. Always pass a fresh id per order. |
| `value` | `Double` | Yes | Total monetary value of the purchase. Must be greater than zero. |
| `url` | `String` | Yes | The checkout/success screen URL or deep link (e.g. `myapp://checkout/complete`). Must include a scheme and host — a bare path is rejected rather than silently rewritten. |
| `currency` | `String?` | No | ISO 4217 currency code (e.g. `"USD"`). |
| `items` | `[PoltioPurchaseItem]` / `List<PoltioPurchaseItem>` | No | Line items (`id`, `name`, `category`, `quantity`, `value`). |
| `eventTime` (iOS) / `eventTimeSeconds` (Android) | `Date?` / `Long?` | No | When the purchase actually occurred, if reported after the fact (e.g. from an offline queue). Defaults to receipt time server-side when omitted. |

**Attribution**: the purchase is credited to the widget session already recorded for this device
via the internal `view` tracking call (`/sdk/mobile/v1/widget`) — both SDKs send the same
device id automatically on every call, so no extra wiring is needed. A purchase from a device with
no such session is still accepted, but whether (and how) it's recorded depends on the publisher's
web conversion URL configuration; don't build reconciliation logic on the assumption that
unattributed purchases are dropped.

**Reliability**: `recordPurchase` is fire-and-forget — it runs on a background thread, never
blocks or throws, and the backend responds `204` as soon as the request is accepted (the
conversion row is written afterwards, so a `204` isn't a guarantee it landed). Invalid input
(blank `orderId`, non-positive `value`, or a `url` without a scheme/host) is rejected client-side
with a log message and no network call, so a coding mistake never accidentally spends a
deduplication slot on a malformed request.

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
