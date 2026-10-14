#!/bin/bash
set -euo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_directory="$(cd -- "$script_directory/.." && pwd)"

cd "$project_directory"
xcrun swift-format lint --strict --recursive Package.swift Sources Tests
for script in scripts/*.sh; do
  bash -n "$script"
done
plutil -lint Resources/Info.plist
"$script_directory/build-app.sh" release
codesign --verify --strict "$project_directory/build/release/Chop.app"
swift test
echo "All checks passed."
