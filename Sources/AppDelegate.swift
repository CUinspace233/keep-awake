import AppKit
import SwiftUI
import Sparkle

// 显式 _main 入口，避免 SwiftUI App 自动创建主菜单栏/Dock 图标
@_cdecl("main")
public func main(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>>) -> Int32 {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
    return 0
}

// 纯 AppKit 入口 + AppDelegate 适配器，不创建 SwiftUI Scene
// 路径常量：用 NSHomeDirectory() 拼接，确保 App 在任何 macOS 用户下都能正确工作
let KEEP_AWAKE_HOME = NSHomeDirectory()
let KEEP_AWAKE_SCRIPT = "\(NSHomeDirectory())/Library/Scripts/keep-awake.sh"
let KEEP_AWAKE_PIDFILE = "\(NSHomeDirectory())/.config/keep-awake.pid"
let KEEP_AWAKE_CONFIG = "\(NSHomeDirectory())/.config/keep-awake.json"

class AppDelegate: NSObject, NSApplicationDelegate {
    private var updaterController: SPUStandardUpdaterController!
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var settingsWindow: NSWindow!
    private var settingsView: SettingsView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // 检测后台引擎是否已装
        if !FileManager.default.fileExists(atPath: KEEP_AWAKE_SCRIPT) {
            showInstallAlert()
        }

        // 菜单栏图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "moon.zzz", accessibilityDescription: "KeepAwake")
            button.image?.isTemplate = true
            button.target = self
            button.action = nil  // 由 menu 自己处理 click
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // 构菜单
        buildMenu()

        // 构设置窗口（备用，菜单里"详细设置"打开）
        settingsView = SettingsView()

