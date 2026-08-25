#!/usr/bin/env bash
set -e

NEW_VERSION="${1:-$VERSION}"

if [ -z "$NEW_VERSION" ]; then
    echo "Usage: $0 <version> or make version VERSION=<version>"
    exit 1
fi

# Strip leading 'v' if provided (e.g. v1.2.0 -> 1.2.0)
NEW_VERSION="${NEW_VERSION#v}"

echo "==> Bumping SDK version to ${NEW_VERSION} across platforms..."

# 1. iOS CocoaPods podspec
if [ -f "ios/PoltioSDK.podspec" ]; then
    sed -i.bak -E "s/s\.version[[:space:]]*=[[:space:]]*['\"][^'\"]+['\"]/s.version          = '${NEW_VERSION}'/" ios/PoltioSDK.podspec
    rm -f ios/PoltioSDK.podspec.bak
    echo "  ✅ Updated ios/PoltioSDK.podspec -> ${NEW_VERSION}"
fi

# 2. Android Gradle manifest (if present)
if [ -f "android/poltio-sdk/build.gradle.kts" ]; then
    sed -i.bak -E "s/version[[:space:]]*=[[:space:]]*['\"][^'\"]+['\"]/version = '${NEW_VERSION}'/" android/poltio-sdk/build.gradle.kts
    rm -f android/poltio-sdk/build.gradle.kts.bak
    echo "  ✅ Updated android/poltio-sdk/build.gradle.kts -> ${NEW_VERSION}"
fi

# 3. React Native package.json (if present)
if [ -f "react-native/package.json" ]; then
    sed -i.bak -E "s/\"version\":[[:space:]]*\"[^\"]+\"/\"version\": \"${NEW_VERSION}\"/" react-native/package.json
    rm -f react-native/package.json.bak
    echo "  ✅ Updated react-native/package.json -> ${NEW_VERSION}"
fi

echo "==> Successfully updated all SDK manifests to version ${NEW_VERSION}."
