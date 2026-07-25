#!/bin/bash
# KeepAwake DMG 打包脚本
# 编译 App + ad-hoc 签名 + 打包成可分发的 DMG（含 InstallHelper）
#
# 用法:
#   bash package.sh                          # 默认：build/KeepAwake-v1.0.dmg
#   bash package.sh --output /tmp/foo.dmg    # 自定义输出
#   bash package.sh --skip-build             # 跳过编译（用现有 ~/Applications/KeepAwake.app）
#
# 要求: macOS + Xcode Command Line Tools

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="KeepAwake"
VERSION="1.1"
APP_SRC="$HOME/Applications/${APP_NAME}.app"
DMG_DIR="$HERE/build"
DMG_NAME="${APP_NAME}-v${VERSION}"
DMG_PATH="$DMG_DIR/${DMG_NAME}.dmg"

OUTPUT="$DMG_PATH"
SKIP_BUILD=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output) OUTPUT="$2"; shift 2 ;;
        --skip-build) SKIP_BUILD=1; shift ;;
        -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "未知参数: $1" >&2; exit 1 ;;
    esac
done

# ---------- 1. 编译 ----------
if [[ $SKIP_BUILD -eq 0 ]]; then
    echo "==> 编译 ${APP_NAME}.app..."
    bash "$HERE/build.sh"
else
    echo "==> 跳过编译，使用现有 $APP_SRC"
fi

if [[ ! -d "$APP_SRC" ]]; then
    echo "❌ 找不到 $APP_SRC，请先 build" >&2
    exit 1
fi

# ---------- 2. 复制 InstallHelper 到 App/Contents/Resources ----------
echo "==> 注入 InstallHelper..."
RES="$APP_SRC/Contents/Resources"
rm -rf "$RES/InstallHelper"
mkdir -p "$RES/InstallHelper"
cp "$HERE/install.sh" "$RES/InstallHelper/install.sh"
cp "$HERE/keep-awake.sh" "$RES/InstallHelper/keep-awake.sh"
cp "$HERE/uninstall.sh" "$RES/InstallHelper/uninstall.sh"
cp "$HERE/com.cuinspace.keep-awake.plist" "$RES/InstallHelper/com.cuinspace.keep-awake.plist"
chmod +x "$RES/InstallHelper/install.sh" "$RES/InstallHelper/keep-awake.sh" "$RES/InstallHelper/uninstall.sh"

# ---------- 3. ad-hoc 签名 ----------
echo "==> ad-hoc 签名..."
codesign --force --deep --sign - "$APP_SRC" 2>&1 | tail -3
xattr -dr com.apple.quarantine "$APP_SRC" 2>/dev/null || true

# ---------- 4. 构建 DMG staging ----------
echo "==> 构建 DMG staging..."
# 保留 iconset/icns 等已有产物，只清 staging 子目录
rm -rf "$DMG_DIR/staging" "$DMG_DIR/temp_rw.dmg"
mkdir -p "$DMG_DIR/staging"
cp -R "$APP_SRC" "$DMG_DIR/staging/${APP_NAME}.app"

# Applications 快捷方式（用户拖拽目标）
ln -s /Applications "$DMG_DIR/staging/Applications"

# DMG 卷标图标（mount 后在 Finder 侧栏和顶部看到的图标）
if [[ -f "$HERE/build/AppIcon.icns" ]]; then
    # macOS 用 .VolumeIcon.icns 作为 DMG 卷标
    mkdir -p "$DMG_DIR/staging/.KeepAwake"
    cp "$HERE/build/AppIcon.icns" "$DMG_DIR/staging/.KeepAwake/.VolumeIcon.icns"
    echo "==> 已注入 DMG 卷标图标"
fi

# README
cat > "$DMG_DIR/staging/安装说明.txt" <<EOF
KeepAwake 安装指南

1. 把 KeepAwake.app 拖到右边的 Applications 快捷方式
2. 首次启动 KeepAwake 会弹出提示，请在「终端」里粘贴运行：
       bash "\$(/Applications/${APP_NAME}.app/Contents/Resources/InstallHelper/install.sh)"
   这一步会安装保活后台引擎 + LaunchAgent（开机自启）
3. 引擎装好后重启 KeepAwake 即可

卸载：
- App:    把 /Applications/${APP_NAME}.app 拖到废纸篍
- 引擎:   bash "/Applications/${APP_NAME}.app/Contents/Resources/InstallHelper/install.sh" --uninstall

系统要求：macOS 14.0+
EOF

# ---------- 5. 创建 DMG ----------
echo "==> 创建 DMG: $OUTPUT"
DMG_STAGING="$DMG_DIR/staging"
# 创建只读 DMG（如有图标则一并注入）
ICON_ARG=""
if [[ -f "$HERE/build/AppIcon.icns" ]]; then
    # hdiutil 不直接支持 -icon，需要创建后用 sips/hdiutil 注入 .VolumeIcon.icns 到根卷
    # 临时 writable DMG 做法：
    RW_DMG="$DMG_DIR/temp_rw.dmg"
    # 用 -srcfolder 时 . 开头的隐藏文件会被排除，但我们用普通文件名
    # 创建一个临时 staging 副本（不复制隐藏文件目录）
    rm -rf "$DMG_DIR/staging_nohide"
    mkdir -p "$DMG_DIR/staging_nohide"
    # 把可见文件复制过去（不包括 .KeepAwake/、._*、._ 开头的隐藏文件）
    find "$DMG_STAGING" -maxdepth 1 -mindepth 1 ! -name ".*" -exec cp -R {} "$DMG_DIR/staging_nohide/" \;
    cp "$HERE/build/AppIcon.icns" "$DMG_DIR/staging_nohide/zz_keep_awake_icon.icns"
    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$DMG_DIR/staging_nohide" \
        -ov -format UDRW \
        -fs HFS+ \
        "$RW_DMG"
    # 挂载读写 DMG
    MOUNT=$(hdiutil attach -readwrite -nobrowse "$RW_DMG" 2>/dev/null | awk '/Apple_HFS/{print $3; exit}')
    if [[ -n "$MOUNT" ]]; then
        mv "$MOUNT/zz_keep_awake_icon.icns" "$MOUNT/.VolumeIcon.icns"
        SetFile -a V "$MOUNT/.VolumeIcon.icns" 2>/dev/null || true
        hdiutil detach "$MOUNT" >/dev/null
        hdiutil convert "$RW_DMG" -format UDZO -ov -o "$OUTPUT"
        rm -rf "$RW_DMG" "$DMG_DIR/staging_nohide"
    else
        echo "⚠ 挂载读写 DMG 失败，回退到无图标方式"
        rm -rf "$RW_DMG" "$DMG_DIR/staging_nohide"
        hdiutil create -volname "$APP_NAME" \
            -srcfolder "$DMG_STAGING" \
            -ov -format UDZO \
            -fs HFS+ \
            "$OUTPUT"
    fi
else
    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$DMG_STAGING" \
        -ov -format UDZO \
        -fs HFS+ \
        "$OUTPUT"
fi

echo ""
echo "✅ 打包完成: $OUTPUT"
ls -lh "$OUTPUT"

# ---------- 6. 清理 ----------
rm -rf "$DMG_DIR/staging"