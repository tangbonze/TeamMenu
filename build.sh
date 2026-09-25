#!/bin/bash
# Build TeamMenu.app into outputs/
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="TeamMenu"
BUNDLE_ID="com.teammenu.TeamMenu"
SRC="TeamMenu.swift"
PROJECT_ROOT="$(cd .. && pwd)"
OUT_APP="$PROJECT_ROOT/outputs/${APP_NAME}.app"
BUILD_DIR="build"

rm -rf "$BUILD_DIR" "$OUT_APP"
mkdir -p "$BUILD_DIR" "$OUT_APP/Contents/MacOS" "$OUT_APP/Contents/Resources"

echo "==> Compiling $SRC ..."
swiftc -O -parse-as-library -module-cache-path "$BUILD_DIR/module-cache" -o "$BUILD_DIR/TeamMenu" "$SRC"
cp "$BUILD_DIR/TeamMenu" "$OUT_APP/Contents/MacOS/TeamMenu"

echo "==> Icon ..."
OFFICIAL_ICON="/Applications/Teamo.app/Contents/Resources/icon.icns"
if [ -f "$OFFICIAL_ICON" ]; then
  cp "$OFFICIAL_ICON" "$OUT_APP/Contents/Resources/icon.icns"
  echo "    app icon: official TeamoRouter logo"
else
  echo "    official app icon not found, generating fallback ..."
  swiftc -O -module-cache-path "$BUILD_DIR/module-cache" -o "$BUILD_DIR/make-icon" make-icon.swift
  "$BUILD_DIR/make-icon" "$BUILD_DIR/icon-base.png"
  ICONSET="$BUILD_DIR/TeamMenu.iconset"
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  make_size() {
    local px="$1" name="$2"
    sips -z "$px" "$px" --deleteColorManagementProperties "$BUILD_DIR/icon-base.png" --out "$ICONSET/$name" >/dev/null
  }
  make_size 16   icon_16x16.png
  make_size 32   icon_16x16@2x.png
  make_size 32   icon_32x32.png
  make_size 64   icon_32x32@2x.png
  make_size 128  icon_128x128.png
  make_size 256  icon_128x128@2x.png
  make_size 256  icon_256x256.png
  make_size 512  icon_256x256@2x.png
  make_size 512  icon_512x512.png
  make_size 1024 icon_512x512@2x.png
  python3 make-icns.py "$ICONSET" "$OUT_APP/Contents/Resources/icon.icns"
fi

if [ -f "assets/menubar.png" ]; then
  cp "assets/menubar.png" "$BUILD_DIR/menubar-72.png"
  sips -z 36 36 "$BUILD_DIR/menubar-72.png" --out "$OUT_APP/Contents/Resources/menubar.png" >/dev/null
  echo "    menubar logo: official TeamoRouter T-logo 36px @2x (assets/menubar.png)"
elif [ -f "$OFFICIAL_ICON" ]; then
  python3 extract-icns-png.py "$OFFICIAL_ICON" "$BUILD_DIR/menubar-source.png"
  sips -z 64 64 "$BUILD_DIR/menubar-source.png" --out "$OUT_APP/Contents/Resources/menubar.png" >/dev/null
  echo "    menubar logo: extracted from app icon"
else
  sips -z 64 64 "$BUILD_DIR/icon-base.png" --out "$OUT_APP/Contents/Resources/menubar.png" >/dev/null
  echo "    menubar logo: fallback generated icon"
fi

codesign --force --deep --sign - "$OUT_APP" >/dev/null 2>&1 || true

echo "==> Built: $OUT_APP"
echo "==> Run:  open \"$OUT_APP\""
