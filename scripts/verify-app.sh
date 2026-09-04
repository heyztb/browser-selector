#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
app_path=${1:-"$project_dir/.build/Browser Selector.app"}
plist="$app_path/Contents/Info.plist"
executable="$app_path/Contents/MacOS/BrowserSelector"

test -d "$app_path"
test -x "$executable"
test -f "$app_path/Contents/Resources/AppIcon.icns"
plutil -lint "$plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")" = "io.github.heyztb.BrowserSelector"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist")" = "14.0"
/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes' "$plist" | grep -q http
/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes' "$plist" | grep -q https
/usr/libexec/PlistBuddy -c 'Print :CFBundleDocumentTypes:0:LSItemContentTypes' "$plist" | grep -q public.html
/usr/libexec/PlistBuddy -c 'Print :CFBundleDocumentTypes:0:CFBundleTypeExtensions' "$plist" | grep -q html
codesign --verify --deep --strict --verbose=2 "$app_path"
lipo -archs "$executable"

echo "Verified $app_path"
