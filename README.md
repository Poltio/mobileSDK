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

> **Note:** Call `configure()` once at app startup, ideally from `Application.onCreate()` as shown
> above. It does no disk or network I/O on the calling thread. If you configure later, pass the
> current `Activity` as `context` so the first screen's trigger can attach to it right away.
> Passing an `Activity` is safe: only its `applicationContext` is retained.

### Android (Java)

Every public member of `PoltioSDK` is `@JvmStatic`, and functions with Kotlin default arguments
have Java overloads:

```java
PoltioSDK.configure(this, "poltio_test_pk_12345");
PoltioSDK.identify("user_12345");
PoltioSDK.track("view", Collections.singletonMap("url", "myapp://products/123"));
PoltioSDK.recordPurchase("ORD-90211", 249.90, "myapp://checkout/complete", "USD",
        Collections.singletonList(new PoltioPurchaseItem("SKU-1")));
```

### Widget events, trigger control & logging

```swift
// iOS
PoltioSDK.onWidgetEvent = { event, data in /* "close", "complete", "leadSubmit", ... */ }
PoltioSDK.hideTrigger()          // hide the floating trigger currently on screen
PoltioSDK.logLevel = .debug      // default: .warning
print(PoltioSDK.version)         // e.g. "1.0.0"
```

```kotlin
// Android
PoltioSDK.onWidgetEvent = PoltioWidgetEventListener { event, data -> /* ... */ }
PoltioSDK.hideTrigger()
PoltioSDK.logLevel = PoltioLogLevel.DEBUG   // default: WARNING
Log.d("App", PoltioSDK.version)
```

> `track()` drives widget resolution only for screen views (`"view"`, `"viewContent"`,
> `"view_content"`). Other event names are accepted but only logged locally; they are **not** sent
> to the Poltio API. Use `recordPurchase(...)` for conversions.
>
> The default log level is `warning`. Identifiers (`sdk_id`, `puid`) and event params are only
> logged at `debug`. iOS logs go through the unified logging system (subsystem `com.poltio.sdk`), so
> you can filter them in Console.app.

### Opening product links in your app (`onOpenURL` / `onOpenUrl`)

The widget only ever navigates within Poltio's own pages. Every other link the user taps — e.g. the
recommended product on a result page — leaves the widget. By default the SDK hands it to the system
(`UIApplication.open` / `Intent.ACTION_VIEW`), which usually means the browser: **iOS never routes
an app's own Universal Links back into the app that opens them**, and on Android only verified App
Links come back.

Set a URL handler to route those links to your own screens instead. When a handler is set, the
widget closes first and the link is then passed to your handler on the main thread, so you're free
to push, switch tabs, or present a screen modally. Return `true` if you handled the link (the
current screen's floating trigger is removed too, so it doesn't reappear over your new screen; the
next `track` view call shows whatever that screen resolves to), or `false` to have the SDK open it
with the system as above. Non-web links such as `tel:` and `mailto:` arrive
here too, so return `false` for anything you don't recognize. Without a handler, nothing changes:
the link opens with the system and the widget stays open.

```swift
// iOS
PoltioSDK.onOpenURL = { url in
    guard url.host == "shop.example.com", let productId = url.pathComponents.last else { return false }
    router.showProduct(id: productId)
    return true
}
```

```kotlin
// Android
PoltioSDK.onOpenUrl = PoltioUrlHandler { url ->
    if (url.host != "shop.example.com") return@PoltioUrlHandler false
    router.showProduct(url.lastPathSegment)
    true
}
```

```java
// Android (Java)
PoltioSDK.setOnOpenUrl(url -> router.handle(url));
```

### Adding products to your cart (`onAddToCart`)

On the web, the widget's add-to-cart button runs a script written for each store. In your app, the
widget hands the product to `onAddToCart` instead. It is called on the main thread and **the widget
stays open**, so the user can keep browsing. Return `true` once you've added the item, or `false` to
have the SDK open `item.url` like a tapped product link (through `onOpenURL` / `onOpenUrl` above).
The same fallback runs when no handler is set, so the button never does nothing.

