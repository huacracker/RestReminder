//
//  休息提醒 RestReminder
//  工作满 1 小时 → 全屏遮盖提醒休息 5 分钟（带倒计时），可「我休息好了」关闭，也可最小化到角落继续倒计时。
//  作者：华哥 / Hermes   2026-10-17
//

import Cocoa
import IOKit.pwr_mgt
import UserNotifications

setvbuf(stdout, nil, _IOLBF, 0)

// MARK: - 多语言文案（系统首选语言为中文 → 中文界面，否则英文）

enum L {
    static let isChinese: Bool = {
        let first = Locale.preferredLanguages.first ?? "en"
        return first.hasPrefix("zh")
    }()

    static func s(_ zh: String, _ en: String) -> String { isChinese ? zh : en }

    static var appName: String { s("休息提醒", "RestReminder") }
    static var greeting: String { s("该休息了 ☕️", "Time to take a break ☕️") }
    static var breakHint: String { s("站起来走动一下 · 看看远处 · 喝口水",
                                     "Stand up · Look into the distance · Drink some water") }
    static var breakTitle: String { s("休息中 ☕️", "Resting ☕️") }
    static var breakSubtitle: String { s("把眼睛从屏幕上挪开一会儿", "Give your eyes a rest from the screen") }
    static var finishButton: String { s("我休息好了", "I'm refreshed") }
    static var minimizeButton: String { s("最小化", "Minimize") }
    static var keyHint: String { s("ESC 结束休息　·　空格 最小化　·　倒计时结束自动关闭",
                                   "ESC finish　·　Space minimize　·　Auto-closes when the timer ends") }
    static func miniBreak(_ clock: String) -> String { s("☕️ 休息 \(clock)", "☕️ Break \(clock)") }

    static var menuPaused: String { s("已暂停计时", "Paused") }
    static func menuNextBreak(_ t: String) -> String { s("距离下次休息 \(t)", "Next break in \(t)") }
    static func menuBreaking(_ t: String) -> String { s("休息中 \(t)", "On break \(t)") }
    static var menuBreakNow: String { s("现在就去休息", "Take a break now") }
    static var menuEndBreak: String { s("结束这次休息", "End this break") }
    static var menuPause: String { s("暂停计时", "Pause timer") }
    static var menuResume: String { s("继续计时", "Resume timer") }
    static var menuReset: String { s("重新开始这一轮", "Restart this cycle") }
    static var menuWorkInterval: String { s("工作间隔", "Work interval") }
    static var menuBreakLength: String { s("休息时长", "Break length") }
    static var menuAllScreens: String { s("遮盖所有屏幕", "Cover all screens") }
    static var menuSound: String { s("提示音", "Sound") }
    static var menuVoice: String { s("语音叮嘱", "Voice reminder") }
    static var menuAutoStart: String { s("开机自动启动", "Launch at login") }
    static var menuQuit: String { s("退出休息提醒", "Quit RestReminder") }

    static func intervalLabel(_ m: Int) -> String {
        switch m {
        case 60: return s("1 小时", "1 hour")
        case 90: return s("1.5 小时", "1.5 hours")
        case 120: return s("2 小时", "2 hours")
        default: return s("\(m) 分钟", "\(m) min")
        }
    }

    static var notifyBreakTitle: String { s("该休息了 ☕️", "Time to take a break ☕️") }
    static func notifyBreakBody(_ workMin: String, _ breakMin: String) -> String {
        s("工作已满 \(workMin) 分钟，离开屏幕 \(breakMin) 分钟吧", "You've worked \(workMin). Step away from the screen for \(breakMin).")
    }
    static var notifyDoneTitle: String { s("休息结束 ✅", "Break is over ✅") }
    static func notifyDoneBody(_ workMin: String) -> String {
        s("回到工作状态，下次提醒 \(workMin) 后", "Back to work — next reminder in \(workMin).")
    }
    static var sayBreak: String { s("该休息了，站起来走动走动，看看远处", "Time to take a break. Stand up and look into the distance.") }
    static var sayDone: String { s("休息结束，继续加油", "Break is over. Back to work.") }
}

// MARK: - 设置

enum K {
    static let work = "workMinutes"
    static let rest = "breakMinutes"
    static let allScreens = "coverAllScreens"
    static let sound = "soundEnabled"
    static let voice = "voiceEnabled"
    static let autoStart = "autoStartEnabled"
}

enum Phase { case working, breaking }

