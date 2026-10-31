import AppKit
import CoreGraphics

final class PanelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panelOpenedAt: TimeInterval = 0
    private var popover: NSPopover?
    private var panelWindow: PanelWindow?
    private var displays: [DisplayInfo] = []
    private var activeID: CGDirectDisplayID = CGMainDisplayID()
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private var donateWindow: NSWindow?

    private let launchAgentLabel = "com.tcxt.luma.swift"

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        RestoreController.shared.onDisplaysChanged = { [weak self] in
            self?.refreshDisplays(rebuildIfOpen: true)
        }
        RestoreController.shared.start()
        refreshDisplays(rebuildIfOpen: false)
        Log.write("启动：\(displays.count) 块屏，语言=\(L10n.code)")
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--test-lang=") }) {
            L10n.code = String(arg.split(separator: "=").last ?? "zh-Hans")
        }
        if CommandLine.arguments.contains("--test-donate") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.showDonate() }
        }
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--test-login=") }) {
            let want = arg.hasSuffix("on")
            if want != loginEnabled() { toggleLogin() }
            Log.write("测试自启：\(want) 结果=\(loginEnabled())")
        }
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--test-panel") }) {
            let index = Int(arg.split(separator: "=").last ?? "0") ?? 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self = self, NSScreen.screens.indices.contains(index) else { return }
                let screen = NSScreen.screens[index]
                self.showPanel(on: screen, anchorX: screen.frame.midX)
            }
        }
    }

    // MARK: - 显示器

    private func refreshDisplays(rebuildIfOpen: Bool) {
        displays = Displays.enumerate(override: Store.shared.forceGamma ? .gamma : nil)
        if rebuildIfOpen, let window = panelWindow, window.isVisible {
            rebuildPanelContent()
        }
    }

    private var hintText: String {
        let gamma = displays.filter { $0.backend == .gamma }.map { $0.name }
        if gamma.isEmpty { return L10n.t("hint") }
        return L10n.t("hintGamma") + gamma.joined(separator: "、")
    }

    // MARK: - 菜单栏

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "Luma") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "☀"
            }
            button.toolTip = "Luma"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    // MARK: - 面板

    @objc private func statusItemClicked(_ sender: Any?) {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            showContextMenu()
            return
        }
        togglePanel(sender)
    }

    private func showContextMenu() {
        closePanel()
        let menu = NSMenu()
        let langItem = NSMenuItem(title: L10n.t("language"), action: nil, keyEquivalent: "")
        let langMenu = NSMenu()
        for lang in L10n.languages {
            let item = NSMenuItem(title: lang.name, action: #selector(changeLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = lang.code
            item.state = lang.code == L10n.code ? .on : .off
            langMenu.addItem(item)
        }
        langItem.submenu = langMenu
        menu.addItem(langItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: L10n.t("quit"), action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        // 用临时菜单不占用状态栏 item 的常驻菜单
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func changeLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        L10n.code = code
        Log.write("语言切换：\(code)")
        if let popover = popover, popover.isShown {
            // 菜单关掉后再重建，否则新面板会被菜单的关闭动作带走
            DispatchQueue.main.async { [weak self] in self?.rebuildPanelContent() }
        }
    }

    @objc private func quitApp() { NSApp.terminate(nil) }

    @objc private func togglePanel(_ sender: Any?) {
        if let popover = popover, popover.isShown {
            popover.performClose(sender)
            return
        }
        showPanel()
    }

    /// 全局鼠标位置（Cocoa 坐标）。用 CGEvent 而不是 NSEvent.mouseLocation：
    /// 后者在鼠标被程序移动（warp）后可能是旧值。
    private func mousePoint() -> NSPoint {
        guard let event = CGEvent(source: nil) else { return NSEvent.mouseLocation }
        let cg = event.location
        let mainScreen = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
        let mainHeight = mainScreen?.frame.maxY ?? 0
        return NSPoint(x: cg.x, y: mainHeight - cg.y)
    }

    private func showPanel() {
        let mouse = mousePoint()
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        showPanel(on: screen, anchorX: mouse.x)
    }

    private func showPanel(on screen: NSScreen, anchorX: CGFloat) {
        activeID = displayID(of: screen) ?? CGMainDisplayID()
        refreshDisplays(rebuildIfOpen: false)

        let maxHeight = screen.visibleFrame.height - 40
        let view = buildPanelView(maxHeight: maxHeight)
        let width = PanelView.width
        let height = view.height

        let popover = self.popover ?? NSPopover()
        // 用 applicationDefined：auto-close 在 accessory app 上不可靠，
        // 关闭交给下面的全局点击监听
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.contentSize = NSSize(width: width, height: height)
        if popover.contentViewController == nil {
            popover.contentViewController = NSViewController()
        }
        popover.contentViewController?.view = view

        guard let button = statusItem.button else { return }
        // transient popover 需要 app 处于 active，否则刚弹出就被关掉
        NSApp.activate(ignoringOtherApps: true)
        panelOpenedAt = ProcessInfo.processInfo.systemUptime
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        self.popover = popover
        installOutsideClickMonitor()

        // 系统把 popover 放在按钮所在的那块屏；这里再挪到点击的那块屏，
        // 并让顶边贴住菜单栏下沿。
        let target = NSPoint(x: anchorX, y: screen.frame.maxY)
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let window = self.popover?.contentViewController?.view.window else { return }
            var frame = window.frame
            var x = target.x - frame.width / 2
            x = max(screen.frame.minX + 6, min(x, screen.frame.maxX - frame.width - 6))
            // 窗口高度里含顶部箭头（约 26pt）：要让可见面板贴在菜单栏下沿，
            // 得把窗口顶放在「菜单栏下沿」，而不是屏幕顶。
            let menuBarH = screen.frame.maxY - screen.visibleFrame.maxY
            let y = screen.frame.maxY - menuBarH - frame.height
            window.setFrameOrigin(NSPoint(x: x, y: y))
            Log.write("弹出面板：屏幕=\(screen.localizedName) 位置=(\(Int(x)),\(Int(y))) 尺寸=\(Int(frame.width))x\(Int(frame.height))")
        }
    }

    private var outsideMonitor: Any?

    private func installOutsideClickMonitor() {
        guard outsideMonitor == nil else { return }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let popover = self.popover, popover.isShown else { return }
            // 刚弹出的那一下别关
            if ProcessInfo.processInfo.systemUptime - self.panelOpenedAt < 0.3 { return }
            let point = NSEvent.mouseLocation
            if let window = popover.contentViewController?.view.window, window.frame.contains(point) {
                return
            }
            // 点状态栏图标自己会 toggle，不在这里关
            if let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) {
                let menuTop = screen.frame.maxY - (screen.frame.maxY - screen.visibleFrame.maxY)
                if point.y >= menuTop - 2 { return }
            }
            popover.performClose(nil)
        }
    }

    private func removeOutsideClickMonitor() {
        if let monitor = outsideMonitor {
            NSEvent.removeMonitor(monitor)
            outsideMonitor = nil
        }
    }

    private func makePanelWindow() -> PanelWindow {
        let window = PanelWindow(contentRect: NSRect(x: 0, y: 0, width: PanelView.width, height: 200),
                                 styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .popUpMenu
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return window
    }

    private func wrap(_ view: PanelView) -> NSView {
        // 外层负责圆角裁切，内层是原生毛玻璃。
        // 注意：不能给 NSVisualEffectView 自己加 cornerRadius/masksToBounds，
        // 那样会把 blur 干掉，只剩一块灰底。
        let container = NSView(frame: NSRect(x: 0, y: 0, width: view.frame.width, height: view.frame.height))
        container.wantsLayer = true
        container.layer?.cornerRadius = 14
        container.layer?.masksToBounds = true

        let blur = NSVisualEffectView(frame: container.bounds)
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]
        container.addSubview(blur)

        view.frame.origin = .zero
        container.addSubview(view)
        return container
    }

    private func rebuildPanelContent() {
        guard let popover = popover, popover.isShown else { return }
        let screen = popover.contentViewController?.view.window?.screen ?? NSScreen.main
        let view = buildPanelView(maxHeight: (screen?.visibleFrame.height ?? 700) - 40)
        popover.contentSize = NSSize(width: PanelView.width, height: view.height)
        popover.contentViewController?.view = view
    }

    private func buildPanelView(maxHeight: CGFloat = 700) -> PanelView {
        let view = PanelView(displays: displays, activeID: activeID,
                             forceGamma: Store.shared.forceGamma,
                             loginOn: loginEnabled(),
                             hint: hintText,
                             maxHeight: maxHeight)
        view.onLevel = { [weak self] display, value in
            Brightness.write(display.id, backend: display.backend, value)
            if display.backend == .gamma { Nudge.shared.kick(display.id) }
            Store.shared.setLevel(value, for: display.key)
            Log.write("亮度 \(display.name) → \(Int((value * 100).rounded()))%")
            self?.updatePercentIfNeeded()
        }
        view.onToggleBackend = { [weak self] in
            Store.shared.forceGamma.toggle()
            self?.refreshDisplays(rebuildIfOpen: true)
            Log.write("后端切换：\(Store.shared.forceGamma ? "软件调光" : "自动")")
        }
        view.onToggleLogin = { [weak self] in
            self?.toggleLogin()
        }
        view.onDonate = { [weak self] in self?.showDonate() }
        view.onLanguage = { [weak self] button in self?.showLanguageMenu(from: button) }
        view.onQuit = { NSApp.terminate(nil) }
        return view
    }

    private func updatePercentIfNeeded() {
        // 百分比由滑块自己刷新，这里只保证状态表最新
    }

    private func closePanel() {
        if let w = panelWindow, w.isVisible {
            let delta = ProcessInfo.processInfo.systemUptime - panelOpenedAt
            Log.write("关闭面板（打开后 \(String(format: "%.2f", delta))s）")
        }
        panelWindow?.orderOut(nil)
        removeClickMonitor()
    }


    private func installClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self else { return }
            // 刚弹出的那一下别把自己关掉
            if ProcessInfo.processInfo.systemUptime - self.panelOpenedAt < 0.4 { return }
            // 点菜单栏（状态栏图标）不算「点外面」，交给按钮自己的 toggle 处理
            let point = NSEvent.mouseLocation
            if let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) {
                let menuTop = screen.frame.maxY - (screen.frame.maxY - screen.visibleFrame.maxY)
                if point.y >= menuTop - 2 { return }
            }
            self.closePanel()
        }
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { self?.closePanel(); return nil }
                return event
            }
        }
    }

    private func removeClickMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

    private func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return num.uint32Value
        }
        return nil
    }

    // MARK: - 开机自启

    private var launchAgentPath: String {
        NSHomeDirectory() + "/Library/LaunchAgents/\(launchAgentLabel).plist"
    }

    private func loginEnabled() -> Bool {
        FileManager.default.fileExists(atPath: launchAgentPath)
    }

    private func toggleLogin() {
        if loginEnabled() {
            removeLaunchAgent()
        } else {
            installLaunchAgent()
        }
        rebuildPanelContent()
    }

    private func installLaunchAgent() {
        let exe = Bundle.main.executablePath ?? "/Applications/Luma.app/Contents/MacOS/Luma"
        let dir = (launchAgentPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "Label": launchAgentLabel,
            "ProgramArguments": [exe],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
        ]
        if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
            try? data.write(to: URL(fileURLWithPath: launchAgentPath))
        }
        let uid = getuid()
        _ = runLaunchctl(["bootout", "gui/\(uid)/\(launchAgentLabel)"])
        _ = runLaunchctl(["bootstrap", "gui/\(uid)", launchAgentPath])
        Log.write("已开启开机自启")
    }

    private func removeLaunchAgent() {
        let uid = getuid()
        _ = runLaunchctl(["bootout", "gui/\(uid)/\(launchAgentLabel)"])
        try? FileManager.default.removeItem(atPath: launchAgentPath)
        Log.write("已关闭开机自启")
    }

    @discardableResult
    private func runLaunchctl(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus
        } catch {
            return -1
        }
    }

    // MARK: - 赞助

    private func showLanguageMenu(from button: NSButton) {
        let menu = NSMenu()
        for lang in L10n.languages {
            let item = NSMenuItem(title: lang.name, action: #selector(changeLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = lang.code
            item.state = lang.code == L10n.code ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: button.bounds.height + 4),
                   in: button)
    }

    private func showDonate() {
        if let window = donateWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let width: CGFloat = 320
        let qr: CGFloat = 220
        let height: CGFloat = qr + 140
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L10n.t("donate")
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.level = .floating

        let view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        let card = NSView(frame: NSRect(x: (width - qr) / 2, y: 108, width: qr, height: qr))
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.white.cgColor
        card.layer?.cornerRadius = 14
        view.addSubview(card)

        if let path = Bundle.main.path(forResource: "DonateQR", ofType: "png"),
           let image = NSImage(contentsOfFile: path) {
            let iv = NSImageView(frame: NSRect(x: 10, y: 10, width: qr - 20, height: qr - 20))
            iv.image = image
            iv.imageScaling = .scaleProportionallyUpOrDown
            card.addSubview(iv)
        }

        let line1 = NSTextField(labelWithString: L10n.t("donateLine1"))
        line1.font = .boldSystemFont(ofSize: 13)
        line1.alignment = .center
        line1.frame = NSRect(x: 16, y: 78, width: width - 32, height: 18)
        view.addSubview(line1)

        let line2 = NSTextField(labelWithString: L10n.t("donateLine2"))
        line2.font = .systemFont(ofSize: 11)
        line2.textColor = .secondaryLabelColor
        line2.alignment = .center
        line2.frame = NSRect(x: 16, y: 54, width: width - 32, height: 18)
        view.addSubview(line2)

        let scan = NSTextField(labelWithString: L10n.t("donateScan"))
        scan.font = .systemFont(ofSize: 10)
        scan.textColor = .tertiaryLabelColor
        scan.alignment = .center
        scan.frame = NSRect(x: 16, y: 36, width: width - 32, height: 14)
        view.addSubview(scan)

        window.contentView = view
        let screen = NSScreen.screens.first { NSMouseInRect(mousePoint(), $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        window.setFrameOrigin(NSPoint(x: screen.frame.midX - width / 2, y: screen.frame.midY - height / 2))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        donateWindow = window
        Log.write("赞助窗口：屏幕=\(screen.localizedName) frame=\(window.frame)")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }


}
