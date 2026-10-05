#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SDK_ROOT=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}
NDK_VERSION=${NDK_VERSION:-28.2.13676358}
ANDROID_API=${ANDROID_API:-23}

if [ -z "$SDK_ROOT" ]; then
    SDK_ROOT="$HOME/Library/Android/sdk"
fi

NDK_ROOT=${ANDROID_NDK_HOME:-"$SDK_ROOT/ndk/$NDK_VERSION"}
TOOLCHAIN_FILE="$NDK_ROOT/build/cmake/android.toolchain.cmake"

if [ ! -f "$TOOLCHAIN_FILE" ]; then
    echo "NDK toolchain not found: $TOOLCHAIN_FILE" >&2
    exit 1
fi

for ABI in arm64-v8a armeabi-v7a x86_64 x86; do
    OUT="$ROOT/build/android/$ABI"
    cmake -S "$ROOT" -B "$OUT" \
        -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE" \
        -DANDROID_ABI="$ABI" \
        -DANDROID_PLATFORM="android-$ANDROID_API" \
        -DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON \
        -DCMAKE_BUILD_TYPE=MinSizeRel \
        -DKC_BUILD_TESTS=OFF >/dev/null
    cmake --build "$OUT" --config MinSizeRel >/dev/null
    "$NDK_ROOT/toolchains/llvm/prebuilt/"*/bin/llvm-strip --strip-unneeded "$OUT/libpromax_crypto.so"
    echo "$ABI: $OUT/libpromax_crypto.so"
done
