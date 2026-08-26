# Poltio Mobile SDK Monorepo Makefile

DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR

.PHONY: all help check build build-ios build-android build-rn test test-ios test-android test-rn format format-ios lint lint-ios lint-pod lint-actions zizmor run-example-ios run-example-android run-example-rn version submit-version publish-cocoapods clean

help:
	@echo "Poltio Mobile SDK - Monorepo Makefile Commands:"
	@echo "  make check               - Check developer toolchain & platform requirements"
	@echo "  make build               - Build all SDKs (iOS, Android, React Native)"
	@echo "  make build-ios           - Build iOS Swift SDK"
	@echo "  make build-android       - Build Android Kotlin SDK"
	@echo "  make build-rn            - Build React Native SDK"
	@echo "  make test                - Run all test suites"
	@echo "  make test-ios            - Run iOS unit tests"
	@echo "  make test-android        - Run Android unit tests"
	@echo "  make test-rn             - Run React Native tests & linter"
	@echo "  make format              - Format code across all platforms"
	@echo "  make format-ios          - Format Swift source files with swiftformat"
	@echo "  make lint                - Run all linters (Swift, GitHub Actions)"
	@echo "  make lint-ios            - Lint Swift source files with swiftformat --lint"
	@echo "  make lint-pod            - Lint CocoaPods podspec with pod lib lint"
	@echo "  make lint-actions        - Lint GitHub Actions workflows with zizmor"
	@echo "  make zizmor              - Alias for lint-actions"
	@echo "  make run-example-ios     - Launch iOS Example App in simulator"
	@echo "  make run-example-android - Launch Android Example App in emulator"
	@echo "  make run-example-rn      - Launch React Native Example App"
	@echo "  make version             - Bump version across all SDK manifests"
	@echo "  make submit-version      - Tag release and trigger publishing"
	@echo "  make publish-cocoapods   - Publish iOS SDK to CocoaPods Trunk"
	@echo "  make clean               - Clean build artifacts across all platforms"

check:
	@chmod +x scripts/check-environment.sh
	@./scripts/check-environment.sh

# ------------------------------------------------------------------------------
# Formatting & Linting Targets
# ------------------------------------------------------------------------------
format: format-ios

format-ios:
	@echo "==> Formatting Swift files with swiftformat..."
	@if command -v swiftformat >/dev/null 2>&1; then \
		swiftformat Package.swift ios example/ios --swiftversion 5.9; \
	elif [ -f "/opt/homebrew/bin/swiftformat" ]; then \
		/opt/homebrew/bin/swiftformat Package.swift ios example/ios --swiftversion 5.9; \
	else \
		echo "swiftformat is not installed. Install via: brew install swiftformat"; \
	fi

lint: lint-ios lint-actions

lint-ios:
	@echo "==> Linting Swift files with swiftformat..."
	@if command -v swiftformat >/dev/null 2>&1; then \
		swiftformat Package.swift ios example/ios --lint --swiftversion 5.9; \
	elif [ -f "/opt/homebrew/bin/swiftformat" ]; then \
		/opt/homebrew/bin/swiftformat Package.swift ios example/ios --lint --swiftversion 5.9; \
	else \
		echo "Error: swiftformat is not installed. Install via: brew install swiftformat"; \
		exit 1; \
	fi

lint-pod:
	@echo "==> Linting CocoaPods podspec..."
	@if command -v pod >/dev/null 2>&1; then \
		pod spec lint ios/PoltioSDK.podspec --allow-warnings --quick; \
	elif [ -f "/opt/homebrew/bin/pod" ]; then \
		/opt/homebrew/bin/pod spec lint ios/PoltioSDK.podspec --allow-warnings --quick; \
	else \
		echo "Error: CocoaPods is not installed. Install via: brew install cocoapods or sudo gem install cocoapods"; \
		exit 1; \
	fi

lint-actions:
	@echo "==> Linting GitHub Actions workflows with zizmor..."
	@if command -v zizmor >/dev/null 2>&1; then \
		zizmor --persona=pedantic .github/workflows/; \
	elif [ -f "/opt/homebrew/bin/zizmor" ]; then \
		/opt/homebrew/bin/zizmor --persona=pedantic .github/workflows/; \
	else \
		echo "Error: zizmor is not installed. Install via: brew install zizmor"; \
		exit 1; \
	fi

zizmor: lint-actions

all: build test

# ------------------------------------------------------------------------------
# Build Targets
# ------------------------------------------------------------------------------
build: build-ios build-android build-rn

build-ios:
	@echo "==> Building iOS Swift SDK..."
	@if [ -f "Package.swift" ]; then \
		xcrun swift build; \
	else \
		echo "iOS SDK Package.swift manifest not found."; \
	fi

build-android:
	@echo "==> Building Android Kotlin SDK..."
	@if [ -d "android" ] && [ -f "android/gradlew" ]; then \
		cd android && ./gradlew :poltio-sdk:assembleRelease; \
	else \
		echo "Android SDK not initialized yet."; \
	fi

build-rn:
	@echo "==> Building React Native SDK..."
	@if [ -d "react-native" ] && [ -f "react-native/package.json" ]; then \
		cd react-native && npm run build; \
	else \
		echo "React Native SDK not initialized yet."; \
	fi

# ------------------------------------------------------------------------------
# Test Targets
# ------------------------------------------------------------------------------
test: test-ios test-android test-rn

