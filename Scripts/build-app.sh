#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
cd "$project_dir"

scratch_dir="${TMPDIR%/}/one-percent-spm-build"
# Keep this Mac's folders (and so your username) out of the app: source paths are recorded
# relative to the project, and the debug symbols that point at build files are stripped below.
build_flags=(--configuration release --scratch-path "$scratch_dir" -Xswiftc -file-prefix-map -Xswiftc "$project_dir=.")
swift build "${build_flags[@]}"
binary_dir="$(swift build "${build_flags[@]}" --show-bin-path)"
app_bundle="$project_dir/build/One Percent.app"

mkdir -p "$app_bundle/Contents/MacOS"
mkdir -p "$app_bundle/Contents/Resources"
cp "$binary_dir/OnePercent" "$app_bundle/Contents/MacOS/OnePercent"
strip -S -x "$app_bundle/Contents/MacOS/OnePercent"
cp "$project_dir/Resources/Info.plist" "$app_bundle/Contents/Info.plist"
if [ -f "$project_dir/Resources/AppIcon.icns" ]; then
    cp "$project_dir/Resources/AppIcon.icns" "$app_bundle/Contents/Resources/AppIcon.icns"
fi
if [ -f "$project_dir/Resources/AppIcon.png" ]; then
    cp "$project_dir/Resources/AppIcon.png" "$app_bundle/Contents/Resources/AppIcon.png"
fi

for lproj in "$project_dir"/Resources/*.lproj; do
    [ -d "$lproj" ] || continue
    rm -rf "$app_bundle/Contents/Resources/${lproj:t}"
    cp -R "$lproj" "$app_bundle/Contents/Resources/${lproj:t}"
done

# Cloud sync needs a Supabase project: its host and publishable key go into the Info.plist from
# Config/Local.xcconfig. Without them the app works fully, on this Mac only.
plist="$app_bundle/Contents/Info.plist"
supabase_host="$(python3 "$project_dir/Scripts/read-config.py" ONEPERCENT_SUPABASE_HOST)"
supabase_key="$(python3 "$project_dir/Scripts/read-config.py" ONEPERCENT_SUPABASE_KEY)"
if [ -n "$supabase_host" ] && [ -n "$supabase_key" ]; then
    /usr/libexec/PlistBuddy -c "Add :OnePercentSupabaseHost string $supabase_host" "$plist"
    /usr/libexec/PlistBuddy -c "Add :OnePercentSupabaseKey string $supabase_key" "$plist"
    sync_note="cloud sync on"
else
    sync_note="cloud sync off: no Supabase project in Config/Local.xcconfig"
fi

touch "$app_bundle"
echo "Created $app_bundle ($sync_note)"
