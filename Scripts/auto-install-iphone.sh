#!/bin/zsh
# The job behind Scripts/iphone-autorefresh.sh. It runs every hour but does nothing until the
# iPhone app was last installed 6 days ago (a free signature lasts 7): then it rebuilds, signs and
# installs it again without opening it, and tries again every hour until it works.
#
# Why hourly checks and not "once every 6 days": the Mac may be asleep, the iPhone out of reach
# or locked at the moment it is due. A missed run is simply retried, not postponed by 6 days.
#
#     REFRESH_DAYS=6 zsh Scripts/auto-install-iphone.sh
set -uo pipefail

cd "${0:A:h:h}"
days="${REFRESH_DAYS:-6}"
state="$HOME/Library/Application Support/One Percent iPhone Refresh"
mkdir -p "$state"

now="$(date +%s)"
last="$(cat "$state/last-install" 2>/dev/null || echo 0)"
age=$(( now - last ))
(( age >= days * 86400 )) || exit 0

# One run at a time: a build can outlast the hour.
lock="$state/running.lock"
if ! mkdir "$lock" 2>/dev/null; then
    held="$(stat -f %m "$lock" 2>/dev/null || echo "$now")"
    (( now - held > 3600 )) && rmdir "$lock" 2>/dev/null     # a crashed run left it behind
    exit 0
fi
trap 'rmdir "$lock" 2>/dev/null' EXIT

notify() {
    /usr/bin/osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1 || true
}

if (( last == 0 )); then since="never installed"; else since="last install $(( age / 3600 )) h ago"; fi
echo "== $(date '+%F %T') refreshing the iPhone app ($since)"
if NO_LAUNCH=1 zsh Scripts/install-iphone.sh; then
    rm -f "$state/last-warning"
    notify "One Percent" "iPhone app renewed for another 7 days."
    exit 0
fi

# Failures are quiet at first (the phone is probably just away). Once the signature is close to
# running out, say so, but no more than every 12 hours.
echo "== failed"
overdue=$(( age - days * 86400 ))
if (( overdue >= 12 * 3600 )); then
    warned="$(cat "$state/last-warning" 2>/dev/null || echo 0)"
    if (( now - warned >= 12 * 3600 )); then
        echo "$now" >"$state/last-warning"
        notify "One Percent" "Could not renew the iPhone app. Unlock the iPhone near the Mac, or run install-iphone.sh."
    fi
fi
exit 1
