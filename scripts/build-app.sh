#!/bin/zsh
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

echo "$app_path"
