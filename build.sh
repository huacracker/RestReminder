#!/bin/bash
# RestReminder 休息提醒 — 构建脚本
#
#   ./build.sh            编译（本机架构）→ 打包 .app → 签名 → 安装到 ~/Applications
#   ./build.sh release    编译 arm64 + x86_64 通用二进制 → 生成 dmg + zip 到 dist/
#   ./build.sh run        编译安装后直接启动
#
# 只需 macOS Command Line Tools（xcode-select --install），不需要完整 Xcode。
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
PRODUCT="RestReminder"
VERSION="1.0.0"
BUNDLE_ID="com.restreminder.app"
MIN_MACOS="14.0"
DIST="$DIR/dist"
APP="$DIST/$PRODUCT.app"
INSTALL_DIR="$HOME/Applications"
MODE="${1:-install}"

echo "==> 清理 ($MODE)"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/zh-Hans.lproj"

compile() {  # $1=架构  $2=输出文件
  echo "    编译 $1"
  swiftc -O -swift-version 5 -target "$1-apple-macosx$MIN_MACOS" \
    -o "$2" "$DIR/Sources/main.swift"
}

if [ "$MODE" = "release" ]; then
  compile arm64 "$DIST/bin-arm64"
  compile x86_64 "$DIST/bin-x86_64"
  lipo -create -output "$APP/Contents/MacOS/$PRODUCT" "$DIST/bin-arm64" "$DIST/bin-x86_64"
  rm -f "$DIST/bin-arm64" "$DIST/bin-x86_64"
  echo "    架构: $(lipo -archs "$APP/Contents/MacOS/$PRODUCT")"
else
  compile "$(uname -m)" "$APP/Contents/MacOS/$PRODUCT"
fi

echo "==> Info.plist"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$PRODUCT</string>
    <key>CFBundleDisplayName</key><string>$PRODUCT</string>
    <key>CFBundleExecutable</key><string>$PRODUCT</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT License · 2026 Huage</string>
</dict>
</plist>
PLIST

# 中文系统下 Finder 显示中文名
printf 'CFBundleName = "休息提醒";\nCFBundleDisplayName = "休息提醒";\n' > "$APP/Contents/Resources/zh-Hans.lproj/InfoPlist.strings"

echo "==> 图标"
ICONSET="$DIST/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
swift "$DIR/scripts/gen-icon.swift" "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

echo "==> 签名"
codesign --force --sign - --timestamp=none "$APP" 2>/dev/null || codesign --force --sign - "$APP"
codesign --verify --strict "$APP" && echo "    签名校验通过"

if [ "$MODE" = "release" ]; then
  echo "==> 打包 dmg / zip"
  STAGE="$DIST/dmg-stage"
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  cat > "$STAGE/Read me first.txt" <<'TXT'
RestReminder — 休息提醒
========================

安装：把 RestReminder.app 拖到 Applications（右侧的快捷方式即可）。

首次打开若提示「无法验证开发者」（本应用用 ad-hoc 签名、未做 Apple 公证）：
  右键点图标 →「打开」→ 再点「打开」；或执行一次：
    xattr -dr com.apple.quarantine /Applications/RestReminder.app

启动后没有 Dock 图标是正常的 —— 它常驻顶部菜单栏（☕️）。
开机自启：点菜单里的「开机自动启动」。

--- English ---
Install: drag RestReminder.app into Applications.

If macOS says the developer cannot be verified (this app is ad-hoc signed and not notarized):
  Right-click the app → Open → Open. Or run:
    xattr -dr com.apple.quarantine /Applications/RestReminder.app

No Dock icon is expected — it lives in the menu bar (☕️).
Enable "Launch at login" from its menu if you want it to start automatically.
TXT
  hdiutil create -volname "RestReminder $VERSION" -srcfolder "$STAGE" -ov -format UDZO \
    "$DIST/$PRODUCT-$VERSION-macos-universal.dmg" >/dev/null
  ditto -c -k --keepParent "$APP" "$DIST/$PRODUCT-$VERSION-macos-universal.zip"
  rm -rf "$STAGE"
  echo "==> 产物"
  ls -la "$DIST" | grep -E '\.dmg|\.zip'
fi

echo "==> 安装到 $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
pkill -f "$INSTALL_DIR/$PRODUCT.app" 2>/dev/null || true
sleep 0.4
rm -rf "$INSTALL_DIR/$PRODUCT.app"
# 清掉旧的中文文件名副本，避免出现两个实例
rm -rf "$INSTALL_DIR/休息提醒.app"
cp -R "$APP" "$INSTALL_DIR/$PRODUCT.app"

echo "==> 完成: $INSTALL_DIR/$PRODUCT.app"
if [ "$MODE" = "run" ]; then
  open -a "$INSTALL_DIR/$PRODUCT.app"
  sleep 2
  pgrep -fl "$INSTALL_DIR/$PRODUCT.app" | head -2
fi
