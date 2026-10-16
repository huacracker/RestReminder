#!/bin/bash
# 编译「休息提醒」App：swiftc 编译 → 组装 .app → 生成图标 → 签名 → 安装到 ~/Applications
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="休息提醒"
EXEC_NAME="RestReminder"
DIST="$DIR/dist"
APP="$DIST/$APP_NAME.app"
INSTALL_DIR="$HOME/Applications"

echo "==> 清理"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> 编译 Swift"
swiftc -O -swift-version 5 \
  -target arm64-apple-macosx14.0 \
  -o "$APP/Contents/MacOS/$EXEC_NAME" \
  "$DIR/Sources/main.swift"

echo "==> Info.plist"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$EXEC_NAME</string>
    <key>CFBundleIdentifier</key><string>com.huage.restreminder</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>华哥 2026</string>
</dict>
</plist>
PLIST

echo "==> 图标"
if [ -f "$DIR/scripts/gen-icon.swift" ]; then
  ICONSET="$DIST/AppIcon.iconset"
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  swift "$DIR/scripts/gen-icon.swift" "$ICONSET" >/dev/null
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET"
fi

echo "==> 签名"
codesign --force --sign - --timestamp=none "$APP" 2>/dev/null || codesign --force --sign - "$APP"

echo "==> 安装到 $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
pkill -f "$EXEC_NAME" 2>/dev/null || true
sleep 0.4
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$APP" "$INSTALL_DIR/$APP_NAME.app"

echo "==> 完成: $INSTALL_DIR/$APP_NAME.app"
ls -la "$INSTALL_DIR/$APP_NAME.app/Contents/MacOS/"
