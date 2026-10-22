#!/bin/zsh
# Runs the opt-in check against your Supabase project (Config/Local.xcconfig): a goal travels
# between two simulated devices and the live channel announces a change. Asks for the email and
# password on screen, so the password never lands in the shell history.
#
#     zsh Scripts/test-live.sh
#
# The scratch path avoids the "%" in the project folder name, which breaks Swift's build cache.
set -euo pipefail

cd "${0:A:h:h}"
host="$(python3 Scripts/read-config.py ONEPERCENT_SUPABASE_HOST)"
key="$(python3 Scripts/read-config.py ONEPERCENT_SUPABASE_KEY)"
if [ -z "$host" ] || [ -z "$key" ]; then
    echo "No Supabase project set. Fill in ONEPERCENT_SUPABASE_HOST and _KEY in Config/Local.xcconfig."
    exit 1
fi
read "email?Email: "
read -s "password?Password: "
echo

ONEPERCENT_SUPABASE_HOST="$host" ONEPERCENT_SUPABASE_KEY="$key" \
ONEPERCENT_LIVE_EMAIL="$email" ONEPERCENT_LIVE_PASSWORD="$password" \
    swift test --scratch-path "${TMPDIR%/}/one-percent-spm-test" --filter LiveSupabaseTests
