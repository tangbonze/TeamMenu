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
if [ "${UNIVERSAL:-0}" = "1" ]; then
  echo "    universal build (arm64 + x86_64) ..."
  if swiftc -O -parse-as-library -target arm64-apple-macosx13.0 -module-cache-path "$BUILD_DIR/mc-arm" -o "$BUILD_DIR/TeamMenu-arm64" "$SRC" >"$BUILD_DIR/build-arm64.log" 2>&1 \
     && swiftc -O -parse-as-library -target x86_64-apple-macosx13.0 -module-cache-path "$BUILD_DIR/mc-x86" -o "$BUILD_DIR/TeamMenu-x86" "$SRC" >"$BUILD_DIR/build-x86_64.log" 2>&1; then
    lipo -create -output "$BUILD_DIR/TeamMenu" "$BUILD_DIR/TeamMenu-arm64" "$BUILD_DIR/TeamMenu-x86"
    echo "    universal: $(lipo -info "$BUILD_DIR/TeamMenu" | sed 's/.*are: //')"
  else
    echo "    universal build failed, falling back to host arch (see build/*.log)"
    swiftc -O -parse-as-library -module-cache-path "$BUILD_DIR/module-cache" -o "$BUILD_DIR/TeamMenu" "$SRC"
  fi
else
  swiftc -O -parse-as-library -module-cache-path "$BUILD_DIR/module-cache" -o "$BUILD_DIR/TeamMenu" "$SRC"
fi
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

cat > "$OUT_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
    <key>CFBundleExecutable</key><string>TeamMenu</string>
    <key>CFBundleIconFile</key><string>icon</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>TeamMenu</string>
    <key>CFBundleDisplayName</key><string>TeamMenu</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.1</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>TeamMenu</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$OUT_APP" >/dev/null 2>&1 || true

echo "==> Built: $OUT_APP"
echo "==> Run:  open \"$OUT_APP\""
