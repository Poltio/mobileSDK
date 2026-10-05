#!/usr/bin/env bash
# Prints the UDID of the first available iPhone simulator, so `xcodebuild -destination id=...`
# works on any machine/CI image without hardcoding a device name or OS version.
set -euo pipefail

udid="$(xcrun simctl list devices available \
    | grep -m1 -E '^[[:space:]]+iPhone' \
    | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' || true)"

if [ -z "$udid" ]; then
    echo "No available iPhone simulator found. Install one via Xcode > Settings > Platforms." >&2
    exit 1
fi

echo "$udid"
