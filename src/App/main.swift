import AppKit
import WidgetKit
import Foundation

/// 메뉴 막대에 상주하면서 주기적으로 collect.py 를 돌리고,
/// 결과를 App Group 컨테이너에 써서 위젯이 읽어가게 한다.
/// (위젯 익스텐션은 샌드박스라 ~/.claude/projects 를 직접 못 읽는다.)
final class Controller: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var usage: Usage?
    private var lastError: String?
    private var refreshing = false
    private var panel: PanelWindow?
    private var panelVisible = UserDefaults.standard.object(forKey: "panelVisible") as? Bool ?? true

    /// 집계 스크립트는 앱 번들 안에 함께 설치된다. 소스 트리를 어디로 옮겨도 동작한다.
    private let script = Bundle.main.url(forResource: "collect", withExtension: "py")?.path
        ?? NSString(string: "~/.claude/widgets/ccusage/collect.py").expandingTildeInPath
    private let agentPlist = NSString(string: "~/Library/LaunchAgents/local.ccusage.widget.plist").expandingTildeInPath

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Claude Code 사용량")
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        if panelVisible { showPanel() }

        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    // MARK: 데이터

    private func refresh() {
        guard !refreshing else { return }
        refreshing = true
        let path = script

        DispatchQueue.global(qos: .utility).async {
            let (data, err) = Controller.run(path)
            var parsed: Usage?
            if let data {
                parsed = try? JSONDecoder().decode(Usage.self, from: data)
                if parsed != nil { try? SnapshotStore.write(data) }
            }

            DispatchQueue.main.async {
                self.refreshing = false
                if let parsed {
                    self.usage = parsed
                    self.lastError = nil
                    WidgetCenter.shared.reloadAllTimelines()
                } else {
                    self.lastError = err ?? "집계 결과를 해석하지 못했습니다"
                }
                self.updateStatusTitle()
                self.panel?.update(self.usage) { [weak self] in self?.refresh() }
            }
        }
    }

    private static func run(_ path: String) -> (Data?, String?) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["python3", path]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do {
            try p.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let errData = err.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else {
                let msg = String(data: errData, encoding: .utf8) ?? ""
                return (nil, msg.isEmpty ? "collect.py 종료 코드 \(p.terminationStatus)" : String(msg.suffix(200)))
            }
            return (data, nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    private func updateStatusTitle() {
        guard let button = statusItem.button else { return }
        if let b = usage?.block, b.active {
            button.title = " " + Fmt.cost(b.cost)
        } else if usage != nil {
            button.title = ""
        } else {
            button.title = " —"
        }
    }

    // MARK: 메뉴

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if let u = usage {
            if let b = u.block, b.active {
                let left = Fmt.remain(b.end - Date().timeIntervalSince1970)
                menu.addItem(info("현재 5시간 블록  \(Fmt.cost(b.cost))  ·  \(left) 남음"))
            } else {
                menu.addItem(info("현재 블록: 활동 없음"))
            }
            menu.addItem(info("오늘  \(Fmt.cost(u.today.cost))  ·  \(Fmt.tok(u.today.tok))"))
            menu.addItem(info("7일   \(Fmt.cost(u.week.cost))"))
            menu.addItem(info("30일  \(Fmt.cost(u.month.cost))"))
            menu.addItem(.separator())
            menu.addItem(info("갱신 \(Fmt.time(u.generated))"))
        } else if let e = lastError {
            menu.addItem(info("오류: \(e.prefix(60))"))
        } else {
            menu.addItem(info("집계 중…"))
        }

        menu.addItem(.separator())
        add(menu, "지금 새로고침", #selector(doRefresh), key: "r")
        let p = add(menu, "바탕화면 패널 표시", #selector(togglePanel))
        p.state = panelVisible ? .on : .off
        add(menu, "패널 위치 초기화", #selector(resetPanel))
        add(menu, "위젯 추가하는 법…", #selector(showHowTo))
        let login = add(menu, "로그인 시 자동 실행", #selector(toggleLogin))
        login.state = FileManager.default.fileExists(atPath: agentPlist) ? .on : .off
        menu.addItem(.separator())
        add(menu, "종료", #selector(quit), key: "q")
    }

    private func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)])
        return item
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func doRefresh() { refresh() }

    private func showPanel() {
        if panel == nil {
            panel = PanelWindow(usage: usage) { [weak self] in self?.refresh() }
        }
        panel?.orderFront(nil)
    }

    @objc private func togglePanel() {
        panelVisible.toggle()
        UserDefaults.standard.set(panelVisible, forKey: "panelVisible")
        if panelVisible { showPanel() } else { panel?.orderOut(nil) }
    }

    @objc private func resetPanel() { panel?.moveToDefault() }

    @objc private func showHowTo() {
        let a = NSAlert()
        a.messageText = "위젯 추가하기"
        a.informativeText = """
        1. 바탕화면의 빈 곳을 우클릭 → '위젯 편집…'
           (또는 메뉴 막대 시계를 클릭 → 맨 아래 '위젯 편집…')
        2. 왼쪽 목록에서 'CCUsage' 를 선택
        3. 작게 / 보통 / 크게 중 원하는 크기를 바탕화면이나 알림 센터로 끌어다 놓기

        이 앱이 켜져 있어야 위젯 데이터가 갱신됩니다.
        """
        a.addButton(withTitle: "위젯 편집 열기")
        a.addButton(withTitle: "닫기")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Notification Centre.app"))
        }
    }

    @objc private func toggleLogin() {
        let fm = FileManager.default
        if fm.fileExists(atPath: agentPlist) {
            shell("/bin/launchctl", ["bootout", "gui/\(getuid())/local.ccusage.widget"])
            try? fm.removeItem(atPath: agentPlist)
        } else {
            let exe = Bundle.main.executablePath ?? ""
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>
              <key>Label</key><string>local.ccusage.widget</string>
              <key>ProgramArguments</key><array><string>\(exe)</string></array>
              <key>RunAtLoad</key><true/>
              <key>KeepAlive</key><false/>
            </dict></plist>
            """
            try? plist.write(toFile: agentPlist, atomically: true, encoding: .utf8)
            shell("/bin/launchctl", ["bootstrap", "gui/\(getuid())", agentPlist])
        }
    }

    private func shell(_ cmd: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: cmd)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

// --diagnose: chronod 가 이 앱의 위젯을 인식하는지 물어보고 종료한다.
if CommandLine.arguments.contains("--diagnose") {
    print("bundleID   : \(Bundle.main.bundleIdentifier ?? "?")")
    print("bundlePath : \(Bundle.main.bundlePath)")
    print("groupPath  : \(SnapshotStore.containerURL.path)")
    print("snapshot   : \(FileManager.default.fileExists(atPath: SnapshotStore.fileURL.path) ? "있음" : "없음")")
    let sem = DispatchSemaphore(value: 0)
    WidgetCenter.shared.getCurrentConfigurations { result in
        switch result {
        case .success(let infos):
            print("chronod    : 인식됨, 설치된 인스턴스 \(infos.count)개")
            for i in infos { print("   - kind=\(i.kind) family=\(i.family)") }
        case .failure(let e):
            print("chronod    : 오류 -> \(e)  (\((e as NSError).domain) / \((e as NSError).code))")
        }
        sem.signal()
    }
    _ = sem.wait(timeout: .now() + 10)
    exit(0)
}

// 단일 인스턴스 보장: 이미 떠 있으면 조용히 종료
let me = ProcessInfo.processInfo.processIdentifier
if !NSRunningApplication.runningApplications(withBundleIdentifier: "local.ccusage.app")
    .filter({ $0.processIdentifier != me }).isEmpty {
    exit(0)
}

let app = NSApplication.shared
let controller = Controller()
app.delegate = controller
app.setActivationPolicy(.accessory)
objc_setAssociatedObject(app, "ccusage.controller", controller, .OBJC_ASSOCIATION_RETAIN)
app.run()
