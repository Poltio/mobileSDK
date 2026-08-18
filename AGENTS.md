# AGENTS.md - Guidelines for AI Coding Assistants (Claude, Antigravity, Gemini)

Welcome to the **Poltio Mobile SDK** repository. This file provides guidelines, architectural conventions, and workflows for AI agents working on this codebase.

> [!IMPORTANT]
> ### MANDATORY GROUND RULES FOR ALL AI AGENTS
> 1. **Root Makefile Commands**: EVERY build, test, lint, example-app, versioning, and publishing action MUST be executable via the root `Makefile` (`make build`, `make build-ios`, `make test-ios`, `make run-example-ios`, `make version`, `make submit-version`, etc.). Agents must maintain and update the Makefile as targets or sub-projects evolve.
> 2. **Monorepo Architecture**: This repository is a monorepo for all Poltio mobile SDKs. Code for iOS, Android, and React Native MUST be isolated in their respective `/ios`, `/android`, and `/react-native` directories.
> 3. **Example Apps**: Sample apps MUST reside in `/example` (`/example/ios`, `/example/android`, `/example/rn`). Every sample app MUST be runnable directly via root `Makefile` targets.

---

## 1. Project Overview & Architecture

Poltio Mobile SDKs bring the **Poltio TAG** web experience (screen targeting, floating launcher button, interactive popup widget in an in-app WebView) to native mobile applications.

### Key Architectural Principles:
1. **Thin Native SDK Core**: Keep the native footprint as small and lightweight as possible. The SDK's primary duties are:
   - Query Poltio API for active widgets matching current screen/route name.
   - Attach a lightweight native floating launcher view (overlay FAB/banner).
   - Present a modal `WKWebView` (iOS) or `WebView` (Android) loading the Poltio Widget URL.
   - Bridge events between JavaScript in the WebView and Native host app (close, complete, lead submit).
2. **Native First, Wrapper Second**:
   - **iOS SDK (`/ios`)**: Pure Swift library (Swift Package Manager & CocoaPods).
   - **Android SDK (`/android`)**: Pure Kotlin library (Gradle & Maven Central).
   - **React Native SDK (`/react-native`)**: Light wrapper bridging JS calls directly to the underlying Swift and Kotlin native SDKs.
3. **Zero Heavy External UI Dependencies**: Use native platform components (`WKWebView`, `UIWindowScene`, `WebView`, `Activity`/`DecorView`, standard networking APIs like `URLSession` and `HttpURLConnection`/`OkHttp`).

---

## 2. Repository Structure

```
/
├── Makefile        # Universal entrypoint for build, test, run, & release tasks
├── ios/            # Swift Package / Xcode project for iOS SDK
├── android/        # Android Library project (Kotlin)
├── react-native/   # React Native library package (npm)
├── example/        # Integrated sample apps for manual testing
│   ├── ios/        # Standalone iOS Example App
│   ├── android/    # Standalone Android Example App
│   └── rn/         # Standalone React Native Example App
├── AGENTS.md       # AI Guidelines & Instructions
└── README.md       # Project Overview & Integration Guide
```

---

## 3. Technology Stack & Rules

### iOS (`/ios`)
- **Language**: Swift 5.9+
- **Min OS Target**: iOS 14.0+
- **Packaging**: Swift Package Manager (`Package.swift`) and CocoaPods (`PoltioSDK.podspec`).
- **Privacy Requirements**: Must include `PrivacyInfo.xcprivacy` manifest for iOS 17+.

### Android (`/android`)
- **Language**: Kotlin 1.9+
- **Min SDK Version**: API level 21 (Android 5.0+) or API level 24 (Android 7.0+).
- **Packaging**: Gradle Library module (`:poltio-sdk`), deployable to Maven Central.
- **UI Overlay**: Add launcher to current Activity's `window.decorView` or root `FrameLayout`.

### React Native (`/react-native`)
- **Language**: TypeScript
- **Architecture**: Support both React Native Legacy Bridge and New Architecture (TurboModules).
- **Dependencies**: React Native core peer dependencies. Depend directly on local/published Native Swift & Kotlin SDKs.

---

## 4. Universal Makefile Workflows

AI agents MUST use and maintain the root `Makefile` targets for executing builds, tests, formatting, and examples:

| Target | Description |
| :--- | :--- |
| `make build` | Builds all SDKs (iOS, Android, React Native). |
| `make build-ios` | Builds the Swift iOS SDK package. |
| `make test-ios` | Runs iOS unit tests (`swift test`). |
| `make format` | Formats code across all platforms. |
| `make format-ios` | Formats all Swift files using `swiftformat`. |
| `make lint-ios` | Lints Swift files using `swiftformat --lint`. |
| `make build-android` | Builds Android AAR library via Gradle. |
| `make test-android` | Runs Android unit tests via Gradle. |
| `make build-rn` | Builds React Native TypeScript package. |
| `make test-rn` | Runs React Native tests and linter. |
| `make test` | Runs test suites across all platforms. |
| `make run-example-ios` | Builds & runs the iOS example app in simulator. |
| `make run-example-android`| Builds & runs the Android example app in emulator. |
| `make run-example-rn` | Builds & starts the React Native example app. |
| `make version` | Bumps version across all platform manifest files. |
| `make submit-version` | Tags and triggers release/publishing workflows. |

---

## 5. Coding Style & Conventions

- **Swift**:
  - **Formatting**: ALL Swift source and test files (`/ios` and `/example/ios`) **MUST** be formatted using `swiftformat` (run `make format-ios`) after every modification.
  - Follow Apple API Design Guidelines, standard Swift naming (`camelCase` for properties, `PascalCase` for types).
- **Kotlin**: Follow official Kotlin style guides, explicit visibility modifiers, immutability (`val` over `var` where possible).
- **TypeScript**: Strict mode enabled, explicit return types on exported functions/classes, detailed JSDoc comments for public SDK APIs.
