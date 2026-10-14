#!/bin/bash
set -euo pipefail

# Zig 0.14 cannot read the arm64 symbol layout in newer Xcode 26 SDKs.
# Scope an optional compatible SDK to Ghostty's Zig build only. Metal tooling
# and every other xcrun invocation continue to use the selected Xcode.
if [[ -n "${CHOP_GHOSTTY_SDKROOT:-}" ]] &&
  [[ "$*" == '--sdk macosx --show-sdk-path' || "$*" == '--show-sdk-path' ]]; then
  echo "$CHOP_GHOSTTY_SDKROOT"
else
  exec /usr/bin/xcrun "$@"
fi
