import SwiftUI

struct SettingsView: View {
    @State private var oneShotMinutes: Int = 60
    @State private var oneShotInfinite: Bool = false
    @State private var autoLock: Bool = true

    @State private var weeklyEnabled: Bool = false
    @State private var weeklyDays: Set<Int> = [1, 2, 3, 4, 5]
    @State private var weeklyStart: Date = defaultTime(hour: 9, minute: 0)
    @State private var weeklyEnd: Date = defaultTime(hour: 18, minute: 0)

    @State private var status: String = "加载中…"
    @State private var caffeinateRunning: Bool = false

    private let dayLabels = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: caffeinateRunning ? "moon.zzz.fill" : "moon.zzz")
                    .foregroundColor(caffeinateRunning ? .blue : .secondary)
                Text("KeepAwake").font(.headline)
                Spacer()
                Text(status).font(.caption).foregroundColor(.secondary)
            }

            Divider()

            // 立即保活
            GroupBox(label: Text("立即保活").font(.subheadline)) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Stepper(value: $oneShotMinutes, in: 5...600, step: 5) {
                            Text("\(oneShotMinutes) 分钟")
                        }
                        Toggle("无限时长", isOn: $oneShotInfinite)
                            .toggleStyle(.checkbox)
                    }
                    HStack {
                        Button("启动") { startOneShot() }
                            .buttonStyle(.borderedProminent)
                        Button("立即停止") { stopKeepAwake() }
                            .buttonStyle(.bordered)
                    }
                }.padding(.vertical, 4)
            }

            // 每周循环
            GroupBox(label: Text("每周循环").font(.subheadline)) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("启用", isOn: $weeklyEnabled)
                        .onChange(of: weeklyEnabled) { _, v in writeWeekly() }
                    HStack(spacing: 6) {
                        ForEach(1...7, id: \.self) { d in
                            Toggle(dayLabels[d - 1], isOn: Binding(
                                get: { weeklyDays.contains(d) },
                                set: { on in
                                    if on { weeklyDays.insert(d) } else { weeklyDays.remove(d) }
                                    writeWeekly()
                                }
                            ))
                            .toggleStyle(.button)
                            .font(.caption)
                        }
                    }
                    HStack {
                        DatePicker("开始", selection: $weeklyStart,
                                   displayedComponents: .hourAndMinute)
                            .onChange(of: weeklyStart) { _, _ in writeWeekly() }
                        DatePicker("结束", selection: $weeklyEnd,
                                   displayedComponents: .hourAndMinute)
                            .onChange(of: weeklyEnd) { _, _ in writeWeekly() }
                    }
                }.padding(.vertical, 4)
            }

            // 全局选项
            Toggle("保活时自动锁屏", isOn: $autoLock)
                .onChange(of: autoLock) { _, v in writeAutoLock(v) }

            Divider()

            HStack {
                Button("退出") { NSApp.terminate(nil) }
                    .buttonStyle(.bordered)
                Spacer()
                Button("刷新状态") { reloadStatus() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(width: 360)
        .onAppear { reloadConfig() }
    }

    // MARK: - 行为

    private func startOneShot() {
        let mins = oneShotInfinite ? 0 : oneShotMinutes
        runShell(KEEP_AWAKE_SCRIPT, ["--now", "\(mins)"])
        // 同步写 local JSON（daemon 会通过 kickstart 重读）
        writeOneShot(active: true, minutes: mins)
        reloadStatus()
    }

    private func stopKeepAwake() {
        runShell(KEEP_AWAKE_SCRIPT, ["--stop"])
        writeOneShot(active: false, minutes: 0)
        reloadStatus()
    }

    private func writeOneShot(active: Bool, minutes: Int) {
        let path = KEEP_AWAKE_CONFIG
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        var oneShot = (json["oneShot"] as? [String: Any]) ?? [:]
        oneShot["active"] = active
        oneShot["durationMinutes"] = minutes
        if active {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            oneShot["startAt"] = fmt.string(from: Date())
        }
        json["oneShot"] = oneShot
        if let out = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? out.write(to: URL(fileURLWithPath: path))
        }
    }

    private func writeWeekly() {
        let path = KEEP_AWAKE_CONFIG
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let fmt = DateFormatter(); fmt.dateFormat = "HH:mm"
        let weekly: [String: Any] = [
            "enabled": weeklyEnabled,
            "days": weeklyDays.sorted(),
            "startTime": fmt.string(from: weeklyStart),
            "endTime": fmt.string(from: weeklyEnd),
        ]
        json["weekly"] = weekly
        if let out = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? out.write(to: URL(fileURLWithPath: path))
        }
        kickDaemon()
    }

    private func writeAutoLock(_ v: Bool) {
        let path = KEEP_AWAKE_CONFIG
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        json["autoLockScreen"] = v
        if let out = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? out.write(to: URL(fileURLWithPath: path))
        }
    }

    private func kickDaemon() {
        let uid = getuid()
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["kickstart", "-k", "gui/\(uid)/com.cuinspace.keep-awake"]
        try? task.run()
    }

    private func reloadConfig() {
        let path = KEEP_AWAKE_CONFIG
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        autoLock = (json["autoLockScreen"] as? Bool) ?? true
        if let oneShot = json["oneShot"] as? [String: Any] {
            oneShotMinutes = (oneShot["durationMinutes"] as? Int) ?? 60
            oneShotInfinite = oneShotMinutes == 0
        }
        if let weekly = json["weekly"] as? [String: Any] {
            weeklyEnabled = (weekly["enabled"] as? Bool) ?? false
            weeklyDays = Set((weekly["days"] as? [Int]) ?? [1, 2, 3, 4, 5])
            let fmt = DateFormatter(); fmt.dateFormat = "HH:mm"
            if let s = weekly["startTime"] as? String, let d = fmt.date(from: s) { weeklyStart = d }
            if let e = weekly["endTime"] as? String, let d = fmt.date(from: e) { weeklyEnd = d }
        }
        reloadStatus()
    }

    private func reloadStatus() {
        let pidFile = KEEP_AWAKE_PIDFILE
        if let pidStr = try? String(contentsOfFile: pidFile, encoding: .utf8),
           let pid = Int(pidStr.trimmingCharacters(in: .whitespacesAndNewlines)),
           kill(pid_t(pid), 0) == 0 {
            caffeinateRunning = true
            status = "保活中"
        } else {
            caffeinateRunning = false
            status = "空闲"
        }
    }
}

private func defaultTime(hour: Int, minute: Int) -> Date {
    var comps = DateComponents()
    comps.hour = hour
    comps.minute = minute
    return Calendar.current.date(from: comps) ?? Date()
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