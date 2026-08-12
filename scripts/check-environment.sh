#!/usr/bin/env bash

# ==============================================================================
# Poltio Mobile SDK - Developer Environment Check
# ==============================================================================

BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

CHECK_MARK="✅"
CROSS_MARK="❌"
WARN_MARK="⚠️ "

IOS_OK=true
ANDROID_OK=true
RN_OK=true

echo -e "${BOLD}${BLUE}======================================================================${NC}"
echo -e "${BOLD}${BLUE}             POLTIO MOBILE SDK - ENVIRONMENT CHECK                    ${NC}"
echo -e "${BOLD}${BLUE}======================================================================${NC}\n"

# ------------------------------------------------------------------------------
# 1. System & Host OS
# ------------------------------------------------------------------------------
echo -e "${BOLD}1. Host System${NC}"
OS_NAME=$(uname -s)
if [ "$OS_NAME" = "Darwin" ]; then
    MAC_VER=$(sw_vers -productVersion)
    echo -e "  ${CHECK_MARK} macOS Detected (${MAC_VER})"
else
    echo -e "  ${WARN_MARK} Non-macOS system (${OS_NAME}). Note: iOS builds require macOS."
fi

if command -v git >/dev/null 2>&1; then
    GIT_VER=$(git --version | awk '{print $3}')
    echo -e "  ${CHECK_MARK} Git (${GIT_VER})"
else
    echo -e "  ${CROSS_MARK} Git not found"
fi

if command -v make >/dev/null 2>&1; then
    echo -e "  ${CHECK_MARK} Make installed"
else
    echo -e "  ${CROSS_MARK} Make not found"
fi

echo ""

# ------------------------------------------------------------------------------
# 2. iOS Development Requirements (/ios)
# ------------------------------------------------------------------------------
echo -e "${BOLD}2. iOS Platform Requirements (/ios)${NC}"

if DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -version >/dev/null 2>&1; then
    XCODE_VER=$(DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -version 2>/dev/null | tr '\n' ' ' | xargs)
    echo -e "  ${CHECK_MARK} Xcode (${XCODE_VER})"
else
    echo -e "  ${CROSS_MARK} Xcode / xcodebuild not found (Install from Mac App Store or 'xcode-select --install')"
    IOS_OK=false
fi

if command -v swift >/dev/null 2>&1; then
    SWIFT_VER=$(swift --version 2>/dev/null | head -n 1 | awk '{print $4}')
    echo -e "  ${CHECK_MARK} Swift Compiler (${SWIFT_VER})"
else
    echo -e "  ${CROSS_MARK} Swift compiler not found"
    IOS_OK=false
fi

if command -v pod >/dev/null 2>&1; then
    POD_VER=$(pod --version 2>/dev/null)
    echo -e "  ${CHECK_MARK} CocoaPods (${POD_VER})"
else
    echo -e "  ${WARN_MARK} CocoaPods not found (Recommended for CocoaPods release testing: 'sudo gem install cocoapods')"
fi

if command -v xcrun >/dev/null 2>&1 && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl list devices 2>/dev/null | grep -q "iPhone"; then
    echo -e "  ${CHECK_MARK} iOS Simulators available"
else
    echo -e "  ${WARN_MARK} iOS Simulator runtime not detected"
fi

echo ""

# ------------------------------------------------------------------------------
# 3. Android Development Requirements (/android)
# ------------------------------------------------------------------------------
echo -e "${BOLD}3. Android Platform Requirements (/android)${NC}"

JAVA_FOUND=false
if [ -n "$JAVA_HOME" ] && [ -x "$JAVA_HOME/bin/java" ]; then
    JAVA_VER=$("$JAVA_HOME/bin/java" -version 2>&1 | head -n 1)
    echo -e "  ${CHECK_MARK} Java (JAVA_HOME): ${JAVA_VER}"
    JAVA_FOUND=true
elif command -v java >/dev/null 2>&1 && java -version >/dev/null 2>&1; then
    JAVA_VER=$(java -version 2>&1 | head -n 1)
    echo -e "  ${CHECK_MARK} Java (System PATH): ${JAVA_VER}"
    JAVA_FOUND=true
elif [ -d "/opt/homebrew/opt/openjdk@17" ]; then
    echo -e "  ${CHECK_MARK} Java: OpenJDK 17 installed at /opt/homebrew/opt/openjdk@17"
    JAVA_FOUND=true
