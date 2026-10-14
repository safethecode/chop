#!/bin/bash
set -euo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_directory="$(cd -- "$script_directory/.." && pwd)"
configuration="${1:-debug}"

if [[ $# -gt 1 ]] || [[ "$configuration" != debug && "$configuration" != release ]]; then
  echo "Usage: $0 [debug|release]" >&2
  exit 2
fi

cd "$project_directory"
"$script_directory/prepare-ghostty.sh"
swift build --configuration "$configuration"
binary_directory="$(swift build --configuration "$configuration" --show-bin-path)"
app_path="$project_directory/build/$configuration/Chop.app"

# Only replace this script's generated app bundle after the build succeeds.
rm -rf -- "$app_path"
mkdir -p "$app_path/Contents/MacOS"
cp "$binary_directory/Chop" "$app_path/Contents/MacOS/Chop"
cp "$project_directory/Resources/Info.plist" "$app_path/Contents/Info.plist"
mkdir -p "$app_path/Contents/Resources"
cp "$project_directory/Resources/terminal.conf" "$app_path/Contents/Resources/terminal.conf"
cp -R "$project_directory/Dependencies/ghostty-resources/." "$app_path/Contents/Resources/"

# Local development signature; release distribution will need Developer ID signing.
codesign --force --sign - "$app_path"
echo "Built $app_path"
