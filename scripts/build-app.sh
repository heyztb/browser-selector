#!/bin/zsh
# Copyright (c) 2026 Zach Blake
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
configuration=${1:-debug}
architecture=${2:-native}
app_path="$project_dir/.build/Browser Selector.app"

case "$configuration" in
  debug|release) ;;
  *) echo "usage: $0 [debug|release] [native|universal]" >&2; exit 64 ;;
esac

case "$architecture" in
  native)
    build_arguments=(-c "$configuration")
    ;;
  universal)
    build_arguments=(-c "$configuration" --arch arm64 --arch x86_64)
    ;;
  *) echo "usage: $0 [debug|release] [native|universal]" >&2; exit 64 ;;
esac

cd "$project_dir"
if [[ "$configuration" == "release" ]]; then
  # Keep checkout paths out of the executable. In particular, Swift's linker
  # debug map includes an absolute swiftmodule path even with prefix mapping.
  build_arguments+=(
    -Xswiftc -debug-prefix-map -Xswiftc "$project_dir=/BrowserSelector"
    -Xswiftc -file-prefix-map -Xswiftc "$project_dir=/BrowserSelector"
    -Xlinker -reproducible
    -Xlinker -S
  )
fi
swift build "${build_arguments[@]}"
binary_dir=$(swift build "${build_arguments[@]}" --show-bin-path)

if [[ "$app_path" != "$project_dir/.build/Browser Selector.app" ]]; then
  echo "refusing to replace unexpected app path: $app_path" >&2
  exit 1
fi
rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
ditto "$binary_dir/BrowserSelector" "$app_path/Contents/MacOS/BrowserSelector"
ditto "$project_dir/Resources/Info.plist" "$app_path/Contents/Info.plist"
ditto "$project_dir/Resources/AppIcon.icns" "$app_path/Contents/Resources/AppIcon.icns"
ditto "$project_dir/LICENSE" "$app_path/Contents/Resources/LICENSE"
ditto "$project_dir/Resources/LicenseNotice.txt" "$app_path/Contents/Resources/LicenseNotice.txt"
source_url="https://github.com/heyztb/browser-selector"
if [[ -n "${RELEASE_VERSION:-}" ]]; then
  source_url="$source_url/tree/v$RELEASE_VERSION"
fi
printf '\nSource code and build instructions: %s\n' "$source_url" >> "$app_path/Contents/Resources/LicenseNotice.txt"

if [[ -n "${RELEASE_VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $RELEASE_VERSION" "$app_path/Contents/Info.plist"
fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$app_path/Contents/Info.plist"
fi

signing_identity=${CODE_SIGN_IDENTITY:--}
if [[ "$signing_identity" == "-" ]]; then
  codesign --force --sign - "$app_path"
else
  codesign --force --options runtime --timestamp --sign "$signing_identity" "$app_path"
fi

# Record the environment outside the bundle: machine-specific information must
# not become part of the payload that independent builders compare.
{
  echo "configuration=$configuration"
  echo "architecture=$architecture"
  echo "version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
  echo "build_number=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_path/Contents/Info.plist")"
  echo "developer_dir=$(xcode-select -p)"
  echo "DEVELOPER_DIR=${DEVELOPER_DIR:-}"
  xcodebuild -version
  swift --version 2>&1
  echo "sdk_path=$(xcrun --sdk macosx --show-sdk-path)"
  echo "sdk_version=$(xcrun --sdk macosx --show-sdk-version)"
  echo "sdk_build=$(xcrun --sdk macosx --show-sdk-build-version)"
  sw_vers
  if [[ -d "$project_dir/.git" || -f "$project_dir/.git" ]]; then
    echo "source_commit=$(git rev-parse HEAD)"
    git status --porcelain
  fi
} > "$project_dir/.build/build-info.txt"

echo "$app_path"