func clockString(_ t: TimeInterval) -> String {
    let s = Int(max(0, t.rounded(.up)))
    return String(format: "%d:%02d", s / 60, s % 60)
}

func workString(_ t: TimeInterval) -> String {
    let m = Int((max(0, t) / 60).rounded(.up))
    if m >= 60 { return String(format: "%dh%02dm", m / 60, m % 60) }
    return "\(m)m"
}

enum Settings {
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            K.work: 60.0,
            K.rest: 5.0,
            K.allScreens: true,
            K.sound: true,
            K.voice: false,
            K.autoStart: false,
        ])
    }
    static var workSeconds: TimeInterval { max(0.05, UserDefaults.standard.double(forKey: K.work)) * 60 }
    static var breakSeconds: TimeInterval { max(0.05, UserDefaults.standard.double(forKey: K.rest)) * 60 }
    static var coverAllScreens: Bool { UserDefaults.standard.bool(forKey: K.allScreens) }
    static var sound: Bool { UserDefaults.standard.bool(forKey: K.sound) }
    static var voice: Bool { UserDefaults.standard.bool(forKey: K.voice) }
    static var autoStart: Bool { UserDefaults.standard.bool(forKey: K.autoStart) }
}

// MARK: - 圆形进度环

final class RingView: NSView {
    /// 剩余比例 1 → 0（满环起步，随时间消退）
    var progress: CGFloat = -1 { didSet { if abs(progress - oldValue) > 0.001 { needsDisplay = true } } }
    let timeLabel = NSTextField(labelWithString: "5:00")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 64, weight: .semibold)
        timeLabel.textColor = .white
        timeLabel.alignment = .center
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(timeLabel)
        NSLayoutConstraint.activate([
            timeLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override func draw(_ dirtyRect: NSRect) {
        let lineWidth: CGFloat = 16
        let radius = min(bounds.width, bounds.height) / 2 - lineWidth / 2 - 2
        guard radius > 0 else { return }
        let center = NSPoint(x: bounds.midX, y: bounds.midY)

        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = lineWidth
        NSColor.white.withAlphaComponent(0.10).setStroke()
        track.stroke()

        if progress > 0.001 {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius,
                          startAngle: 90, endAngle: 90 - 360 * min(1, progress), clockwise: true)
            arc.lineWidth = lineWidth
            arc.lineCapStyle = .round
            NSColor.white.withAlphaComponent(0.88).setStroke()
            arc.stroke()
        }
    }
}

// MARK: - 遮盖窗口内容（主屏）

final class CoverView: NSView {
    var onFinish: (() -> Void)?
    var onMinimize: (() -> Void)?
    let ring = RingView()

    init(primary: Bool) {
        super.init(frame: .zero)
        wantsLayer = true

        // 背景：毛玻璃 + 深色遮罩
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blur)
        let dim = NSView()
        dim.wantsLayer = true
        dim.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        dim.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dim)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 28
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        if primary {
            ring.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(makeLabel(L.greeting, size: 34, weight: .bold, alpha: 1))
            stack.addArrangedSubview(ring)
            stack.addArrangedSubview(makeLabel(L.breakHint, size: 19, weight: .regular, alpha: 0.85))

            let buttons = NSStackView()
            buttons.orientation = .horizontal
            buttons.spacing = 16
            let finish = makeButton(L.finishButton, bg: NSColor.white.withAlphaComponent(0.92), fg: NSColor.black, sel: #selector(finishTapped))
            let mini = makeButton(L.minimizeButton, bg: NSColor.white.withAlphaComponent(0.14), fg: NSColor.white, sel: #selector(minimizeTapped))
            buttons.addArrangedSubview(finish)
            buttons.addArrangedSubview(mini)
            stack.addArrangedSubview(buttons)

            stack.addArrangedSubview(makeLabel(L.keyHint, size: 13, weight: .regular, alpha: 0.55))

            NSLayoutConstraint.activate([
                ring.widthAnchor.constraint(equalToConstant: 260),
                ring.heightAnchor.constraint(equalToConstant: 260),
            ])
        } else {
            stack.addArrangedSubview(makeLabel(L.breakTitle, size: 28, weight: .semibold, alpha: 0.9))
            stack.addArrangedSubview(makeLabel(L.breakSubtitle, size: 17, weight: .regular, alpha: 0.6))
        }

        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            dim.leadingAnchor.constraint(equalTo: leadingAnchor),
            dim.trailingAnchor.constraint(equalTo: trailingAnchor),
            dim.topAnchor.constraint(equalTo: topAnchor),
            dim.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 640),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override var acceptsFirstResponder: Bool { true }

    private func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = NSColor.white.withAlphaComponent(alpha)
        l.alignment = .center
        return l
    }

    private func makeButton(_ title: String, bg: NSColor, fg: NSColor, sel: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: sel)
        b.isBordered = false
        b.wantsLayer = true
        b.layer?.backgroundColor = bg.cgColor
        b.layer?.cornerRadius = 12
        b.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: fg,
            .font: NSFont.systemFont(ofSize: 17, weight: .semibold),
        ])
        b.focusRingType = .none
        b.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            b.widthAnchor.constraint(equalToConstant: 168),
            b.heightAnchor.constraint(equalToConstant: 46),
        ])
        return b
    }

    @objc private func finishTapped() { onFinish?() }
    @objc private func minimizeTapped() { onMinimize?() }
}

