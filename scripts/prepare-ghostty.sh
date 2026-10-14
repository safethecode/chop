#!/bin/bash
set -euo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_directory="$(cd -- "$script_directory/.." && pwd)"
cd "$project_directory"

ghostty_revision=6d2dd585a5d87fa745d48188dd096ca6e63014d0
ghostty_sha256=684c62a62ee4e90d4238be4c8e039751b57ffa5ddb34c8990104761c0918916c
zig_version=0.14.1
case "$(uname -m)" in
  arm64)
    zig_arch=aarch64
    zig_sha256=39f3dc5e79c22088ce878edc821dedb4ca5a1cd9f5ef915e9b3cc3053e8faefa
    ;;
  x86_64)
    zig_arch=x86_64
    zig_sha256=b0f8bdfb9035783db58dd6c19d7dea89892acc3814421853e5752fe4573e5f43
    ;;
  *) echo 'Chop requires an Intel or Apple Silicon Mac.' >&2; exit 1 ;;
esac

mkdir -p .cache/downloads .cache/toolchains Dependencies
build_fingerprint="$(cat scripts/prepare-ghostty.sh scripts/ghostty-xcrun.sh scripts/ghostty-libtool.sh Dependencies/ghostty-config.patch; uname -m; xcodebuild -version; echo "${CHOP_GHOSTTY_SDKROOT:-auto}")"
build_fingerprint="$(echo "$build_fingerprint" | shasum -a 256 | cut -d ' ' -f 1)"
if [[ -f Dependencies/.ghostty-build ]] &&
  [[ "$(cat Dependencies/.ghostty-build)" == "$build_fingerprint" ]] &&
  [[ -d Dependencies/GhosttyKit.xcframework && -d Dependencies/ghostty-resources ]]; then
  exit 0
fi

download() {
  local url="$1" destination="$2" checksum="$3"
  if [[ ! -f "$destination" ]]; then
    curl --fail --location --retry 3 --silent --show-error "$url" -o "$destination.part"
    mv "$destination.part" "$destination"
  fi
  echo "$checksum  $destination" | shasum -a 256 -c -
}

zig_archive=".cache/downloads/zig-$zig_arch-$zig_version.tar.xz"
download "https://ziglang.org/download/$zig_version/zig-$zig_arch-macos-$zig_version.tar.xz" "$zig_archive" "$zig_sha256"
zig_directory="$project_directory/.cache/toolchains/zig-$zig_version"
if [[ ! -x "$zig_directory/zig" ]]; then
  mkdir -p "$zig_directory"
  tar -xJf "$zig_archive" --strip-components=1 -C "$zig_directory"
fi

download "https://codeload.github.com/ghostty-org/ghostty/tar.gz/$ghostty_revision" .cache/downloads/ghostty.tar.gz "$ghostty_sha256"
source_fingerprint="$(echo "$ghostty_revision $(shasum -a 256 Dependencies/ghostty-config.patch)" | shasum -a 256 | cut -d ' ' -f 1)"
if [[ ! -f .cache/ghostty/.chop-source ]] || [[ "$(cat .cache/ghostty/.chop-source)" != "$source_fingerprint" ]]; then
  rm -rf .cache/ghostty
  mkdir -p .cache/ghostty
  tar -xzf .cache/downloads/ghostty.tar.gz --strip-components=1 -C .cache/ghostty
  patch -d .cache/ghostty -p1 < Dependencies/ghostty-config.patch
  echo "$source_fingerprint" > .cache/ghostty/.chop-source
fi

if ! /usr/bin/xcrun metal --version >/dev/null 2>&1; then
  xcodebuild -downloadComponent MetalToolchain
fi

