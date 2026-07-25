#!/bin/bash
# keep-awake.sh — 后台保活引擎
#
# 由 ~/Library/LaunchAgents/com.cuinspace.keep-awake.plist 加载并守护。
# 读取 ~/.config/keep-awake.json，按调度规则启停 caffeinate -dis。
# caffeinate 进程由本脚本派生，便于到点自动结束。
#
# 命令行用法（菜单栏 App 会通过 launchctl kickstart 间接触发）：
#   keep-awake.sh                 # daemon 模式：持续轮询 JSON 决定何时启停
#   keep-awake.sh --now 60        # 立即保活 60 分钟（写入 JSON oneShot 段）
#   keep-awake.sh --now 0         # 立即保活无限时长
#   keep-awake.sh --stop          # 立刻停止保活
#   keep-awake.sh --status        # 打印当前状态
#
# 设计要点：
#   - 调度冲突时 oneShot 优先于 weekly
#   - caffeine PID 写到 ~/.config/keep-awake.pid，重复调用会清理旧 PID
#   - 锁屏 = pmset displaysleepnow，不影响 caffeinate 的 -d（caffeinate 只阻止睡眠发生，displaysleepnow 是请求一次性的显示器关闭）

set -euo pipefail

CONFIG="$HOME/.config/keep-awake.json"
PIDFILE="$HOME/.config/keep-awake.pid"
LOG="$HOME/Library/Logs/keep-awake.log"
WEEKDAYS=(Mon Tue Wed Thu Fri Sat Sun)

mkdir -p "$(dirname "$CONFIG")" "$(dirname "$LOG")"

log() { echo "[$(date '+%F %T')] $*" >> "$LOG"; }

# ---------- 日志清理 ----------
# 策略：保留 30 天内的日志；超过 30 天的 .log/.out/.err 全部删除
# 在 daemon 启动时跑一次（每天最多一次）
LOG_DIR="$(dirname "$LOG")"
LOG_RETENTION_DAYS=30

rotate_logs() {
    # 删掉 N 天前的旧日志
    find "$LOG_DIR" -maxdepth 1 -type f \
        \( -name 'keep-awake.log*' -o -name 'keep-awake.out*' -o -name 'keep-awake.err*' \) \
        -mtime +${LOG_RETENTION_DAYS} -delete 2>/dev/null || true
    # 单文件超过 1MB 时轮转：旧文件改名 .1，新文件从空开始
    for f in "$LOG" "$LOG_DIR/keep-awake.out" "$LOG_DIR/keep-awake.err"; do
        if [[ -f "$f" ]] && [[ $(stat -f%z "$f" 2>/dev/null || echo 0) -gt 1048576 ]]; then
            mv "$f" "${f}.1.$(date '+%Y%m%d')"
        fi
    done
}

# ---------- 默认配置 ----------
default_config() {
cat <<'JSON'
{
  "autoLockScreen": true,
  "oneShot": {
    "startAt": null,
    "durationMinutes": 0,
    "active": false
  },
  "weekly": {
    "enabled": false,
    "days": [1, 2, 3, 4, 5],
    "startTime": "09:00",
    "endTime": "18:00"
  }
}
JSON
}

ensure_config() {
    if [[ ! -f "$CONFIG" ]]; then
        default_config > "$CONFIG"
        log "created default config at $CONFIG"
    fi
}

# ---------- caffeinate 生命周期 ----------
caffeinate_pid() {
    [[ -f "$PIDFILE" ]] && cat "$PIDFILE" 2>/dev/null || echo ""
}

