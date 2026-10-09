#!/bin/zsh
# Builds build/One-Percent-v<version>.dmg: the classic installer window with the app on the left,
# an Applications shortcut on the right and a "drag it across" background.
#
# Uses only what ships with macOS (hdiutil + a short Finder script for the window layout), so the
# first run may ask to let your terminal control Finder. The art lives in
# Resources/dmg-background.png (regenerate with Scripts/make-dmg-background.py).
set -euo pipefail

project_dir="${0:A:h:h}"
cd "$project_dir"

app_name="One Percent"
volume_name="$app_name"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
app_bundle="$project_dir/build/$app_name.app"
staging="$project_dir/build/dmg-staging"
rw_dmg="$project_dir/build/dmg-rw.dmg"
final_dmg="$project_dir/build/One-Percent-v$version.dmg"
mount_point="/Volumes/$volume_name"

# Window geometry (points). Icon centres must match Scripts/make-dmg-background.py.
window_left=200
window_top=120
content_width=660
content_height=400
title_bar=28
app_x=170
apps_x=490
icons_y=185

echo "==> Building $app_name $version"
"$project_dir/Scripts/build-app.sh" >/dev/null
codesign --force --deep --sign - "$app_bundle"

echo "==> Staging"
if [ -d "$mount_point" ]; then hdiutil detach "$mount_point" -force >/dev/null 2>&1 || true; fi
rm -rf "$staging" "$rw_dmg" "$final_dmg"
mkdir -p "$staging/.background"
ditto "$app_bundle" "$staging/$app_name.app"
ln -s /Applications "$staging/Applications"
cp Resources/dmg-background.png "$staging/.background/background.png"

echo "==> Creating disk image"
hdiutil create -srcfolder "$staging" -volname "$volume_name" -fs HFS+ -format UDRW -size 32m "$rw_dmg" >/dev/null
device="$(hdiutil attach "$rw_dmg" -readwrite -noverify -noautoopen | awk '/Apple_HFS/ {print $1; exit}')"
trap 'hdiutil detach "$device" -force >/dev/null 2>&1 || true' EXIT

echo "==> Laying out the window"
window_right=$((window_left + content_width))
window_bottom=$((window_top + content_height + title_bar))
osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$volume_name"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {$window_left, $window_top, $window_right, $window_bottom}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:background.png"
    set position of item "$app_name.app" of container window to {$app_x, $icons_y}
    set position of item "Applications" of container window to {$apps_x, $icons_y}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT

# Volume icon last: Finder removes it again when it is already present while the window is laid out.
cp Resources/AppIcon.icns "$mount_point/.VolumeIcon.icns"
SetFile -a C "$mount_point"
SetFile -a V "$mount_point/.VolumeIcon.icns" 2>/dev/null || true

echo "==> Compressing"
sync
hdiutil detach "$device" >/dev/null 2>&1 || { sleep 2; hdiutil detach "$device" -force >/dev/null; }
trap - EXIT
hdiutil convert "$rw_dmg" -format UDZO -imagekey zlib-level=9 -o "$final_dmg" >/dev/null
rm -rf "$rw_dmg" "$staging"

echo "Created $final_dmg ($(du -h "$final_dmg" | cut -f1))"
