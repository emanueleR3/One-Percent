#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
cd "$project_dir"

scratch_dir="${TMPDIR%/}/one-percent-spm-build"
swift build --configuration release --scratch-path "$scratch_dir"
binary_dir="$(swift build --configuration release --scratch-path "$scratch_dir" --show-bin-path)"
app_bundle="$project_dir/build/One Percent.app"

mkdir -p "$app_bundle/Contents/MacOS"
cp "$binary_dir/OnePercent" "$app_bundle/Contents/MacOS/OnePercent"
cp "$project_dir/Resources/Info.plist" "$app_bundle/Contents/Info.plist"

echo "Created $app_bundle"
