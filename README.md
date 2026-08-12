# Poltio Mobile SDK

Bringing the **Poltio TAG** web experience (screen targeting, floating launcher button, interactive popup widget in an in-app WebView) to native mobile applications.

## Repository Structure

- [`/ios`](./ios): Swift Package & CocoaPods library for native iOS apps (iOS 14.0+).
- [`/android`](./android): Gradle library for native Android apps (API 21+).
- [`/react-native`](./react-native): React Native wrapper library (`@poltio/react-native-sdk`).
- [`/example`](./example): Sample apps demonstrating integration for iOS, Android, and React Native.
- [`AGENTS.md`](./AGENTS.md): Guidelines and rules for AI assistants (Claude, Gemini, Antigravity) working on this codebase.

## Quick Start Integration

### iOS (Swift Package Manager)
Add `https://github.com/Poltio/mobileSDK` as a Swift Package dependency, then:

```swift
import PoltioSDK

// In AppDelegate or App launch:
Poltio.configure(apiKey: "YOUR_API_KEY")

// On screen navigation:
Poltio.trackScreen("phone-finder")
```

### Android (Gradle)
Add dependency to `build.gradle.kts`:

```kotlin
implementation("com.poltio:sdk:1.0.0")

// In Application class or Activity:
Poltio.initialize(context, "YOUR_API_KEY")

// On screen navigation:
Poltio.trackScreen("phone-finder")
```

### React Native
Install via npm/yarn:

```bash
npm install @poltio/react-native-sdk
```

```typescript
import { Poltio } from '@poltio/react-native-sdk';

Poltio.configure('YOUR_API_KEY');
Poltio.trackScreen('phone-finder');
```
