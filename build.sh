#!/bin/bash
# 编译 KeepAwake.app 到 ~/Applications/
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$HOME/Applications/KeepAwake.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

# Info.plist
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>KeepAwake</string>
    <key>CFBundleDisplayName</key>
    <string>KeepAwake</string>
    <key>CFBundleIdentifier</key>
    <string>com.cuinspace.KeepAwake</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>KeepAwake</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# 编译
swiftc -O \
    -target arm64-apple-macosx14.0 \
    -framework AppKit -framework SwiftUI \
    "$SRC_DIR/Sources/AppDelegate.swift" \
    "$SRC_DIR/Sources/SettingsView.swift" \
    -o "$MACOS_DIR/KeepAwake"

# 去掉隔离属性（首次启动需要）
xattr -dr com.apple.quarantine "$APP_DIR" 2>/dev/null || true

echo "✓ 编译完成: $APP_DIR"
echo "  启动: open $APP_DIR"