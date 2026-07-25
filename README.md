# KeepAwake

> macOS 熄屏保活工具 —— 自定义开始时间、时长、星期，屏幕可黑但 CPU / Wi‑Fi / Terminal 等进程持续工作。
>
> macOS menu-bar keep-awive utility — schedule by start time, duration, weekdays. Screen can sleep, but CPU / Wi-Fi / Ghostty keep running.

## 功能 / Features

- 🌙 **菜单栏 App** —— 一键开启/关闭，点图标弹出快捷菜单
- ⏰ **三种调度模式** —— 立即保活 / 定时单次 / 每周循环
- 🌃 **支持跨天** —— 例如 `工作日 22:00 → 次日 09:00` 自动判断为跨天
- 🔒 **自动锁屏** —— 保活期间屏幕可黑（`pmset displaysleepnow`），CPU 继续工作
- 🚀 **开机自启** —— LaunchAgent 守护后台引擎，进程异常退出自动重启
- 🪶 **轻量原生** —— Swift + SwiftUI，单文件可执行 ~250 KB

## 系统要求 / Requirements

- macOS 14.0+ (Sonoma 或更新 / Sonoma or newer)
- Apple Silicon / Intel

## 安装 / Installation

### 方式 1：下载 DMG（推荐 / Recommended）

前往 [Releases](https://github.com/CUinspace233/keep-awake/releases) 下载最新 `KeepAwake-v1.0.dmg`：

1. 双击挂载 DMG
2. 把 `KeepAwake.app` 拖到右边的 `Applications` 快捷方式
3. 启动 `KeepAwake.app` → 弹窗提示运行一次性安装命令
4. 打开「终端」粘贴命令（已自动复制）→ 回车
5. 安装完成后重启 KeepAwake 即可

> 第一次启动时若系统提示"无法打开，因为它来自身份不明的开发者"，请到「系统设置 → 隐私与安全性」点「仍要打开」。
>
> On first launch, if macOS warns "cannot be opened because the developer cannot be verified", go to **System Settings → Privacy & Security** and click **Open Anyway**.

### 方式 2：从源码构建 / Build from source

```bash
git clone https://github.com/CUinspace233/keep-awake.git
cd keep-awake
bash build.sh         # 编译 ~/Applications/KeepAwake.app
bash install.sh       # 安装后台引擎 + LaunchAgent
open ~/Applications/KeepAwake.app
```

需要 Xcode Command Line Tools (`xcode-select --install`)。

## 使用 / Usage

点击菜单栏的 🌙 月亮图标：

| 菜单项 / Menu Item | 作用 / Effect |
| --- | --- |
| 状态: 空闲 / 保活中 · 至 09:00 | 当前状态 / Current status |
| 保活 1 小时 | 立即保活 60 分钟 / Keep awake for 1 hour |
| 保活到明早 9:00 | 立即保活到次日 09:00 / Until tomorrow 9 AM |
| 无限时长保活 | 永不停止（需手动停） / Indefinite (stop manually) |
| 立即停止 | 解除保活 / Stop now |
| 详细设置… | 打开 SwiftUI 面板（定时、星期、跨天） / Detailed settings |
| 退出 KeepAwake | 完全退出 App / Quit |

### 每周循环示例 / Weekly schedule examples

| 场景 / Scenario | days | startTime | endTime | 含义 / Meaning |
| --- | --- | --- | --- | --- |
| 工作日上班时段 | `[1,2,3,4,5]` | `09:00` | `18:00` | 周一到周五 9:00–18:00 |
| 工作日晚加班 | `[1,2,3,4,5]` | `20:00` | `09:00` | 周一~周五晚 8 点 → 次日早 9 点（**跨天**） |
| 周末全天 | `[6,7]` | `00:00` | `23:59` | 周六、周日整天 |

> 引擎自动识别跨天：`startTime > endTime` 时判定为"今天晚 → 次日早"。
> Cross-midnight schedules are auto-detected: when `startTime > endTime`, the engine treats it as "tonight → tomorrow morning".

## 工作原理 / How it works

```
┌────────────────┐    JSON 配置    ┌────────────────────┐
│  KeepAwake.app │ ──────────────► │ LaunchAgent 守护的 │
│  (菜单栏 App)   │ ◄────────────── │ keep-awake.sh     │
└────────────────┘   caffeinate PID └────────┬───────────┘
                                             │
                                             ▼
                                    ┌─────────────────┐
                                    │ caffeinate -dis  │
                                    │ (阻止睡眠 + 锁屏) │
                                    └─────────────────┘
```

- `caffeinate -dis` 阻止显示器、系统空闲、系统睡眠（合盖）
- `pmset displaysleepnow` 触发屏幕锁定（黑屏，但机器仍 awake）
- LaunchAgent 由 launchd 加载，开机自启、进程异常退出 10 秒后自动重启

## 文件位置 / File locations

| 路径 / Path | 用途 / Purpose |
| --- | --- |
| `~/Applications/KeepAwake.app` | App 主体 |
| `~/Library/Scripts/keep-awake.sh` | 后台保活引擎 |
| `~/Library/LaunchAgents/com.cuinspace.keep-awake.plist` | LaunchAgent 配置 |
| `~/Library/Logs/keep-awake.log` | 引擎日志 |
| `~/.config/keep-awake.json` | 调度配置 |

## 卸载 / Uninstall

```bash
# 一行命令：卸载后台引擎
bash "/Applications/KeepAwake.app/Contents/Resources/InstallHelper/install.sh" --uninstall

# 然后删除 App
rm -rf ~/Applications/KeepAwake.app
rm -rf ~/.config/keep-awake.json ~/.config/keep-awake.pid
```

## 常见问题 / FAQ

**Q：保活期间屏幕黑了，是否影响远程 SSH？**
A：不影响。`pmset displaysleepnow` 只关显示器，CPU、Wi-Fi、SSH 连接全部继续。移动鼠标即可唤醒屏幕。

**Q：和 macOS 自带的 `caffeinate -t 3600` 有什么区别？**
A：KeepAwake 支持定时调度（每周循环）、跨天时间段、自动锁屏、统一管理多个开关。

**Q：合盖时还能保活吗？**
A：本 App 设计为**开盖 + 锁屏**场景（CPU 持续运行、屏幕黑），更适合长时间任务。合盖时系统会强制睡眠，无法绕过。

**Q：怎么验证保活真的生效？**
A：在终端跑 `bash ~/Library/Scripts/keep-awake.sh --status`，应看到 `caffeinate running: yes`。

## 安全 / Security

- DMG 内的 App 是 **ad-hoc 签名**（无 Apple Developer 账号），未做 Apple 公证
- 首次启动需右键打开或去系统设置允许
- 后台引擎是 **只读 JSON + 调用系统 `caffeinate`**，无网络通信
- 完整源码公开，可审计

## 开发 / Development

```bash
bash build.sh         # 编译
bash package.sh       # 打包成 build/KeepAwake-v1.0.dmg
```

技术栈：Swift + SwiftUI + AppKit，标准 `swiftc` 编译（不依赖 Xcode 工程）。

## License

MIT
