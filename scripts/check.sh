#!/bin/bash
set -euo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_directory="$(cd -- "$script_directory/.." && pwd)"

cd "$project_directory"
xcrun swift-format lint --strict --recursive Package.swift Sources Tests scripts/generate-app-icon.swift
for script in scripts/*.sh; do
  bash -n "$script"
done
plutil -lint Resources/Info.plist
"$script_directory/build-app.sh" release
codesign --verify --strict "$project_directory/build/release/Chop.app"
icon_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$project_directory/build/release/Chop.app/Contents/Info.plist")"
iconset_path="$project_directory/build/icon-check.iconset"
rm -rf -- "$iconset_path"
iconutil -c iconset "$project_directory/build/release/Chop.app/Contents/Resources/$icon_name" -o "$iconset_path"
# AppKit windows and the terminal engine share process state across async UI tests.
swift test --no-parallel
echo "All checks passed."
