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

# 加载 LaunchAgent（注意：不能把 launchctl load 的 stdout pipe 到 sed，
# 否则 launchd 子进程 spawn 时会被延迟，导致 list 看不到）
LOAD_OUTPUT=$(launchctl load -w "$PLIST" 2>&1)
if [[ -n "$LOAD_OUTPUT" ]]; then
    echo "$LOAD_OUTPUT" | sed 's/^/    /'
fi

# macOS 26 上 launchd 注册 label 可能慢，最多等 20 秒，每秒重试
FOUND=0
DOMAIN="gui/$(id -u)"
for i in $(seq 1 20); do
    sleep 1
    # 用 launchctl print 检查（比 list 更可靠，不会被进程重启窗口期影响）
    if launchctl print "$DOMAIN/$LABEL" 2>/dev/null | grep -q "state = "; then
        PID=$(launchctl list 2>/dev/null | awk -v lbl="$LABEL" '$3==lbl{print $1}')
        echo "  ✓ LaunchAgent 已启动（pid=${PID:-未分配}，开机自启）"
        FOUND=1
        break
    fi
done
if [[ $FOUND -eq 0 ]]; then
    echo "  ⚠ LaunchAgent 加载后 20s 内未注册，检查日志: $LOG"
    exit 1
fi

echo ""
echo "✅ 安装完成！"
echo ""
echo "查看状态: bash $SCRIPT --status"
echo "查看日志: tail -f $LOG"
echo "卸载: bash $SCRIPT --uninstall  或者  bash $HERE/install.sh --uninstall"