#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
source_app="$project_dir/.build/Browser Selector.app"
destination_app="/Applications/Browser Selector.app"

"$script_dir/build-app.sh" debug native
ditto "$source_app" "$destination_app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$destination_app"
open "$destination_app"

echo "Installed $destination_app"
