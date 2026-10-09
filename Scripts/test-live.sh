#!/bin/zsh
# Runs the opt-in check against the real Supabase project: a goal travels between two simulated
# devices and the live channel announces a change. Asks for the email and password on screen, so
# the password never lands in the shell history.
#
#     zsh Scripts/test-live.sh
#
# The scratch path avoids the "%" in the project folder name, which breaks Swift's build cache.
set -euo pipefail

cd "${0:A:h:h}"
read "email?Email: "
read -s "password?Password: "
echo

ONEPERCENT_LIVE_EMAIL="$email" ONEPERCENT_LIVE_PASSWORD="$password" \
    swift test --scratch-path "${TMPDIR%/}/one-percent-spm-test" --filter LiveSupabaseTests
