#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/MacDraw.app"
BIN_DIR="$BUILD_DIR/bin"
BIN_PATH="$BIN_DIR/MacDraw"
SDK_PATH="${SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk}"
CACHE_DIR="$ROOT_DIR/.swift-cache"
CLANG_CACHE_DIR="$ROOT_DIR/.clang-cache"

cd "$ROOT_DIR"

mkdir -p "$BUILD_DIR" "$BIN_DIR" "$CACHE_DIR" "$CLANG_CACHE_DIR"

SDKROOT="$SDK_PATH" \
CLANG_MODULE_CACHE_PATH="$CLANG_CACHE_DIR" \
swiftc \
  -sdk "$SDK_PATH" \
  -module-cache-path "$CACHE_DIR" \
  Sources/MacDraw/*.swift \
  -o "$BIN_PATH"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/MacDraw"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$APP_DIR"

echo "Built binary: $BIN_PATH"
echo "Built app bundle: $APP_DIR"
