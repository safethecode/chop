#!/bin/bash
set -euo pipefail

# Newer Apple libtool silently drops unaligned members in Zig 0.14 archives.
# Extract each archive to loose objects first, keeping duplicate member names
# in separate directories, then let Apple's libtool create a padded archive.
if [[ $# -lt 4 || "$1" != -static || "$2" != -o ]]; then
  echo 'Expected: chop-libtool -static -o output.a input.a ...' >&2
  exit 2
fi
output="$3"
shift 3
temporary="$(mktemp -d "$(dirname "$output")/chop-libtool.XXXXXX")"
trap 'rm -rf -- "$temporary"' EXIT
objects=()
index=0
for archive in "$@"; do
  index=$((index + 1))
  directory="$temporary/$index"
  mkdir -p "$directory"
  (cd "$directory" && /usr/bin/ar -x "$archive")
  for object in "$directory"/*; do
    [[ -f "$object" ]] || continue
    [[ "$object" == */__.SYMDEF* ]] && continue
    chmod u+rw "$object"
    objects+=("$object")
  done
done
/usr/bin/libtool -static -o "$output" "${objects[@]}"