is_running() {
    local pid
    pid=$(caffeinate_pid)
    [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

start_caffeinate() {
    if is_running; then
        log "caffeinate already running (pid=$(caffeinate_pid))"
        return 0
    fi
    /usr/bin/caffeinate -dis &
    local pid=$!
    echo "$pid" > "$PIDFILE"
    log "started caffeinate -dis pid=$pid"
    if [[ "$(jq -r '.autoLockScreen' "$CONFIG" 2>/dev/null)" == "true" ]]; then
        # 异步锁屏；不等待，避免阻塞本脚本
        pmset displaysleepnow &>/dev/null || true
        log "lock screen requested"
    fi
}

stop_caffeinate() {
    local pid
    pid=$(caffeinate_pid)
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        log "stopped caffeinate pid=$pid"
    fi
    rm -f "$PIDFILE"
}

# ---------- 调度判断 ----------
# 输入：当前 epoch 秒；输出："ON" / "OFF"
should_be_active() {
    local now_epoch="$1"
    local now_hm weekday
    now_hm=$(date -r "$now_epoch" '+%H:%M')
    weekday=$(date -r "$now_epoch" '+%u')  # 1=Mon..7=Sun

    # 1) oneShot 优先
    local one_active one_start one_dur
    one_active=$(jq -r '.oneShot.active' "$CONFIG")
    if [[ "$one_active" == "true" ]]; then
        one_start=$(jq -r '.oneShot.startAt' "$CONFIG")
        one_dur=$(jq -r '.oneShot.durationMinutes' "$CONFIG")
        local start_epoch end_epoch
        start_epoch=$(date -j -f '%Y-%m-%dT%H:%M:%S' "$one_start" '+%s' 2>/dev/null || echo 0)
        if [[ "$one_dur" == "0" ]]; then
            # 无限时长
            [[ $now_epoch -ge $start_epoch ]] && { echo "ON"; return; }
        else
            end_epoch=$((start_epoch + one_dur * 60))
            [[ $now_epoch -ge $start_epoch && $now_epoch -lt $end_epoch ]] && { echo "ON"; return; }
            # 已过期：自动关闭 oneShot
            if [[ $now_epoch -ge $end_epoch ]]; then
                jq '.oneShot.active = false' "$CONFIG" > "${CONFIG}.tmp" && mv "${CONFIG}.tmp" "$CONFIG"
                log "oneShot expired, marked inactive"
            fi
        fi
    fi

    # 2) weekly
    local weekly_enabled weekly_days weekly_start weekly_end
    weekly_enabled=$(jq -r '.weekly.enabled' "$CONFIG")
    if [[ "$weekly_enabled" == "true" ]]; then
        weekly_days=$(jq -r '.weekly.days | join(",")' "$CONFIG")
        weekly_start=$(jq -r '.weekly.startTime' "$CONFIG")
        weekly_end=$(jq -r '.weekly.endTime' "$CONFIG")
        local in_today=false in_tomorrow=false
        if [[ "$weekly_start" < "$weekly_end" ]]; then
            # 同一天：start < end，例如 09:00-18:00
            # now 在 [start, end] 闭区间
            if [[ ( "$now_hm" > "$weekly_start" || "$now_hm" == "$weekly_start" ) && \
                  ( "$now_hm" < "$weekly_end" || "$now_hm" == "$weekly_end" ) ]]; then
                in_today=true
            fi
        else
            # 跨天：start > end，例如 22:00-06:00
            # 当天晚上段：now >= start
            if [[ "$now_hm" > "$weekly_start" || "$now_hm" == "$weekly_start" ]]; then
                in_today=true
            fi
            # 次日凌晨段：now < end
            if [[ "$now_hm" < "$weekly_end" ]]; then
                in_tomorrow=true
            fi
        fi
        # 今天 weekday 命中 & in_today
        if [[ "$in_today" == "true" && ",$weekly_days," == *",$weekday,"* ]]; then
            echo "ON"; return
        fi
        # 次日凌晨段：把"今天 weekday"回退一天，看昨天是否在 days 中
        if [[ "$in_tomorrow" == "true" ]]; then
            local prev_weekday=$(( weekday == 1 ? 7 : weekday - 1 ))
            if [[ ",$weekly_days," == *",$prev_weekday,"* ]]; then
                echo "ON"; return
            fi
        fi
    fi

    echo "OFF"
}

# ---------- daemon 模式 ----------
daemon_loop() {
    log "daemon started, watching $CONFIG"
    rotate_logs
    while true; do
        ensure_config
        local now_epoch
        now_epoch=$(date '+%s')
        local want
        want=$(should_be_active "$now_epoch")
        if [[ "$want" == "ON" ]]; then
            start_caffeinate
        else
            stop_caffeinate
        fi
        sleep 30
    done
}

# ---------- CLI ----------
usage() {
    grep '^#' "$0" | sed 's/^# \{0,1\}//'
}

cmd_status() {
    ensure_config
    echo "config: $CONFIG"
    echo "caffeinate running: $(is_running && echo yes || echo no)"
    echo "current schedule says: $(should_be_active "$(date '+%s')")"
    jq . "$CONFIG"
}

cmd_now() {
    local minutes="${1:-0}"
    ensure_config
    local now_iso
    now_iso=$(date '+%Y-%m-%dT%H:%M:%S')
    local tmp
    tmp=$(jq --arg s "$now_iso" --argjson m "$minutes" \
        '.oneShot.startAt = $s | .oneShot.durationMinutes = $m | .oneShot.active = true' "$CONFIG")
    echo "$tmp" > "${CONFIG}.tmp" && mv "${CONFIG}.tmp" "$CONFIG"
    log "CLI --now $minutes: wrote oneShot.startAt=$now_iso"
    # 立即触发 daemon 重读
    launchctl kickstart -k "gui/$(id -u)/com.cuinspace.keep-awake" &>/dev/null || true
    echo "✓ 保活已启动：$minutes 分钟（0 = 无限）"
    start_caffeinate
}

cmd_stop() {
    ensure_config
    local tmp
    tmp=$(jq '.oneShot.active = false' "$CONFIG")
    echo "$tmp" > "${CONFIG}.tmp" && mv "${CONFIG}.tmp" "$CONFIG"
    stop_caffeinate
    log "CLI --stop"
    echo "✓ 已停止保活"
}

# ---------- main ----------
case "${1:-daemon}" in
    daemon|"")     daemon_loop ;;
    --now)         shift; cmd_now "${1:-0}" ;;
    --stop)        cmd_stop ;;
    --status)      cmd_status ;;
    -h|--help)     usage; exit 0 ;;
    *)             echo "未知参数: $1" >&2; usage; exit 1 ;;
esac