# Zig 0.14 predates the Xcode 26 arm64 libSystem stub layout. Keep modern
# headers (CoreVideo needs them), but use an older installed stub for Zig's
# host helpers. This overlay is local to this build; no SDK files are edited.
selected_sdk="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
if [[ -z "${CHOP_GHOSTTY_SDKROOT:-}" ]] && [[ "$(uname -m)" == arm64 ]] &&
  ! /usr/bin/head -n 4 "$selected_sdk/usr/lib/libSystem.B.tbd" | /usr/bin/grep -q 'arm64-macos'; then
  compatible_sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
  if [[ ! -f "$compatible_sdk/usr/lib/libSystem.B.tbd" ]] ||
    ! /usr/bin/head -n 4 "$compatible_sdk/usr/lib/libSystem.B.tbd" | /usr/bin/grep -q 'arm64-macos'; then
    echo 'Zig needs a compatible libSystem stub. Install Command Line Tools or set CHOP_GHOSTTY_SDKROOT to a compatible SDK overlay.' >&2
    exit 1
  fi
  overlay="$project_directory/.cache/macos-sdk"
  mkdir -p "$overlay/usr/lib"
  ln -sfn "$selected_sdk/System" "$overlay/System"
  ln -sfn "$selected_sdk/usr/include" "$overlay/usr/include"
  for entry in "$selected_sdk"/usr/lib/*; do
    ln -sfn "$entry" "$overlay/usr/lib/$(basename "$entry")"
  done
  for stub in libSystem.tbd libSystem.B.tbd; do
    ln -sfn "$compatible_sdk/usr/lib/$stub" "$overlay/usr/lib/$stub"
  done
  export CHOP_GHOSTTY_SDKROOT="$overlay"
fi

mkdir -p .cache/bin
ln -sf "$project_directory/scripts/ghostty-xcrun.sh" .cache/bin/xcrun
ln -sf "$project_directory/scripts/ghostty-libtool.sh" .cache/bin/chop-libtool
export PATH="$project_directory/.cache/bin:$PATH"
export ZIG_GLOBAL_CACHE_DIR="$project_directory/.cache/zig"

# These pinned transitive dependencies use Zig's Git transport upstream.
# Fetch equivalent archives with curl and verify Zig's exact content hash;
# this avoids Codeberg capability negotiation failures on hosted runners.
fetch_package() {
  local url="$1" archive="$2" expected="$3" actual
  [[ -d "$ZIG_GLOBAL_CACHE_DIR/p/$expected" ]] && return
  curl --fail --location --retry 3 --silent --show-error "$url" -o "$archive"
  actual="$("$zig_directory/zig" fetch "$archive")"
  if [[ "$actual" != "$expected" ]]; then
    echo "Unexpected Zig package hash for $archive" >&2
    exit 1
  fi
}
fetch_package https://codeberg.org/atman/zg/archive/4a002763419a34d61dcbb1f415821b83b9bf8ddc.tar.gz \
  "$project_directory/.cache/downloads/zg.tar.gz" zg-0.13.4-AAAAAGiZ7QLz4pvECFa_wG4O4TP4FLABHHbemH2KakWM
fetch_package https://codeload.github.com/TUSF/zigimg/tar.gz/31268548fe3276c0e95f318a6c0d2ab10565b58d \
  "$project_directory/.cache/downloads/zigimg.tar.gz" zigimg-0.1.0-lly-O6N2EABOxke8dqyzCwhtUCAafqP35zC7wsZ4Ddxj
(
  cd .cache/ghostty
  "$zig_directory/zig" build -Doptimize=ReleaseFast -Demit-macos-app=false \
    -Demit-xcframework=true -Dxcframework-target=native -Demit-docs=false \
    -Demit-terminfo=true -Demit-themes=false -Dsentry=false -Di18n=false \
    -Dversion-string=1.2.3 -j"${CHOP_BUILD_JOBS:-4}"
)

rm -rf Dependencies/GhosttyKit.xcframework Dependencies/ghostty-resources
cp -R .cache/ghostty/macos/GhosttyKit.xcframework Dependencies/GhosttyKit.xcframework
if ! /usr/bin/nm -g Dependencies/GhosttyKit.xcframework/macos-*/libghostty-fat.a | /usr/bin/grep ' T _ghostty_init$' >/dev/null; then
  echo 'libghostty is missing its exported API.' >&2
  exit 1
fi
mkdir -p Dependencies/ghostty-resources
cp -R .cache/ghostty/zig-out/share/. Dependencies/ghostty-resources/
mkdir -p Dependencies/ghostty-resources/licenses
while IFS= read -r notice; do
  relative="${notice#"$project_directory/.cache/"}"
  destination="$project_directory/Dependencies/ghostty-resources/licenses/$relative"
  mkdir -p "$(dirname "$destination")"
  cp "$notice" "$destination"
done < <(find "$project_directory/.cache/ghostty/pkg" "$project_directory/.cache/ghostty/vendor" "$ZIG_GLOBAL_CACHE_DIR/p" \
  -type f \( -iname '*license*' -o -iname '*copying*' -o -iname '*notice*' -o -iname '*ofl*' \))
cp .cache/ghostty/LICENSE Dependencies/ghostty-resources/licenses/Ghostty-LICENSE
echo "$build_fingerprint" > Dependencies/.ghostty-build