        // 启动后轮询 caffeinate 状态
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refreshStatusIcon()
        }
        refreshStatusIcon()

        // Sparkle 自动升级（启动时异步检查，菜单可手动触发）
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    private func buildMenu() {
        let m = NSMenu()
        m.autoenablesItems = false

        let header = NSMenuItem(title: "🌙 KeepAwake", action: nil, keyEquivalent: "")
        header.isEnabled = false
        m.addItem(header)

        let statusItemMenu = NSMenuItem(title: "状态: 检测中…", action: nil, keyEquivalent: "")
        statusItemMenu.isEnabled = false
        statusItemMenu.tag = 100
        m.addItem(statusItemMenu)

        m.addItem(NSMenuItem.separator())

        // 立即保活 1h
        let oneHour = NSMenuItem(title: "保活 1 小时", action: #selector(startForMinutes(_:)), keyEquivalent: "")
        oneHour.target = self
        oneHour.tag = 60
        m.addItem(oneHour)

        // 立即保活直到本周末
        let untilMorning = NSMenuItem(title: "保活到明早 9:00", action: #selector(startUntilMorning(_:)), keyEquivalent: "")
        untilMorning.target = self
        m.addItem(untilMorning)

        // 无限
        let infinite = NSMenuItem(title: "无限时长保活", action: #selector(startInfinite(_:)), keyEquivalent: "")
        infinite.target = self
        m.addItem(infinite)

        m.addItem(NSMenuItem.separator())

        let stop = NSMenuItem(title: "立即停止", action: #selector(stopKeepAwake(_:)), keyEquivalent: "")
        stop.target = self
        m.addItem(stop)

        m.addItem(NSMenuItem.separator())

        let openSettings = NSMenuItem(title: "详细设置…", action: #selector(openSettings(_:)), keyEquivalent: "")
        openSettings.target = self
        m.addItem(openSettings)

        let checkUpdate = NSMenuItem(title: "检查更新…", action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        checkUpdate.target = self
        m.addItem(checkUpdate)

        let quit = NSMenuItem(title: "退出 KeepAwake", action: #selector(quitApp(_:)), keyEquivalent: "q")
        quit.target = self
        m.addItem(quit)

        statusItem.menu = m
        self.menu = m

        // 点击 status item 显示菜单（macOS 默认行为：statusItem 有 menu 就自动显示）
    }

    private func refreshStatusIcon() {
        guard let button = statusItem.button else { return }
        let running = isCaffeinateRunning()
        let oneShotActive = readJSONBool(path: configPath(), key: ".oneShot.active")
        let weeklyEnabled = readJSONBool(path: configPath(), key: ".weekly.enabled")

        let symbolName: String
        if running && oneShotActive {
            symbolName = "moon.zzz.fill"
        } else if running && weeklyEnabled {
            symbolName = "calendar.badge.clock"
        } else if running {
            symbolName = "moon.zzz.fill"
        } else {
            symbolName = "moon.zzz"
        }
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "KeepAwake")
        button.image?.isTemplate = true

        // 同步菜单里的状态文字
        if let statusMenuItem = menu?.item(withTag: 100) {
            if running {
                let untilStr = readUntilString()
                statusMenuItem.title = "状态: 保活中" + (untilStr.isEmpty ? "" : " · \(untilStr)")
            } else {
                statusMenuItem.title = "状态: 空闲"
            }
        }
    }

    private func readUntilString() -> String {
        let path = configPath()
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ""
        }
        // oneShot 优先
        if let oneShot = json["oneShot"] as? [String: Any],
           (oneShot["active"] as? Bool) == true,
           let startAt = oneShot["startAt"] as? String {
            let dur = (oneShot["durationMinutes"] as? Int) ?? 0
            if dur == 0 { return "无限" }
            let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            if let startDate = fmt.date(from: startAt) {
                let endDate = startDate.addingTimeInterval(TimeInterval(dur * 60))
                let outFmt = DateFormatter(); outFmt.dateFormat = "HH:mm"
                return "至 \(outFmt.string(from: endDate))"
            }
        }
        return ""
    }

    @objc private func startForMinutes(_ sender: NSMenuItem) {
        runShell(KEEP_AWAKE_SCRIPT, ["--now", "\(sender.tag)"])
        refreshStatusIcon()
    }

    @objc private func startInfinite(_ sender: NSMenuItem?) {
        runShell(KEEP_AWAKE_SCRIPT, ["--now", "0"])
        refreshStatusIcon()
    }

    @objc private func startUntilMorning(_ sender: NSMenuItem?) {
        // 算到明早 9:00 的分钟数
        let now = Date()
        let cal = Calendar.current
        var components = cal.dateComponents([.year, .month, .day], from: now)
        components.hour = 9
        components.minute = 0
        let tomorrow9 = cal.date(byAdding: .day, value: 1, to: cal.date(from: components)!)!
        let minutes = Int(tomorrow9.timeIntervalSince(now) / 60)
        runShell(KEEP_AWAKE_SCRIPT, ["--now", "\(minutes)"])
        refreshStatusIcon()
    }

    @objc private func stopKeepAwake(_ sender: NSMenuItem?) {
        runShell(KEEP_AWAKE_SCRIPT, ["--stop"])
        refreshStatusIcon()
    }

    @objc private func openSettings(_ sender: NSMenuItem?) {
        if settingsWindow == nil {
            let host = NSHostingController(rootView: settingsView)
            let win = NSWindow(contentViewController: host)
            win.title = "KeepAwake 设置"
            win.styleMask = [.titled, .closable]
            win.setContentSize(NSSize(width: 380, height: 540))
            win.center()
            settingsWindow = win
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow.makeKeyAndOrderFront(nil)
    }

    @objc private func checkForUpdates(_ sender: NSMenuItem?) {
        updaterController.checkForUpdates(sender)
    }

    @objc private func quitApp(_ sender: NSMenuItem?) {
        NSApp.terminate(nil)
    }

    private func showInstallAlert() {
        let helper = Bundle.main.resourcePath.map { "\($0)/InstallHelper/install.sh" } ?? ""
        let alert = NSAlert()
        alert.messageText = "需要完成一次性安装"
        alert.informativeText = "KeepAwake 需要一个后台脚本来控制 caffeinate。由于 macOS 安全限制，App 无法自行安装。请打开「终端」并粘贴下面的命令（已自动复制到剪贴板）：\n\nbash \(helper)\n\n安装完成后重新启动 KeepAwake 即可。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        _ = alert.runModal()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("bash \(helper)", forType: .string)
    }

    private func runShell(_ launchPath: String, _ args: [String]) {
        let task = Process()
        task.launchPath = launchPath
        task.arguments = args
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
    }

    private func isCaffeinateRunning() -> Bool {
        let pidFile = KEEP_AWAKE_PIDFILE
        guard let pidStr = try? String(contentsOfFile: pidFile, encoding: .utf8),
              let pid = Int(pidStr.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        return kill(pid_t(pid), 0) == 0
    }

    private func configPath() -> String {
        KEEP_AWAKE_CONFIG
    }
}

// MARK: - 工具
func readJSONBool(path: String, key: String) -> Bool {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return false
    }
    // 支持 ".oneShot.active" 路径
    let parts = key.split(separator: ".").map { String($0) }
    var cur: Any? = json
    for p in parts where p != "" {
        guard let dict = cur as? [String: Any], let next = dict[p] else { return false }
        cur = next
    }
    return (cur as? Bool) ?? false
}