#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
cd "$project_dir"

scratch_dir="${TMPDIR%/}/one-percent-spm-build"
swift build --configuration release --scratch-path "$scratch_dir"
binary_dir="$(swift build --configuration release --scratch-path "$scratch_dir" --show-bin-path)"
app_bundle="$project_dir/build/One Percent.app"

mkdir -p "$app_bundle/Contents/MacOS"
mkdir -p "$app_bundle/Contents/Resources"
cp "$binary_dir/OnePercent" "$app_bundle/Contents/MacOS/OnePercent"
cp "$project_dir/Resources/Info.plist" "$app_bundle/Contents/Info.plist"
if [ -f "$project_dir/Resources/AppIcon.icns" ]; then
    cp "$project_dir/Resources/AppIcon.icns" "$app_bundle/Contents/Resources/AppIcon.icns"
fi
if [ -f "$project_dir/Resources/AppIcon.png" ]; then
    cp "$project_dir/Resources/AppIcon.png" "$app_bundle/Contents/Resources/AppIcon.png"
fi

touch "$app_bundle"
echo "Created $app_bundle"
