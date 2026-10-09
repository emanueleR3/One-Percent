#!/bin/zsh
# Renews the iPhone app's 7-day signature by itself, every 6 days, while you are logged in to the Mac.
#
#     zsh Scripts/iphone-autorefresh.sh install    # turn it on (and renew once, right away)
#     zsh Scripts/iphone-autorefresh.sh status     # when it last ran and when it is next due
#     zsh Scripts/iphone-autorefresh.sh run        # renew now, ignoring the 6-day wait
#     zsh Scripts/iphone-autorefresh.sh remove     # turn it off
#
# It is a launchd agent: a small job in ~/Library/LaunchAgents that checks every hour and acts
# only when the app was last installed 6 days ago (see auto-install-iphone.sh). It renews a copy
# of the code that was last installed with install-iphone.sh, so new code reaches the phone only
# through that script, never behind your back. Needs, once:
# Xcode > Window > Devices and Simulators > your iPhone > "Connect via network", so the Mac can
# reach the phone over Wi-Fi without a cable.
set -euo pipefail

root="${0:A:h:h}"
label="com.example.onepercent.iphone-refresh"
plist="$HOME/Library/LaunchAgents/$label.plist"
state="$HOME/Library/Application Support/One Percent iPhone Refresh"
mirror="$state/source"
log="$HOME/Library/Logs/OnePercent-iphone-refresh.log"
domain="gui/$(id -u)"

case "${1:-status}" in
install)
    mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs" "$mirror"
    # macOS keeps background jobs out of ~/Desktop, so the job works on a copy of the sources.
    # Every install-iphone.sh run that works refreshes that copy; it always matches the phone.
    if [ ! -f "$mirror/Package.swift" ]; then
        (cd "$root" && rsync -a --delete Package.swift Sources Tests Resources iOS Scripts "$mirror/")
    fi
    cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$label</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/zsh</string>
        <string>$mirror/Scripts/auto-install-iphone.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>3600</integer>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin</string>
    </dict>
    <key>StandardOutPath</key>
    <string>$log</string>
    <key>StandardErrorPath</key>
    <string>$log</string>
    <key>ProcessType</key>
    <string>Background</string>
</dict>
</plist>
EOF
    launchctl bootout "$domain/$label" 2>/dev/null || true
    launchctl bootstrap "$domain" "$plist"
    echo "On. It checks every hour and renews the iPhone app when 6 days have passed."
    echo "Log: $log"
    ;;
remove)
    launchctl bootout "$domain/$label" 2>/dev/null || true
    rm -f "$plist"
    echo "Off."
    ;;
run)
    rm -f "$state/last-install"      # makes it due; a failed run leaves it due, so it keeps retrying
    launchctl kickstart -k "$domain/$label"
    echo "Started. Follow it with: tail -f \"$log\""
    ;;
status)
    if launchctl print "$domain/$label" >/dev/null 2>&1; then echo "Job: on"; else echo "Job: off"; fi
    if [ -f "$state/last-install" ]; then
        last="$(cat "$state/last-install")"
        echo "Last install: $(date -r "$last" '+%a %d %b %H:%M')"
        echo "Next renewal: $(date -r $(( last + 6 * 86400 )) '+%a %d %b %H:%M') or the first hour after that when the iPhone can be reached"
    else
        echo "No install recorded yet."
    fi
    [ -f "$log" ] && { echo "--- last lines of $log"; tail -5 "$log"; }
    ;;
*)
    echo "Usage: zsh Scripts/iphone-autorefresh.sh install|remove|run|status"
    exit 1
    ;;
esac
