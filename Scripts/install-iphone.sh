#!/bin/zsh
# Builds the iPhone app, signs it with your free Personal Team, installs it on the connected
# iPhone and opens it. A free account's signature lasts 7 days, so run this again about once a
# week (the app and its data stay in place).
#
#     zsh Scripts/install-iphone.sh            # the first connected iPhone
#     DEVICE=<udid> zsh Scripts/install-iphone.sh
#
# Needs the iPhone unlocked, plugged in (or on the same Wi-Fi) and Developer Mode on.
set -euo pipefail

cd "${0:A:h:h}"
bundle_id="com.example.onepercent"
derived="${TMPDIR%/}/one-percent-ios-dd"      # outside the project: its folder name contains a "%"

device="${DEVICE:-}"
if [ -z "$device" ]; then
    list="$(mktemp)"
    xcrun devicectl list devices --json-output "$list" >/dev/null 2>&1 || true
    device="$(python3 - "$list" <<'PY'
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    devices = []
for d in devices:
    props = d.get("hardwareProperties", {})
    if props.get("deviceType") == "iPhone" and d.get("connectionProperties", {}).get("tunnelState") in ("connected", "disconnected"):
        print(props.get("udid") or d["identifier"]); break
PY
)"
    rm -f "$list"
fi
[ -n "$device" ] || { echo "No iPhone found. Unlock it, plug it in, and try again."; exit 1; }

echo "== building for $device"
app="$derived/Build/Products/Debug-iphoneos/OnePercentiOS.app"
rm -rf "$app"      # never install a leftover from an earlier build
log="$(mktemp)"
if ! xcodebuild -project iOS/OnePercentiOS.xcodeproj -scheme OnePercentiOS \
        -destination "id=$device" -derivedDataPath "$derived" -allowProvisioningUpdates build >"$log" 2>&1; then
    grep -E "error:" "$log" | sort -u | head -20
    rm -f "$log"
    echo "Build failed."
    exit 1
fi
rm -f "$log"
[ -d "$app" ] || { echo "Build produced no app."; exit 1; }

echo "== installing"
xcrun devicectl device install app --device "$device" "$app" | tail -1

echo "== opening"
xcrun devicectl device process launch --device "$device" "$bundle_id" >/dev/null 2>&1 && echo "Done." || \
    echo "Installed. If it will not open: Settings > General > VPN & Device Management > trust your developer certificate."
