#!/bin/bash
# 编译 KeepAwake.app 到 ~/Applications/
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$HOME/Applications/KeepAwake.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
DMG_DIR="$SRC_DIR/build"
VERSION="1.4"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$APP_DIR/Contents/Resources"

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
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>KeepAwake</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>SUPublicEDKey</key>
    <string>bOSokyZpkcejzAs+1aFn5zTOa4wSwnscQuFb/ULlcoE=</string>
    <key>SUFeedURL</key>
    <string>https://github.com/CUinspace233/keep-awake/releases/latest/download/appcast.xml</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
</dict>
</plist>
PLIST

# 编译
swiftc -O \
    -target arm64-apple-macosx14.0 \
    -framework AppKit -framework SwiftUI \
    -F "$DMG_DIR/sparkle" \
    -framework Sparkle \
    -Xlinker -rpath -Xlinker "@loader_path/../Frameworks" \
    "$SRC_DIR/Sources/AppDelegate.swift" \
    "$SRC_DIR/Sources/SettingsView.swift" \
    -o "$MACOS_DIR/KeepAwake"

# 把 Sparkle.framework 嵌入 App
if [[ -d "$DMG_DIR/sparkle/Sparkle.framework" ]]; then
    mkdir -p "$APP_DIR/Contents/Frameworks"
    cp -R "$DMG_DIR/sparkle/Sparkle.framework" "$APP_DIR/Contents/Frameworks/"
    echo "✓ 嵌入 Sparkle.framework"
fi

# 嵌入 App icon（如果存在）
if [[ -f "$SRC_DIR/build/AppIcon.icns" ]]; then
    cp "$SRC_DIR/build/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
    echo "✓ 嵌入 App 图标"
else
    echo "⚠ 未找到 build/AppIcon.icns（先跑 bash icons.sh）"
fi

# 注入 InstallHelper（首次启动时 NSAlert 会用这个路径打开 Terminal 自动执行）
if [[ -f "$SRC_DIR/install.sh" ]]; then
    mkdir -p "$APP_DIR/Contents/Resources/InstallHelper"
    cp "$SRC_DIR/install.sh" "$APP_DIR/Contents/Resources/InstallHelper/install.sh"
    cp "$SRC_DIR/keep-awake.sh" "$APP_DIR/Contents/Resources/InstallHelper/keep-awake.sh"
    cp "$SRC_DIR/com.cuinspace.keep-awake.plist" "$APP_DIR/Contents/Resources/InstallHelper/com.cuinspace.keep-awake.plist"
    chmod +x "$APP_DIR/Contents/Resources/InstallHelper/install.sh"
    chmod +x "$APP_DIR/Contents/Resources/InstallHelper/keep-awake.sh"
    echo "✓ 注入 InstallHelper"
fi

# 去掉隔离属性（首次启动需要）
xattr -dr com.apple.quarantine "$APP_DIR" 2>/dev/null || true

# 把 ${VERSION} 替换成实际版本号
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP_DIR/Contents/Info.plist" 2>/dev/null
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_DIR/Contents/Info.plist" 2>/dev/null
echo "✓ 版本号: $VERSION"

echo "✓ 编译完成: $APP_DIR"
echo "  启动: open $APP_DIR"