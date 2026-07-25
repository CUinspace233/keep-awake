#!/bin/bash
# KeepAwake 后台引擎一键安装脚本
# 由菜单栏 App 在检测到 keep-awake.sh 缺失时引导用户执行
#
# 用法:
#   bash install.sh           # 安装
#   bash install.sh --uninstall   # 卸载
#
# 安装内容:
#   1. ~/Library/Scripts/keep-awake.sh          # 保活引擎
#   2. ~/Library/LaunchAgents/com.cuinspace.keep-awake.plist  # LaunchAgent
#   3. ~/.config/keep-awake.json                # 调度配置（首次）
#
# LaunchAgent 由 launchd 加载，开机自启，进程异常退出自动重启。
# 注意：此脚本会启动持久化进程，仅在你信任本工具时执行。

set -euo pipefail

LABEL="com.cuinspace.keep-awake"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
SCRIPT="$HOME/Library/Scripts/keep-awake.sh"
LOG="$HOME/Library/Logs/keep-awake.log"
HERE="$(cd "$(dirname "$0")" && pwd)"

uninstall() {
    echo "🗑  卸载 KeepAwake 后台引擎..."
    launchctl unload "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"
    rm -f "$SCRIPT"
    rm -f "$HOME/.config/keep-awake.pid"
    echo "✓ 已卸载（App 本身在 /Applications/KeepAwake.app 里，需手动删除）"
    exit 0
}

if [[ "${1:-}" == "--uninstall" ]]; then
    uninstall
fi

echo "🚀 安装 KeepAwake 后台引擎..."

# 复制脚本
mkdir -p "$(dirname "$SCRIPT")" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs" "$HOME/.config"
cp "$HERE/keep-awake.sh" "$SCRIPT"
chmod +x "$SCRIPT"
echo "  ✓ 复制引擎脚本: $SCRIPT"

# 写 LaunchAgent（用 sed 把里面的当前用户目录展开成 ~）
sed "s|/Users/cuinspace|$HOME|g" "$HERE/com.cuinspace.keep-awake.plist" > "$PLIST"
echo "  ✓ 写 LaunchAgent: $PLIST"

# 加载 LaunchAgent
launchctl load -w "$PLIST"
sleep 1
if launchctl list | grep -q "$LABEL"; then
    echo "  ✓ LaunchAgent 已启动（开机自启）"
else
    echo "  ⚠ LaunchAgent 加载失败，请检查日志: $LOG"
    exit 1
fi

echo ""
echo "✅ 安装完成！"
echo ""
echo "查看状态: bash $SCRIPT --status"
echo "查看日志: tail -f $LOG"
echo "卸载: bash $SCRIPT --uninstall  或者  bash $HERE/install.sh --uninstall"