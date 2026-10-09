#!/bin/zsh
# Builds the iPhone app, signs it with your free Personal Team, installs it on the connected
# iPhone and opens it. A free account's signature lasts 7 days, so run this again about once a
# week (the app and its data stay in place).
#
#     zsh Scripts/install-iphone.sh            # the first connected iPhone
#     DEVICE=<udid> zsh Scripts/install-iphone.sh
#
# Needs the iPhone unlocked, plugged in (or on the same Wi-Fi) and Developer Mode on.
#
# Scripts/iphone-autorefresh.sh sets this up to run by itself every 6 days. NO_LAUNCH=1 installs
# without opening the app (so it never pops up while you are using the phone).
set -euo pipefail

cd "${0:A:h:h}"
bundle_id="com.example.onepercent"
tmp="${TMPDIR:-$(getconf DARWIN_USER_TEMP_DIR)}"      # launchd jobs may start without TMPDIR
state="$HOME/Library/Application Support/One Percent iPhone Refresh"
staging="$state/staging"
renewal="$state/source"       # what the 6-day job rebuilds; only ever a copy that installed fine

# Xcode's asset compiler cannot read files under ~/Desktop, and background jobs cannot either, so
# the app is always built from a copy outside it. (Derived data lives outside the project too: its
# folder name contains a "%".)
case "$PWD" in
    "$renewal")
        derived="${tmp%/}/one-percent-ios-dd-refresh" ;;
    *)
        mkdir -p "$staging"
        rsync -a --delete Package.swift Sources Tests Resources iOS Scripts "$staging/"
        cd "$staging"
        derived="${tmp%/}/one-percent-ios-dd" ;;
esac

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
    # Real phones only: Xcode also lists simulators, which cannot take a signed device build.
    if props.get("deviceType") == "iPhone" and props.get("reality") == "physical" \
            and d.get("connectionProperties", {}).get("tunnelState") in ("connected", "disconnected"):
        print(props.get("udid") or d["identifier"]); break
PY
)"
    rm -f "$list"
fi
[ -n "$device" ] || { echo "No iPhone found. Unlock it, plug it in, and try again."; exit 1; }

# Xcode keeps using a provisioning profile until it has run out, so a rebuild would hand back the
# same expiry date and the app would still stop 7 days after the FIRST install. Setting this app's
# profiles aside makes the build ask Apple for new ones: a fresh 7 days. They come back if it fails.
profiles="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
aside="$(mktemp -d)"
for profile in "$profiles"/*.mobileprovision(N); do
    security cms -D -i "$profile" 2>/dev/null | grep -q "$bundle_id" && mv "$profile" "$aside/"
done
restore_profiles() { mv "$aside"/*.mobileprovision(N) "$profiles/" 2>/dev/null; rmdir "$aside" 2>/dev/null; return 0; }

echo "== building for $device"
app="$derived/Build/Products/Debug-iphoneos/OnePercentiOS.app"
rm -rf "$app"      # never install a leftover from an earlier build
log="$(mktemp)"
if ! xcodebuild -project iOS/OnePercentiOS.xcodeproj -scheme OnePercentiOS \
        -destination "id=$device" -derivedDataPath "$derived" -allowProvisioningUpdates build >"$log" 2>&1; then
    grep -E "error:" "$log" | sort -u | head -20
    rm -f "$log"
    restore_profiles
    echo "Build failed."
    exit 1
fi
rm -f "$log"
rm -rf "$aside"
[ -d "$app" ] || { echo "Build produced no app."; exit 1; }

echo "== installing"
if ! output="$(xcrun devicectl device install app --device "$device" "$app" 2>&1)"; then
    echo "$output" | tail -6
    echo "Install failed."
    exit 1
fi

# The new signature starts now: remember when, so the 6-day job knows when it is due again.
mkdir -p "$state" && date +%s >"$state/last-install"

# The 6-day job renews exactly what was installed just now: same code, a fresh signature. The copy
# is only replaced after an install that worked, so a broken edit can never end up in it.
if [ "$PWD" = "$staging" ]; then
    mkdir -p "$renewal"
    rsync -a --delete Package.swift Sources Tests Resources iOS Scripts "$renewal/"
fi

if [ "${NO_LAUNCH:-}" = "1" ]; then
    echo "Done."
    exit 0
fi

echo "== opening"
xcrun devicectl device process launch --device "$device" "$bundle_id" >/dev/null 2>&1 && echo "Done." || \
    echo "Installed. If it will not open: Settings > General > VPN & Device Management > trust your developer certificate."
