#!/usr/bin/env bash
# Rebuilds the static libraries ogg_opus_player vendors for macOS from
# source, without LTO. The published plugin ships libogg/libopus/
# libopusenc/libopusfile archives whose object files are pure LLVM
# bitcode (-flto) produced by a compiler newer than the one bundled with
# the Xcode version this project builds with; the macOS linker then
# fails with "Invalid bitcode version" when it tries to translate them.
# Compiling the same library versions locally, with plain -O2 instead of
# -flto, produces drop-in replacement archives the linker can read
# directly, with the same public API and ABI.
set -euo pipefail

VERSION_OGG=1.3.5
VERSION_OPUS=1.3.1
VERSION_OPUSENC=0.2.1
VERSION_OPUSFILE=0.12
MACOS_MIN=10.15

PUB_CACHE_DIR="${PUB_CACHE:-$HOME/.pub-cache}"
PACKAGE_DIR=$(find "$PUB_CACHE_DIR/hosted/pub.dev" -maxdepth 1 -iname 'ogg_opus_player-*' -type d | sort -V | tail -n 1)
if [ -z "$PACKAGE_DIR" ]; then
  echo "::error::ogg_opus_player package not found under $PUB_CACHE_DIR; run flutter pub get first."
  exit 1
fi

TARGETS=()
if [ -d "$PACKAGE_DIR/darwin/Libs" ]; then
  TARGETS+=("$PACKAGE_DIR/darwin/Libs")
fi
for xc in "$PACKAGE_DIR/darwin/ogg_opus_player/Frameworks" "$PACKAGE_DIR/darwin/Frameworks"; do
  if [ -d "$xc" ]; then
    for dir in "$xc"/*.xcframework/macos-arm64_x86_64; do
      [ -d "$dir" ] && TARGETS+=("$dir")
    done
  fi
done
if [ "${#TARGETS[@]}" -eq 0 ]; then
  echo "::error::Could not find a macOS Libs directory inside $PACKAGE_DIR/darwin."
  exit 1
fi

WORKDIR="${RUNNER_TEMP:-/tmp}/opus-macos-build"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR/src"
cd "$WORKDIR/src"

if ! command -v pkg-config >/dev/null 2>&1; then
  brew install pkg-config
fi

curl_retry() {
  curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 "$@"
}

curl_retry "https://downloads.xiph.org/releases/ogg/libogg-${VERSION_OGG}.tar.gz" -o libogg.tar.gz
curl_retry "https://downloads.xiph.org/releases/opus/opus-${VERSION_OPUS}.tar.gz" -o opus.tar.gz
curl_retry "https://downloads.xiph.org/releases/opus/libopusenc-${VERSION_OPUSENC}.tar.gz" -o libopusenc.tar.gz
curl_retry "https://downloads.xiph.org/releases/opus/opusfile-${VERSION_OPUSFILE}.tar.gz" -o opusfile.tar.gz

tar xzf libogg.tar.gz
tar xzf opus.tar.gz
tar xzf libopusenc.tar.gz
tar xzf opusfile.tar.gz

build_one_arch() {
  local arch="$1" host="$2" prefix="$3"
  local sdk
  sdk=$(xcrun --sdk macosx --show-sdk-path)
  mkdir -p "$prefix"
  export CC=clang
  export CFLAGS="-arch $arch -mmacosx-version-min=$MACOS_MIN -isysroot $sdk -O2 -fPIC -g"
  export LDFLAGS="-arch $arch -mmacosx-version-min=$MACOS_MIN -isysroot $sdk"
  export PKG_CONFIG_PATH="$prefix/lib/pkgconfig"
  export CPPFLAGS="-I$prefix/include"
  export LIBRARY_PATH="$prefix/lib"

  (cd "$WORKDIR/src/libogg-${VERSION_OGG}" && make distclean >/dev/null 2>&1 || true
    ./configure --host="$host" --prefix="$prefix" --disable-shared --enable-static --with-pic
    make -j"$(sysctl -n hw.ncpu)"
    make install)

  (cd "$WORKDIR/src/opus-${VERSION_OPUS}" && make distclean >/dev/null 2>&1 || true
    ./configure --host="$host" --prefix="$prefix" --disable-shared --enable-static --with-pic --disable-doc --disable-extra-programs
    make -j"$(sysctl -n hw.ncpu)"
    make install)

  (cd "$WORKDIR/src/libopusenc-${VERSION_OPUSENC}" && make distclean >/dev/null 2>&1 || true
    ./configure --host="$host" --prefix="$prefix" --disable-shared --enable-static --with-pic --disable-doc
    make -j"$(sysctl -n hw.ncpu)"
    make install)

  (cd "$WORKDIR/src/opusfile-${VERSION_OPUSFILE}" && make distclean >/dev/null 2>&1 || true
    ./configure --host="$host" --prefix="$prefix" --disable-shared --enable-static --with-pic --disable-http --disable-doc --disable-examples
    make -j"$(sysctl -n hw.ncpu)"
    make install)

  unset CC CFLAGS LDFLAGS PKG_CONFIG_PATH CPPFLAGS LIBRARY_PATH
}

build_one_arch arm64 aarch64-apple-darwin "$WORKDIR/arm64"
build_one_arch x86_64 x86_64-apple-darwin "$WORKDIR/x86_64"

UNIVERSAL="$WORKDIR/universal"
mkdir -p "$UNIVERSAL"
for lib in ogg opus opusenc opusfile; do
  lipo -create \
    "$WORKDIR/arm64/lib/lib${lib}.a" \
    "$WORKDIR/x86_64/lib/lib${lib}.a" \
    -output "$UNIVERSAL/lib${lib}.a"
  lipo -info "$UNIVERSAL/lib${lib}.a"
done

for target in "${TARGETS[@]}"; do
  echo "Replacing prebuilt libraries in $target"
  for lib in ogg opus opusenc opusfile; do
    if [ -f "$target/lib${lib}.a" ]; then
      cp "$UNIVERSAL/lib${lib}.a" "$target/lib${lib}.a"
    fi
  done
done

echo "Rebuilt ogg/opus/opusenc/opusfile for macOS arm64+x86_64 without LTO bitcode."
