#!/bin/sh
# Builds the C GDExtension. C is compiled by zig's clang, which can target
# Linux, Windows and Android from the FreeBSD host.
set -e
cd "$(dirname "$0")"

CC=${CC:-"zig cc"}
CFLAGS="-std=c11 -O2 -fPIC -Wall -Wextra -Wno-unused-parameter -Wno-cast-function-type -shared"
SRC="src/api.c src/native_ops.c src/init.c"

mkdir -p bin

case "${1:-linux}" in
  linux)
    $CC -target x86_64-linux-gnu $CFLAGS $SRC -lm -o bin/libopenshooter_native.so
    ;;
  windows)
    $CC -target x86_64-windows-gnu $CFLAGS $SRC -lm -o bin/openshooter_native.dll
    ;;
  android)
    SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/home/renan/Android/Sdk}}"
    if [ -z "${ANDROID_NDK_HOME:-}" ]; then
      ANDROID_NDK_HOME="$(ls -d "$SDK"/ndk/* 2>/dev/null | sort -V | tail -n 1)"
    fi
    NDK="${ANDROID_NDK_HOME:?Android NDK not found; set ANDROID_NDK_HOME}"
    ANDROID_CC="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang"
    "$ANDROID_CC" $CFLAGS $SRC -lm -s -o bin/libopenshooter_native.android.so
    ANDROID_CC32="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/armv7a-linux-androideabi24-clang"
    "$ANDROID_CC32" $CFLAGS $SRC -lm -s -o bin/libopenshooter_native.android-arm32.so
    ;;
  freebsd)
    cc -std=c11 -O2 -fPIC -shared -Wall -Wextra -Wno-unused-parameter -Wno-cast-function-type       $SRC -lm -o bin/libopenshooter_native.freebsd.so
    ;;
  all)
    "$0" linux
    "$0" windows
    "$0" android
    "$0" freebsd
    ;;
  *)
    echo "usage: $0 [linux|windows|android|freebsd|all]" >&2
    exit 2
    ;;
esac
echo "built native ($1)"
