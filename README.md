# KeepAwake

> macOS 熄屏保活工具 —— 自定义开始时间、时长、星期，屏幕可黑但 CPU / Wi‑Fi / Terminal 等进程持续工作。
>
> macOS menu-bar keep-awake utility — schedule by start time, duration, weekdays. Screen can sleep, but CPU / Wi-Fi / Terminal keep running.

## 功能 / Features

- 🌙 **菜单栏 App** —— 一键开启/关闭，点图标弹出快捷菜单（NSMenu，紧贴图标无箭头）
- ⏰ **三种调度模式** —— 立即保活 / 定时单次 / 每周循环
- 🌃 **支持跨天** —— 例如 `工作日 22:00 → 次日 09:00` 自动判断为跨天
- 🔒 **自动锁屏** —— 保活期间屏幕可黑（`pmset displaysleepnow`），CPU 继续工作
- 🚀 **开机自启** —— LaunchAgent 守护后台引擎，进程异常退出自动重启
- 🔄 **自动升级** —— Sparkle 集成，菜单里一键检查更新（增量包下载）
- 🪶 **轻量原生** —— Swift + SwiftUI + AppKit，单二进制 ~250 KB

## 系统要求 / Requirements

- macOS 14.0+ (Sonoma 或更新 / Sonoma or newer)
- Apple Silicon / Intel
- 首次启动需要允许"打开未知开发者 App"

## 安装 / Installation

### 方式 1：下载 DMG（推荐 / Recommended）

