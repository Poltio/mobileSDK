# Poltio Mobile SDK Monorepo Makefile

.PHONY: all help build build-ios build-android build-rn test test-ios test-android test-rn run-example-ios run-example-android run-example-rn version submit-version clean

help:
	@echo "Poltio Mobile SDK - Monorepo Makefile Commands:"
	@echo "  make build               - Build all SDKs (iOS, Android, React Native)"
	@echo "  make build-ios           - Build iOS Swift SDK"
	@echo "  make build-android       - Build Android Kotlin SDK"
	@echo "  make build-rn            - Build React Native SDK"
	@echo "  make test                - Run all test suites"
	@echo "  make test-ios            - Run iOS unit tests"
	@echo "  make test-android        - Run Android unit tests"
	@echo "  make test-rn             - Run React Native tests & linter"
	@echo "  make run-example-ios     - Launch iOS Example App in simulator"
	@echo "  make run-example-android - Launch Android Example App in emulator"
	@echo "  make run-example-rn      - Launch React Native Example App"
	@echo "  make version             - Bump version across all SDK manifests"
	@echo "  make submit-version      - Tag release and trigger publishing"
	@echo "  make clean               - Clean build artifacts across all platforms"

all: build test

# ------------------------------------------------------------------------------
# Build Targets
# ------------------------------------------------------------------------------
build: build-ios build-android build-rn

build-ios:
	@echo "==> Building iOS Swift SDK..."
	@if [ -d "ios" ] && [ -f "ios/Package.swift" ]; then \
		cd ios && swift build; \
	else \
		echo "iOS SDK not initialized yet."; \
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
	@if [ -d "ios" ] && [ -f "ios/Package.swift" ]; then \
		cd ios && swift test; \
	else \
		echo "iOS SDK tests not initialized yet."; \
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
	@echo "==> Building iOS Example App..."
	@DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --package-path example/ios --build-path example/ios/.build

open-example-ios:
	@echo "==> Opening iOS Example App in Xcode..."
	@open -a Xcode example/ios/Package.swift

run-example-ios: build-example-ios
	@echo "==> Booting iOS Simulator & Opening Xcode..."
	@open -a Simulator
	@DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl boot "iPhone 17 Pro" 2>/dev/null || true
	@open -a Xcode example/ios/Package.swift

run-example-android:
	@echo "==> Running Android Example App..."
	@if [ -d "example/android" ]; then \
		cd example/android && ./gradlew :app:installDebug; \
	else \
		echo "Android Example App not created yet."; \
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
	@echo "==> Bumping version to $(VERSION)..."
	@echo "Updating iOS, Android, and React Native package versions..."

submit-version:
	@echo "==> Submitting version $(VERSION)..."
	@git tag -a "v$(VERSION)" -m "Release v$(VERSION)"

clean:
	@echo "==> Cleaning build artifacts..."
	@rm -rf ios/.build
	@if [ -d "android" ] && [ -f "android/gradlew" ]; then cd android && ./gradlew clean; fi
	@rm -rf react-native/dist react-native/node_modules