// MARK: - 遮盖窗口

final class CoverWindow: NSWindow {
    let isPrimaryScreen: Bool
    var onEscape: (() -> Void)?
    var onSpace: (() -> Void)?
    private var coverRef: CoverView?

    init(screen: NSScreen, primary: Bool) {
        isPrimaryScreen = primary
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        setFrame(screen.frame, display: false)

        let cover = CoverView(primary: primary)
        cover.frame = NSRect(origin: .zero, size: screen.frame.size)
        cover.autoresizingMask = [.width, .height]
        cover.onFinish = { [weak self] in self?.onEscape?() }
        cover.onMinimize = { [weak self] in self?.onSpace?() }
        coverRef = cover
        contentView = cover
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onEscape?()            // ESC
        case 49: onSpace?()             // 空格
        default: super.keyDown(with: event)
        }
    }

    var ringText: String? { coverRef?.ring.timeLabel.stringValue }

    func apply(progress: CGFloat, remaining: TimeInterval) {
        guard let cover = coverRef else { return }
        if isPrimaryScreen {
            cover.ring.progress = progress
            cover.ring.timeLabel.stringValue = clockString(remaining)
        } else if let secondary = cover.subviews.compactMap({ $0 as? NSStackView }).first?.arrangedSubviews.compactMap({ $0 as? NSTextField }).first {
            secondary.stringValue = L.breakTitle + "　" + clockString(remaining)
        }
    }
}

// MARK: - 最小化后的小悬浮条

final class MiniWindow: NSPanel {
    var onClick: (() -> Void)?
    private let label = NSTextField(labelWithString: "")

    init() {
        let size = NSSize(width: 224, height: 58)
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true

        let bg = NSView(frame: NSRect(origin: .zero, size: size))
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
        bg.layer?.cornerRadius = 18
        bg.layer?.borderWidth = 1
        bg.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor

        label.font = .monospacedDigitSystemFont(ofSize: 18, weight: .semibold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: bg.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: bg.centerYAnchor),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(clicked))
        bg.addGestureRecognizer(click)
        contentView = bg
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    @objc private func clicked() { onClick?() }

    func update(remaining: TimeInterval) {
        label.stringValue = L.miniBreak(clockString(remaining))
    }

    var debugText: String { label.stringValue }

    func placeBottomRight() {
        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        let size = frame.size
        setFrameOrigin(NSPoint(x: f.maxX - size.width - 24, y: f.minY + 24))
    }
}