test-ios:
	@echo "==> Testing iOS Swift SDK..."
	@if [ -f "Package.swift" ]; then \
		xcrun swift test; \
	else \
		echo "iOS SDK Package.swift manifest not found."; \
	fi

test-android:
	@echo "==> Testing Android Kotlin SDK..."
	@if [ -d "android" ] && [ -f "android/gradlew" ]; then \
		cd android && ./gradlew :poltio-sdk:test; \
	else \
		echo "Android SDK tests not initialized yet."; \
	fi

test-rn:
	@echo "==> Testing React Native SDK..."
	@if [ -d "react-native" ] && [ -f "react-native/package.json" ]; then \
		cd react-native && npm test; \
	else \
		echo "React Native SDK tests not initialized yet."; \
	fi

# ------------------------------------------------------------------------------
# Example Apps
# ------------------------------------------------------------------------------
build-example-ios:
	@echo "==> Building iOS Example App (.app bundle)..."
	@DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project example/ios/ExampleApp.xcodeproj -scheme ExampleApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath example/ios/.build/DerivedData build

open-example-ios:
	@echo "==> Opening iOS Example App in Xcode..."
	@open example/ios/ExampleApp.xcodeproj

run-example-ios: build-example-ios
	@echo "==> Booting iOS Simulator & Installing Example App..."
	@open -a Simulator
	@DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl boot "iPhone 17 Pro" 2>/dev/null || true
	@DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl install booted example/ios/.build/DerivedData/Build/Products/Debug-iphonesimulator/ExampleApp.app
	@echo "==> Launching ExampleApp on iOS Simulator screen..."
	@DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl launch booted com.poltio.ExampleApp

build-example-android:
	@echo "==> Building Android Example App (APK)..."
	@cd example/android && ./gradlew assembleDebug

open-example-android:
	@echo "==> Opening Android Example App in Android Studio..."
	@open -a "Android Studio" example/android 2>/dev/null || open example/android

run-example-android: build-example-android
	@echo "==> Resolving Android ADB path & checking device status..."
	@ADB_BIN=$$(command -v adb 2>/dev/null || echo "$$HOME/Library/Android/sdk/platform-tools/adb"); \
	EMU_BIN=$$(command -v emulator 2>/dev/null || echo "$$HOME/Library/Android/sdk/emulator/emulator"); \
	if $$ADB_BIN devices 2>/dev/null | grep -q "device$$"; then \
		echo "==> Installing & launching on running Android device/emulator..."; \
		$$ADB_BIN install -r example/android/app/build/outputs/apk/debug/app-debug.apk && \
		$$ADB_BIN shell am start -n com.poltio.exampleapp/.MainActivity; \
	elif [ -f "$$EMU_BIN" ] && [ -n "$$($$EMU_BIN -list-avds 2>/dev/null | head -n 1)" ]; then \
		AVD_NAME=$$($$EMU_BIN -list-avds 2>/dev/null | head -n 1); \
		echo "==> Booting Android Emulator ($$AVD_NAME)..."; \
		$$EMU_BIN -avd "$$AVD_NAME" > /dev/null 2>&1 & \
		echo "==> Waiting for Android OS to finish booting..."; \
		$$ADB_BIN wait-for-device; \
		while [ "$$($$ADB_BIN shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]; do sleep 1; done; \
		echo "==> Installing & launching example app..."; \
		$$ADB_BIN install -r example/android/app/build/outputs/apk/debug/app-debug.apk && \
		$$ADB_BIN shell am start -n com.poltio.exampleapp/.MainActivity; \
	else \
		echo "==> Launching Android Studio..."; \
		open -a "Android Studio" example/android 2>/dev/null || open example/android; \
		echo "Notice: No AVD emulator found. Create one in Android Studio Device Manager (see example/android/README.md)."; \
	fi

run-example-rn:
	@echo "==> Running React Native Example App..."
	@if [ -d "example/rn" ]; then \
		cd example/rn && npm start; \
	else \
		echo "React Native Example App not created yet."; \
	fi

# ------------------------------------------------------------------------------
# Release & Maintenance
# ------------------------------------------------------------------------------
VERSION ?= 1.0.0

version:
	@chmod +x scripts/bump-version.sh
	@./scripts/bump-version.sh "$(VERSION)"

submit-version:
	@echo "==> Submitting version $(VERSION)..."
	@git tag -a "v$(VERSION)" -m "Release v$(VERSION)"

publish-cocoapods:
	@echo "==> Pushing PoltioSDK to CocoaPods Trunk..."
	@if command -v pod >/dev/null 2>&1; then \
		pod trunk push ios/PoltioSDK.podspec --allow-warnings; \
	elif [ -f "/opt/homebrew/bin/pod" ]; then \
		/opt/homebrew/bin/pod trunk push ios/PoltioSDK.podspec --allow-warnings; \
	else \
		echo "Error: CocoaPods is not installed. Install via: brew install cocoapods or sudo gem install cocoapods"; \
		exit 1; \
	fi

clean:
	@echo "==> Cleaning build artifacts..."
	@rm -rf .build ios/.build example/ios/.build
	@if [ -d "android" ] && [ -f "android/gradlew" ]; then cd android && ./gradlew clean; fi
	@rm -rf react-native/dist react-native/node_modules