A `PoltioCartItem` has `productId` (your catalog ID from the widget's product data), `url` (http/https
only), `quantity` (at least 1), and `data`, which holds the full payload including extra fields such
as `sku` or `variant`.

```swift
// iOS
PoltioSDK.onAddToCart = { item in
    guard let productId = item.productId else { return false }
    cart.add(productId: productId, quantity: item.quantity)
    return true
}
```

```kotlin
// Android
PoltioSDK.onAddToCart = PoltioAddToCartHandler { item ->
    val productId = item.productId ?: return@PoltioAddToCartHandler false
    cart.add(productId, item.quantity)
    true
}
```

```java
// Android (Java)
PoltioSDK.setOnAddToCart(item -> {
    if (item.getProductId() == null) return false;
    cart.add(item.getProductId(), item.getQuantity());
    return true;
});
```

The event also reaches `onWidgetEvent` as `addToCart`, as before.

#### Widget bridge contract

The SDK loads the widget with `sdk_platform` (`ios` / `android`) and `sdk_version` (e.g. `1.0.2`) in
its URL, so the widget can tell it's running inside an app. When it is, the add-to-cart button posts
this message instead of running the store's web script. Always send `url` (it's the fallback when the
app doesn't add the item); `productId` is what most apps' carts need. Every field is passed through
in `data`.

```js
const msg = { event: "addToCart", data: { productId: "42", url: "https://shop.example.com/p/42", quantity: 1 } };
if (window.webkit?.messageHandlers?.poltioNative) window.webkit.messageHandlers.poltioNative.postMessage(msg); // iOS app
else if (window.PoltioNativeBridge) window.PoltioNativeBridge.postMessage(JSON.stringify(msg));             // Android app
else runStoreCartScript();                                                                                   // web
```

On iOS, `addToCart` is only accepted from `https://poltio.com` / `https://*.poltio.com` frames. On
Android, any frame inside the widget can currently send it, so validate `productId` against your
catalog before adding it.

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

## 🚀 Releasing

Releases are fully automated by GitHub Actions. Nothing is tagged or published from a laptop.

1. **Merge a PR into `main`.** `release.yaml` (`poltio/action-release`) creates the next tag and
   GitHub release: a patch bump by default, or a minor/major bump if the PR has a `minor`/`major`
   label.
2. **The published release triggers the publish workflows**, which take the version from the tag:
   - `publish-maven.yaml` publishes `com.poltio:poltio-sdk` to Maven Central (`-PlibVersion=<tag>`).
     Central usually takes 10–30 minutes to serve a new version after the workflow finishes.
   - `publish-cocoapods.yaml` syncs `PoltioSDK.podspec` to the tag (`scripts/bump-version.sh`) and
     runs `pod trunk push`. Trunk can report "Calling the GitHub commit API timed out" even though
     the push went through, so check `https://trunk.cocoapods.org/api/v1/pods/PoltioSDK` before
     re-running (a re-run of an accepted version fails with "duplicate entry").
3. **Swift Package Manager** resolves the tag directly; there's nothing to publish.

Don't bump versions, tag, or publish locally.

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
| `make test-ios` | Run iOS unit tests on an iOS Simulator (full suite) |
| `make test-android` | Run Android unit tests |
| `make lint-ios` | Lint Swift source files with swiftformat |
| `make lint-pod` | Lint CocoaPods podspec |
| `make lint-actions` | Lint GitHub Actions workflows with zizmor |
| `make run-example-ios` | Launch iOS Example App in simulator |
| `make run-example-android` | Launch Android Example App in emulator |
| `make run-example-rn` | Launch React Native Example App |
| `make version` | Sync manifests to a version; the CocoaPods workflow does this from the tag (see [Releasing](#-releasing)) |
| `make publish-cocoapods` | Manual fallback for the CocoaPods publish workflow |
