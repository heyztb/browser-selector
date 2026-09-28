#!/bin/zsh
# Copyright (c) 2026 Zach Blake
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

if [[ $# -ne 2 || ! "$1" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' || ! "$2" =~ '^[0-9]+$' ]]; then
  echo "usage: $0 VERSION BUILD_NUMBER (for example: 0.1.0 1)" >&2
  exit 64
fi

script_dir=${0:A:h}
project_dir=${script_dir:h}
version=$1
build_number=$2
app_path="$project_dir/.build/Browser Selector.app"
release_dir="$project_dir/.build/releases"
dmg_path="$release_dir/Browser-Selector-$version.dmg"
staging_dir=$(mktemp -d)
trap 'rm -rf "$staging_dir"' EXIT

if [[ -e "$dmg_path" || -e "$dmg_path.sha256" ]]; then
  echo "refusing to overwrite existing release output for $version" >&2
  exit 1
fi

RELEASE_VERSION=$version BUILD_NUMBER=$build_number CODE_SIGN_IDENTITY=- \
  "$script_dir/build-app.sh" release universal
"$script_dir/verify-app.sh" "$app_path"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")" = "$version"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_path/Contents/Info.plist")" = "$build_number"

ditto "$app_path" "$staging_dir/Browser Selector.app"
ln -s /Applications "$staging_dir/Applications"
mkdir -p "$release_dir"
hdiutil create -volname "Browser Selector $version" -srcfolder "$staging_dir" \
  -format UDZO -ov "$dmg_path"
hdiutil verify "$dmg_path"
(cd "$release_dir" && shasum -a 256 "${dmg_path:t}" > "${dmg_path:t}.sha256")

echo "Created $dmg_path"
cat "$dmg_path.sha256"