前往 [Releases](https://github.com/CUinspace233/keep-awake/releases) 下载最新 `KeepAwake-v1.2.dmg`：

1. 双击挂载 DMG
2. 把 `KeepAwake.app` 拖到右边的 `Applications` 快捷方式
3. 启动 `KeepAwake.app` → 弹窗提示
4. **推荐点「打开终端并执行」** —— 自动在 Terminal.app 里跑 install.sh
5. 装好后关 Terminal，重新启动 KeepAwake 即可

> 第一次启动时若系统提示"无法打开，因为它来自身份不明的开发者"，请到「系统设置 → 隐私与安全性」点「仍要打开」。
>
> On first launch, if macOS warns "cannot be opened because the developer cannot be verified", go to **System Settings → Privacy & Security** and click **Open Anyway**.

### 方式 2：从源码构建 / Build from source

```bash
git clone https://github.com/CUinspace233/keep-awake.git
cd keep-awake
bash icons.sh         # 生成 App 图标（可选，需要先下载 Sparkle）
bash build.sh         # 编译 ~/Applications/KeepAwake.app（带 InstallHelper + 图标）
bash install.sh       # 安装后台引擎 + LaunchAgent
open ~/Applications/KeepAwake.app
```

需要 Xcode Command Line Tools (`xcode-select --install`)。

### 方式 3：已有旧版本用户

直接点菜单栏 🌙 → **「检查更新…」**，Sparkle 会自动下载增量包升级。

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
| **检查更新…** | 自动检查新版本（Sparkle） / Check for updates |
| 退出 KeepAwake | 完全退出 App / Quit |

### 每周循环示例 / Weekly schedule examples

| 场景 / Scenario | days | startTime | endTime | 含义 / Meaning |
| --- | --- | --- | --- | --- |
| 工作日上班时段 | `[1,2,3,4,5]` | `09:00` | `18:00` | 周一到周五 9:00–18:00 |
| 工作日晚加班 | `[1,2,3,4,5]` | `22:00` | `09:00` | 周一~周五晚 10 点 → 次日早 9 点（**跨天**） |
| 周末全天 | `[6,7]` | `00:00` | `23:59` | 周六、周日整天 |

> 引擎自动识别跨天：`startTime > endTime` 时判定为"今天晚 → 次日早"。
> Cross-midnight schedules are auto-detected: when `startTime > endTime`, the engine treats it as "tonight → tomorrow morning".

## 工作原理 / How it works

```
┌─────────────────┐    JSON 配置     ┌──────────────────────┐
│  KeepAwake.app  │ ───────────────► │ LaunchAgent 守护的    │
│  (菜单栏 App)    │ ◄─────────────── │ keep-awake.sh        │
└─────────────────┘   caffeinate PID └─────────┬────────────┘
                                               │
                                               ▼
                                      ┌─────────────────┐
                                      │ caffeinate -dis  │
                                      │ (阻止睡眠 + 锁屏) │
                                      └─────────────────┘
```

- `caffeinate -dis` 阻止显示器、系统空闲、系统睡眠
- `pmset displaysleepnow` 触发屏幕锁定（黑屏，但机器仍 awake）
- LaunchAgent 由 launchd 加载，开机自启、进程异常退出 10 秒后自动重启
- Sparkle 通过 GitHub Releases 自动检查 + 下载增量包升级

## 自动升级 / Auto Update

KeepAwake 集成 [Sparkle 2.9.4](https://sparkle-project.org)，使用 EdDSA 签名验证更新来源：

- 菜单 → 「检查更新…」 手动触发
- App 启动时后台异步检查一次
- 更新包来自 GitHub Releases，自动鉴权签名
- 支持**增量包**（v1.1 → v1.2 仅 13 KB）

App 内 `Info.plist` 含：
- `SUPublicEDKey` —— 验证升级包签名
- `SUFeedURL` —— `https://github.com/CUinspace233/keep-awake/releases/latest/download/appcast.xml`

## 文件位置 / File locations

| 路径 / Path | 用途 / Purpose |
| --- | --- |
| `~/Applications/KeepAwake.app` | App 主体（编译产出） |
| `/Applications/KeepAwake.app` | App 主体（DMG 安装） |
| `~/Library/Scripts/keep-awake.sh` | 后台保活引擎 |
| `~/Library/LaunchAgents/com.cuinspace.keep-awake.plist` | LaunchAgent 配置 |
| `~/Library/Logs/keep-awake.log` | 引擎日志（自动轮转 30 天） |
| `~/.config/keep-awake.json` | 调度配置 |

## 卸载 / Uninstall

### 方式 1：DMG 安装包自带卸载器

```bash
bash "/Applications/KeepAwake.app/Contents/Resources/InstallHelper/install.sh" --uninstall
rm -rf /Applications/KeepAwake.app
```

### 方式 2：独立卸载脚本（推荐，无需 App 安装包）

```bash
curl -fsSL https://raw.githubusercontent.com/CUinspace233/keep-awake/main/uninstall.sh | bash
```

或者从本地源码：

```bash
bash uninstall.sh            # 完整卸载
bash uninstall.sh --keep-app # 只卸载后台引擎，保留 App
```

完整卸载会清理：
- GUI App 进程
- LaunchAgent `~/Library/LaunchAgents/com.cuinspace.keep-awake.plist`
- 后台引擎 `~/Library/Scripts/keep-awake.sh`
- 配置 + PID `~/.config/keep-awake.{json,pid}`
- 日志 `~/Library/Logs/keep-awake.*`
- App 本体（`~/Applications/KeepAwake.app` 和 `/Applications/KeepAwake.app`）

## 常见问题 / FAQ

**Q：保活期间屏幕黑了，是否影响远程 SSH？**
A：不影响。`pmset displaysleepnow` 只关显示器，CPU、Wi-Fi、SSH 连接全部继续。移动鼠标即可唤醒屏幕。

**Q：和 macOS 自带的 `caffeinate -t 3600` 有什么区别？**
A：KeepAwake 支持定时调度（每周循环）、跨天时间段、自动锁屏、统一管理多个开关、自动升级。

**Q：合盖时还能保活吗？**
A：本 App 设计为**开盖 + 锁屏**场景（CPU 持续运行、屏幕黑），更适合长时间任务。合盖时系统会强制睡眠，无法绕过（macOS SMC 硬件行为）。

**Q：怎么验证保活真的生效？**
A：在终端跑 `bash ~/Library/Scripts/keep-awake.sh --status`，应看到 `caffeinate running: yes`。

**Q：如何关闭后台引擎但保留 App？**
A：菜单 → 立即停止（仅当前会话）；或卸载 LaunchAgent 后 App 退化为"无后台引擎"模式（仍可手动启动但不会跨进程保活）。

## 安全 / Security

- DMG 内的 App 是 **ad-hoc 签名**（无 Apple Developer 账号），未做 Apple 公证
- 首次启动需右键打开或去系统设置允许
- 后台引擎是 **只读 JSON + 调用系统 `caffeinate`**，无网络通信
- 自动升级用 **Sparkle + EdDSA 签名验证**（公钥嵌入 Info.plist，私钥在 Keychain），确保 DMG 来源可信
- 完整源码公开，可审计

## 开发 / Development

```bash
bash icons.sh         # 生成 App 图标（一次性，已 commit）
bash build.sh         # 编译 ~/Applications/KeepAwake.app
bash package.sh       # 打包 build/KeepAwake-v1.2.dmg + appcast
```

技术栈：
- Swift + SwiftUI + AppKit
- 标准 `swiftc` 编译（不依赖 Xcode 工程）
- Sparkle 2.9.4 自动升级框架
- 后台引擎：纯 Bash + `caffeinate`

## 更新日志 / Changelog

### v1.2 (2026-07-26)
- 🪟 NSAlert 安装引导新增「打开终端并执行」按钮
- 📝 install.sh 跑完后明确提示关闭 Terminal
- 📦 build.sh 自动把 InstallHelper 注入 App bundle
- 🔧 install.sh 用 `launchctl print` 判定 LaunchAgent 启动（修 macOS 26 误报）
- ⚡ Sparkle 增量更新支持（v1.1 → v1.2 仅 13 KB）

### v1.1 (2026-07-25)
- 🔧 日志自动轮转（保留 30 天，单文件 >1MB 时切割）
- 🗑 独立 `uninstall.sh` 脚本
- ✅ 修 install.sh 在 macOS 26 上偶发的"LaunchAgent 加载失败"误报
- 🎨 App 图标 + DMG 卷标图标

### v1.0 (2026-07-25)
- 🎉 首个发布
- 菜单栏 App + 三种调度模式 + 跨天支持 + 自动锁屏

## License

MIT
