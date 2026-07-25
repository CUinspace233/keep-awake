#!/bin/bash
# KeepAwake 完整卸载脚本（独立版，不依赖 App 安装包）
#
# 卸载顺序：
#   1. 退出 GUI App 进程（如果在跑）
#   2. unload 并删除 LaunchAgent
#   3. 删后台引擎脚本
#   4. 删配置 + PID 文件
#   5. 删日志
#   6. 删 App 本体
#
# 用法:
#   bash uninstall.sh            # 完整卸载
#   bash uninstall.sh --keep-app # 只卸载后台引擎，保留 App（不常见）

set -euo pipefail

LABEL="com.cuinspace.keep-awake"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
SCRIPT="$HOME/Library/Scripts/keep-awake.sh"
LOG_DIR="$HOME/Library/Logs"
APP_DIR="$HOME/Applications/KeepAwake.app"
CONF="$HOME/.config/keep-awake.json"
PID="$HOME/.config/keep-awake.pid"

KEEP_APP=0
if [[ "${1:-}" == "--keep-app" ]]; then
    KEEP_APP=1
fi

echo "🗑  卸载 KeepAwake..."
echo

# 1. 退出 App
if pgrep -f "KeepAwake.app/Contents/MacOS/KeepAwake" >/dev/null 2>&1; then
    pkill -f "KeepAwake.app/Contents/MacOS/KeepAwake"
    sleep 1
    echo "  ✓ 退出 GUI App"
fi

# 2. unload + 删 LaunchAgent
if [[ -f "$PLIST" ]]; then
    launchctl unload "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"
    echo "  ✓ 删除 LaunchAgent: $PLIST"
fi

# 3. 删后台引擎
if [[ -f "$SCRIPT" ]]; then
    rm -f "$SCRIPT"
    echo "  ✓ 删除引擎脚本: $SCRIPT"
fi

# 4. 删配置 + PID
[[ -f "$CONF" ]] && rm -f "$CONF" && echo "  ✓ 删除配置: $CONF"
[[ -f "$PID" ]] && rm -f "$PID" && echo "  ✓ 删除 PID 文件: $PID"

# 5. 删日志
rm -f "$LOG_DIR/keep-awake.log"* "$LOG_DIR/keep-awake.out"* "$LOG_DIR/keep-awake.err"* 2>/dev/null && \
    echo "  ✓ 删除日志" || true

# 6. 删 App
if [[ $KEEP_APP -eq 0 && -d "$APP_DIR" ]]; then
    rm -rf "$APP_DIR"
    echo "  ✓ 删除 App: $APP_DIR"
elif [[ $KEEP_APP -eq 1 ]]; then
    echo "  - 保留 App: $APP_DIR"
fi

echo
echo "✅ 卸载完成。"
echo
if [[ $KEEP_APP -eq 0 ]]; then
    echo "如需重新安装："
    echo "  1. 重新下载 DMG: https://github.com/CUinspace233/keep-awake/releases/latest"
    echo "  2. 或: cd <repo> && bash install.sh"
fi