// MARK: - 主程序

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {

    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var phase: Phase = .working
    private var deadline = Date()
    private var pausedRemaining: TimeInterval?
    private var workSeconds: TimeInterval = 3600
    private var breakSeconds: TimeInterval = 300
    private var covers: [CoverWindow] = []
    private var mini: MiniWindow?
    private var assertion: IOPMAssertionID = 0
    private var sleeping = false

    // MARK: 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.registerDefaults()
        workSeconds = Settings.workSeconds
        breakSeconds = Settings.breakSeconds

        setupNotifications()
        setupStatusItem()

        phase = .working
        deadline = Date().addingTimeInterval(workSeconds)
        timer = Timer.scheduledTimer(timeInterval: 0.2, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer!, forMode: .common)

        let ud = UserDefaults.standard
        if ud.object(forKey: "workMinutes") != nil { }
        log("started work=\(workSeconds)s break=\(breakSeconds)s screens=\(NSScreen.screens.count)")

        if ud.bool(forKey: "selftest") { runSelfTest() }
        if let shot = ud.string(forKey: "snapshot"), !shot.isEmpty {
            runSnapshot(shot, mini: ud.bool(forKey: "snapshotMini"))
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        releaseSleepAssertion()
    }

    private func log(_ s: String) { print("[RestReminder] \(s)") }

    // MARK: 状态栏

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let img = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: L.appName) {
                img.isTemplate = true
                button.image = img
                button.imagePosition = .imageLeading
            }
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.title = " \(workString(workSeconds))"
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    private func updateStatusTitle() {
        guard let button = statusItem?.button else { return }
        if pausedRemaining != nil {
            button.title = " ⏸"
            return
        }
        let left = currentRemaining()
        if phase == .working {
            button.title = " \(workString(left))"
        } else {
            button.title = " \(clockString(left))"
        }
    }

    // MARK: 计时

    private func currentRemaining() -> TimeInterval {
        if let p = pausedRemaining { return p }
        return max(0, deadline.timeIntervalSinceNow)
    }

    @objc private func tick() {
        if pausedRemaining != nil { return }
        let left = deadline.timeIntervalSinceNow
        if left <= 0 {
            if phase == .working {
                beginBreak()
            } else {
                finishBreak(manual: false)
            }
            return
        }
        updateStatusTitle()
        if phase == .breaking {
            let total = breakSeconds
            let progress = total > 0 ? CGFloat(left / total) : 0
            for w in covers { w.apply(progress: progress, remaining: left) }
            mini?.update(remaining: left)
        }
    }

    private func startWork() {
        phase = .working
        pausedRemaining = nil
        workSeconds = Settings.workSeconds
        deadline = Date().addingTimeInterval(workSeconds)
        updateStatusTitle()
        statusItem?.button?.appearsDisabled = false
    }

    // MARK: 休息

    private func beginBreak() {
        phase = .breaking
        pausedRemaining = nil
        breakSeconds = Settings.breakSeconds
        deadline = Date().addingTimeInterval(breakSeconds)
        log("break start (\(breakSeconds)s)")
        playSound(breakStart: true)

        showCovers()
        updateStatusTitle()
        holdDisplayAwake()
    }

    private func showCovers() {
        closeCovers()
        let screens = Settings.coverAllScreens ? NSScreen.screens : [NSScreen.main ?? NSScreen.screens[0]]
        let mainScreen = NSScreen.main
        for screen in screens {
            let primary = (mainScreen == nil) || (screen == mainScreen) || (screens.count == 1)
            let w = CoverWindow(screen: screen, primary: primary)
            w.onEscape = { [weak self] in self?.finishBreak(manual: true) }
            w.onSpace = { [weak self] in self?.minimizeBreak() }
            w.apply(progress: 1, remaining: breakSeconds)
            w.orderFrontRegardless()
            covers.append(w)
        }
        if let first = covers.first(where: { $0.isPrimaryScreen }) ?? covers.first {
            first.makeKeyAndOrderFront(nil)
            first.makeFirstResponder(first.contentView)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func minimizeBreak() {
        guard phase == .breaking else { return }
        for w in covers { w.orderOut(nil) }
        if mini == nil {
            let m = MiniWindow()
            m.onClick = { [weak self] in self?.restoreBreak() }
            mini = m
        }
        mini?.update(remaining: currentRemaining())
        mini?.placeBottomRight()
        mini?.orderFrontRegardless()
        log("break minimized")
    }

    private func restoreBreak() {
        guard phase == .breaking else { return }
        mini?.orderOut(nil)
        mini = nil
        showCovers()
        log("break restored")
    }

    private func finishBreak(manual: Bool) {
        log("break \(manual ? "closed manually" : "finished")")
        closeCovers()
        releaseSleepAssertion()
        if manual { playSound(breakStart: false) }
        startWork()
    }

    private func closeCovers() {
        for w in covers { w.orderOut(nil) }
        covers.removeAll()
        mini?.orderOut(nil)
        mini = nil
        NSApp.hide(nil)
    }

    // MARK: 声音 / 通知 / 屏幕

    private func playSound(breakStart: Bool) {
        if Settings.sound {
            NSSound(named: NSSound.Name(breakStart ? "Glass" : "Ping"))?.play()
        }
        if Settings.voice {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            p.arguments = breakStart ? [L.sayBreak] : [L.sayDone]
            try? p.run()
        }
        notify(breakStart ? L.notifyBreakTitle : L.notifyDoneTitle,
               breakStart ? L.notifyBreakBody("\(Int(workSeconds / 60))", "\(Int(breakSeconds / 60))")
                          : L.notifyDoneBody("\(Int(Settings.workSeconds / 60))"))
    }

    private func setupNotifications() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(_ title: String, _ body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    private func holdDisplayAwake() {
        guard assertion == 0 else { return }
        let r = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep as CFString,
                                            IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                            "RestReminder break" as CFString,
                                            &assertion)
        sleeping = (r == kIOReturnSuccess)
    }

    private func releaseSleepAssertion() {
        if assertion != 0 {
            IOPMAssertionRelease(assertion)
            assertion = 0
        }
        sleeping = false
    }

    // MARK: 菜单

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let state: String
        if pausedRemaining != nil {
            state = L.menuPaused
        } else if phase == .working {
            state = L.menuNextBreak(workString(currentRemaining()))
        } else {
            state = L.menuBreaking(clockString(currentRemaining()))
        }
        let head = NSMenuItem(title: state, action: nil, keyEquivalent: "")
        head.isEnabled = false
        menu.addItem(head)
        menu.addItem(.separator())

        menu.addItem(item(phase == .breaking ? L.menuEndBreak : L.menuBreakNow, #selector(menuBreakNow)))
        menu.addItem(item(pausedRemaining == nil ? L.menuPause : L.menuResume, #selector(menuTogglePause)))
        menu.addItem(item(L.menuReset, #selector(menuReset)))
        menu.addItem(.separator())

        let workSub = NSMenu()
        for m in [15, 25, 30, 45, 50, 60, 90, 120] {
            let i = item(L.intervalLabel(m), #selector(menuSetWork(_:)))
            i.tag = m
            i.state = (Int(Settings.workSeconds / 60) == m) ? .on : .off
            workSub.addItem(i)
        }
        let workItem = NSMenuItem(title: L.menuWorkInterval, action: nil, keyEquivalent: "")
        workItem.submenu = workSub
        menu.addItem(workItem)

        let restSub = NSMenu()
        for m in [3, 5, 10, 15] {
            let i = item(L.intervalLabel(m), #selector(menuSetRest(_:)))
            i.tag = m
            i.state = (Int(Settings.breakSeconds / 60) == m) ? .on : .off
            restSub.addItem(i)
        }
        let restItem = NSMenuItem(title: L.menuBreakLength, action: nil, keyEquivalent: "")
        restItem.submenu = restSub
        menu.addItem(restItem)

        menu.addItem(.separator())

        let allScreens = item(L.menuAllScreens, #selector(menuToggleAllScreens))
        allScreens.state = Settings.coverAllScreens ? .on : .off
        menu.addItem(allScreens)

        let sound = item(L.menuSound, #selector(menuToggleSound))
        sound.state = Settings.sound ? .on : .off
        menu.addItem(sound)

        let voice = item(L.menuVoice, #selector(menuToggleVoice))
        voice.state = Settings.voice ? .on : .off
        menu.addItem(voice)

        let auto = item(L.menuAutoStart, #selector(menuToggleAutoStart))
        auto.state = Settings.autoStart ? .on : .off
        menu.addItem(auto)

        menu.addItem(.separator())
        menu.addItem(item(L.menuQuit, #selector(menuQuit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector?, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc private func menuBreakNow() {
        if phase == .breaking { finishBreak(manual: true) } else { beginBreak() }
    }

    @objc private func menuTogglePause() {
        if let p = pausedRemaining {
            deadline = Date().addingTimeInterval(p)
            pausedRemaining = nil
        } else {
            pausedRemaining = max(0, deadline.timeIntervalSinceNow)
        }
        updateStatusTitle()
    }

    @objc private func menuReset() {
        if phase == .breaking { finishBreak(manual: true) } else { startWork() }
    }

    @objc private func menuSetWork(_ sender: NSMenuItem) {
        UserDefaults.standard.set(Double(sender.tag), forKey: K.work)
        if phase == .working { startWork() } else { workSeconds = Settings.workSeconds }
    }

    @objc private func menuSetRest(_ sender: NSMenuItem) {
        UserDefaults.standard.set(Double(sender.tag), forKey: K.rest)
        if phase == .breaking {
            breakSeconds = Settings.breakSeconds
            deadline = Date().addingTimeInterval(breakSeconds)
        }
    }

    @objc private func menuToggleAllScreens() {
        let v = !Settings.coverAllScreens
        UserDefaults.standard.set(v, forKey: K.allScreens)
        if phase == .breaking { showCovers() }
    }

    @objc private func menuToggleSound() {
        UserDefaults.standard.set(!Settings.sound, forKey: K.sound)
    }

    @objc private func menuToggleVoice() {
        UserDefaults.standard.set(!Settings.voice, forKey: K.voice)
    }

    @objc private func menuToggleAutoStart() {
        let enable = !Settings.autoStart
        let ok = AutoStart.set(enabled: enable)
        UserDefaults.standard.set(enable && ok, forKey: K.autoStart)
        if !ok { log("autostart failed") }
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }

    // MARK: 截图（文档用，不需要屏幕录制权限：直接把视图渲染成 PNG）

    private func runSnapshot(_ path: String, mini: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.beginBreak()
            if mini { self.minimizeBreak() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if mini, let view = self.mini?.contentView {
                    self.saveImage(view, to: path)
                } else if let view = (self.covers.first(where: { $0.isPrimaryScreen }) ?? self.covers.first)?.contentView {
                    self.saveImage(view, to: path)
                } else {
                    print("SNAPSHOT failed: no view")
                }
                exit(0)
            }
        }
    }

    private func saveImage(_ view: NSView, to path: String) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            print("SNAPSHOT failed: no bitmap"); return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            print("SNAPSHOT failed: no png data"); return
        }
        try? data.write(to: URL(fileURLWithPath: path))
        print("SNAPSHOT \(path) \(rep.pixelsWide)x\(rep.pixelsHigh)")
    }

    // MARK: 自检

    private func runSelfTest() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.beginBreak()
            let primary = self.covers.first(where: { $0.isPrimaryScreen })
            print("SELFTEST screens=\(NSScreen.screens.count) covers=\(self.covers.count) phase=\(self.phase) status=\(self.statusItem?.button?.title ?? "-") primaryVisible=\(primary?.isVisible ?? false) ring=\(primary?.ringText ?? "-")")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                self.minimizeBreak()
                let visible = self.covers.filter { $0.isVisible }.count
                print("SELFTEST after-minimize visibleCovers=\(visible) mini=\(self.mini?.isVisible ?? false) miniText=\(self.mini?.debugText ?? "-")")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    self.restoreBreak()
                    print("SELFTEST after-restore visibleCovers=\(self.covers.filter { $0.isVisible }.count)")
                    self.finishBreak(manual: true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        print("SELFTEST after-finish phase=\(self.phase) status=\(self.statusItem?.button?.title ?? "-") covers=\(self.covers.count)")
                        print("SELFTEST OK")
                        exit(0)
                    }
                }
            }
        }
    }
}

// MARK: - 开机自启（LaunchAgent）

enum AutoStart {
    static var plistPath: String { NSHomeDirectory() + "/Library/LaunchAgents/com.huage.restreminder.plist" }
    static var label: String { Bundle.main.bundleIdentifier ?? "com.restreminder.app" }

    static func set(enabled: Bool) -> Bool {
        guard let exec = Bundle.main.executablePath, Bundle.main.bundleIdentifier != nil else { return false }
        let fm = FileManager.default
        let dir = NSHomeDirectory() + "/Library/LaunchAgents"
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        unload()

        if !enabled {
            try? fm.removeItem(atPath: plistPath)
            return true
        }

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>\(label)</string>
            <key>ProgramArguments</key>
            <array><string>\(exec)</string></array>
            <key>RunAtLoad</key><true/>
            <key>KeepAlive</key><false/>
        </dict>
        </plist>
        """
        do {
            try plist.write(toFile: plistPath, atomically: true, encoding: .utf8)
        } catch {
            return false
        }
        return load()
    }

    private static func load() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["bootstrap", "gui/\(getuid())", plistPath]
        p.standardError = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        if p.terminationStatus == 0 { return true }
        let legacy = Process()
        legacy.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        legacy.arguments = ["load", "-w", plistPath]
        legacy.standardError = FileHandle.nullDevice
        legacy.standardOutput = FileHandle.nullDevice
        try? legacy.run()
        legacy.waitUntilExit()
        return legacy.terminationStatus == 0
    }

    private static func unload() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["bootout", "gui/\(getuid())/\(label)"]
        p.standardError = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }
}

// MARK: - 启动

let lockFD = open(NSTemporaryDirectory() + "rest-reminder.lock", O_CREAT | O_RDWR, 0o644)
if lockFD >= 0 { flock(lockFD, LOCK_EX | LOCK_NB) }

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