else
    echo -e "  ${CROSS_MARK} Java JDK not found (Required: OpenJDK 17+. Install via 'brew install openjdk@17' or Android Studio)"
    ANDROID_OK=false
    RN_OK=false
fi

if [ -d "/Applications/Android Studio.app" ]; then
    echo -e "  ${CHECK_MARK} Android Studio installed (/Applications/Android Studio.app)"
else
    echo -e "  ${WARN_MARK} Android Studio not found in /Applications (Install via 'brew install --cask android-studio' or developer.android.com)"
fi

if command -v adb >/dev/null 2>&1 || [ -x "$HOME/Library/Android/sdk/platform-tools/adb" ]; then
    echo -e "  ${CHECK_MARK} Android Debug Bridge (adb) available"
else
    echo -e "  ${WARN_MARK} adb not found in PATH (Will be installed automatically with Android Studio SDK)"
fi

if command -v emulator >/dev/null 2>&1 || [ -x "$HOME/Library/Android/sdk/emulator/emulator" ]; then
    echo -e "  ${CHECK_MARK} Android Emulator available"
else
    echo -e "  ${WARN_MARK} Android Emulator binary not found in PATH"
fi

echo ""

# ------------------------------------------------------------------------------
# 4. React Native Development Requirements (/react-native)
# ------------------------------------------------------------------------------
echo -e "${BOLD}4. React Native Platform Requirements (/react-native)${NC}"

if command -v node >/dev/null 2>&1; then
    NODE_VER=$(node -v)
    echo -e "  ${CHECK_MARK} Node.js (${NODE_VER})"
else
    echo -e "  ${CROSS_MARK} Node.js not found (Required for React Native: Install via 'brew install node')"
    RN_OK=false
fi

if command -v npm >/dev/null 2>&1; then
    NPM_VER=$(npm -v)
    echo -e "  ${CHECK_MARK} npm (${NPM_VER})"
else
    echo -e "  ${CROSS_MARK} npm not found"
    RN_OK=false
fi

if command -v watchman >/dev/null 2>&1; then
    WATCHMAN_VER=$(watchman -v)
    echo -e "  ${CHECK_MARK} Watchman (${WATCHMAN_VER})"
else
    echo -e "  ${WARN_MARK} Watchman not found (Recommended for React Native file watching: 'brew install watchman')"
fi

echo ""

# ------------------------------------------------------------------------------
# 5. Summary & Actionable Recommendations
# ------------------------------------------------------------------------------
echo -e "${BOLD}${BLUE}======================================================================${NC}"
echo -e "${BOLD}SUMMARY REPORT:${NC}"

if [ "$IOS_OK" = true ]; then
    echo -e "  iOS Platform:          ${GREEN}${BOLD}READY FOR DEVELOPMENT${NC}"
else
    echo -e "  iOS Platform:          ${RED}${BOLD}MISSING DEPENDENCIES${NC}"
fi

if [ "$ANDROID_OK" = true ]; then
    echo -e "  Android Platform:      ${GREEN}${BOLD}READY FOR DEVELOPMENT${NC}"
else
    echo -e "  Android Platform:      ${YELLOW}${BOLD}NEEDS JDK / ANDROID STUDIO${NC}"
fi

if [ "$RN_OK" = true ]; then
    echo -e "  React Native Platform: ${GREEN}${BOLD}READY FOR DEVELOPMENT${NC}"
else
    echo -e "  React Native Platform: ${YELLOW}${BOLD}NEEDS NODE.JS / NPM${NC}"
fi

echo -e "${BOLD}${BLUE}======================================================================${NC}\n"

if [ "$IOS_OK" = false ] || [ "$ANDROID_OK" = false ] || [ "$RN_OK" = false ]; then
    echo -e "${BOLD}Quick Setup Command Recommendations:${NC}"
    if [ "$IOS_OK" = false ]; then
        echo -e "  • For iOS:     xcode-select --install"
    fi
    if [ "$ANDROID_OK" = false ]; then
        echo -e "  • For Android: brew install openjdk@17 && brew install --cask android-studio"
    fi
    if [ "$RN_OK" = false ]; then
        echo -e "  • For RN:      brew install node watchman"
    fi
    echo ""
fi
