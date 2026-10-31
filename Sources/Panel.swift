import AppKit

/// 自绘滑块：macOS 26 上系统 NSSlider 的滑块会被控件边界裁掉，只能自己画。
final class LumaSlider: NSView {
    var value: Float = 1
    var onChanged: ((Float) -> Void)?
    var compact = false
    private let minValue: Float = 0.05

    private var knob: CGFloat { compact ? 13 : 18 }
    private var trackHeight: CGFloat { compact ? 4 : 6 }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let trackH: CGFloat = trackHeight
        let trackRect = NSRect(x: knob / 2, y: (bounds.height - trackH) / 2,
                               width: bounds.width - knob, height: trackH)
        NSColor.labelColor.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: trackH / 2, yRadius: trackH / 2).fill()

        let pct = CGFloat((value - minValue) / (1 - minValue))
        let fillW = max(0, min(1, pct)) * trackRect.width
        let fillRect = NSRect(x: trackRect.minX, y: trackRect.minY, width: fillW, height: trackH)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: trackH / 2, yRadius: trackH / 2).fill()

        let kx = trackRect.minX + fillW - knob / 2
        let knobRect = NSRect(x: kx, y: (bounds.height - knob) / 2, width: knob, height: knob)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.set()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: knobRect).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.labelColor.withAlphaComponent(0.12).setStroke()
        let border = NSBezierPath(ovalIn: knobRect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
    }

    override func mouseDown(with event: NSEvent) { update(with: event) }
    override func mouseDragged(with event: NSEvent) { update(with: event) }

    private func update(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let usable = bounds.width - knob
        guard usable > 0 else { return }
        let pct = min(1, max(0, (point.x - knob / 2) / usable))
        value = minValue + Float(pct) * (1 - minValue)
        needsDisplay = true
        onChanged?(value)
    }
}

/// 一块屏一行：名字、百分比、滑块。
final class DisplayRow: NSView {
    let display: DisplayInfo
    private var nameLabel: NSTextField!
    private var pctLabel: NSTextField!
    var slider: LumaSlider!

    var onChanged: ((Float) -> Void)?

    static let height: CGFloat = 66

    init(display: DisplayInfo, active: Bool, width: CGFloat) {
        self.display = display
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: DisplayRow.height))
        wantsLayer = true

        if active {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
            layer?.cornerRadius = 9
        }

        nameLabel = NSTextField(labelWithString: display.name)
        nameLabel.font = active ? .boldSystemFont(ofSize: 13) : .systemFont(ofSize: 13)
        nameLabel.textColor = active ? .controlAccentColor : .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.frame = NSRect(x: 14, y: 38, width: width - 120, height: 17)
        addSubview(nameLabel)

        if active {
            let tag = NSTextField(labelWithString: L10n.t("current"))
            tag.font = .boldSystemFont(ofSize: 11)
            tag.textColor = .controlAccentColor
            let nameWidth = min(nameLabel.intrinsicContentSize.width, width - 120)
            tag.frame = NSRect(x: 14 + nameWidth + 8, y: 39, width: 90, height: 16)
            addSubview(tag)
        }

        pctLabel = NSTextField(labelWithString: "\(Int((display.level * 100).rounded()))%")
        pctLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        pctLabel.alignment = .right
        pctLabel.frame = NSRect(x: width - 66, y: 38, width: 52, height: 17)
        addSubview(pctLabel)

        slider = LumaSlider(frame: NSRect(x: 14, y: 4, width: width - 28, height: 30))
        slider.value = display.level
        slider.onChanged = { [weak self] value in
            guard let self = self else { return }
            self.pctLabel.stringValue = "\(Int((value * 100).rounded()))%"
            self.onChanged?(value)
        }
        addSubview(slider)

        if active {
            let bar = NSView(frame: NSRect(x: 0, y: 8, width: 3, height: DisplayRow.height - 16))
            bar.wantsLayer = true
            bar.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            bar.layer?.cornerRadius = 1.5
            addSubview(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// 整个面板：屏幕地图（每块屏一个瓦片，瓦片里带亮度条）+ 固定底栏。
/// 屏幕多到瓦片放不下时，退回可滚动的竖排列表。
final class PanelView: NSView {
    static let width: CGFloat = 460
    static let margin: CGFloat = 20
    static let gap: CGFloat = 8
    static let footerHeight: CGFloat = 76

    var onLevel: ((DisplayInfo, Float) -> Void)?
    var onToggleBackend: (() -> Void)?
    var onToggleLogin: (() -> Void)?
    var onDonate: (() -> Void)?
    var onQuit: (() -> Void)?
    var onLanguage: ((NSButton) -> Void)?

    private(set) var height: CGFloat = 0
    private(set) var scrolls: Bool = false
    private(set) var usesMap: Bool = false

    /// 按当前屏幕排列算出地图需要多高（保持真实宽高比）
    static func fittedMapHeight(forWidth width: CGFloat) -> CGFloat {
        var union = NSRect.zero
        var first = true
        for screen in NSScreen.screens {
            union = first ? screen.frame : union.union(screen.frame)
            first = false
        }
        guard union.width > 0, union.height > 0 else { return 200 }
        return min(280, width * union.height / union.width)
    }

    init(displays: [DisplayInfo], activeID: CGDirectDisplayID, forceGamma: Bool,
         loginOn: Bool, hint: String, maxHeight: CGFloat) {
        let mapWidth = PanelView.width - 2 * PanelView.margin
        var mapHeight = min(PanelView.fittedMapHeight(forWidth: mapWidth), maxHeight - PanelView.footerHeight - 20)

        var map: ScreenMapView?
        if displays.count >= 1 && mapHeight >= 90 {
            let candidate = ScreenMapView(displays: displays, activeID: activeID,
                                          width: mapWidth, height: mapHeight, compact: displays.count > 3)
            if candidate.usedMap {
                map = candidate
                mapHeight = candidate.frame.height
            }
        }

        let listHeight = 14 + CGFloat(displays.count) * DisplayRow.height + PanelView.footerHeight
        let wanted = map != nil ? (PanelView.footerHeight + mapHeight + 14) : listHeight
        height = min(wanted, max(maxHeight, PanelView.footerHeight + 120))

        super.init(frame: NSRect(x: 0, y: 0, width: PanelView.width, height: height))
        wantsLayer = true
        usesMap = map != nil

        if let map = map {
            map.frame.origin = NSPoint(x: PanelView.margin, y: PanelView.footerHeight + 14)
            map.onLevel = { [weak self] display, value in self?.onLevel?(display, value) }
            addSubview(map)
        } else {
            // 列表兜底（可滚动）
            let topInset: CGFloat = 14
            let rowsH = CGFloat(displays.count) * DisplayRow.height
            let documentHeight = topInset + rowsH + 6
            scrolls = listHeight > height + 0.5
            let scrollH = height - PanelView.footerHeight
            let scroll = NSScrollView(frame: NSRect(x: 0, y: PanelView.footerHeight,
                                                    width: PanelView.width, height: scrollH))
            scroll.drawsBackground = false
            scroll.hasVerticalScroller = scrolls
            scroll.autohidesScrollers = true
            scroll.scrollerStyle = .overlay
            let document = NSView(frame: NSRect(x: 0, y: 0, width: PanelView.width, height: documentHeight))
            var y = documentHeight - topInset - DisplayRow.height
            for d in displays {
                let row = DisplayRow(display: d, active: d.id == activeID,
                                     width: PanelView.width - 2 * PanelView.margin)
                row.frame.origin = NSPoint(x: PanelView.margin, y: y)
                row.onChanged = { [weak self] value in self?.onLevel?(d, value) }
                document.addSubview(row)
                y -= DisplayRow.height
            }
            scroll.documentView = document
            addSubview(scroll)
        }

        // ---- 底栏（always）----
        let hintLabel = NSTextField(labelWithString: hint)
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.lineBreakMode = .byTruncatingTail
        hintLabel.frame = NSRect(x: PanelView.margin, y: 14 + 26 + 10,
                                 width: PanelView.width - 2 * PanelView.margin, height: 18)
        addSubview(hintLabel)

        let buttonY: CGFloat = 14
        let font = NSFont.systemFont(ofSize: 12)

        func width(for title: String) -> CGFloat {
            let w = (title as NSString).size(withAttributes: [.font: font]).width
            return max(58, ceil(w) + 22)
        }

        let items: [(String, Selector)] = [
            (forceGamma ? L10n.t("backendSoftware") : L10n.t("backendAuto"), #selector(backendTapped)),
            (loginOn ? L10n.t("loginOn") : L10n.t("loginOff"), #selector(loginTapped)),
            (L10n.t("donate"), #selector(donateTapped)),
        ]

        var x = PanelView.margin
        for (title, sel) in items {
            let w = width(for: title)
            let button = NSButton(title: title, target: self, action: sel)
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.font = font
            button.frame = NSRect(x: x, y: buttonY, width: w, height: 26)
            addSubview(button)
            x += w + PanelView.gap
        }

        let quitX = PanelView.width - PanelView.margin - 64
        let quit = NSButton(title: L10n.t("quit"), target: self, action: #selector(quitTapped))
        quit.bezelStyle = .rounded
        quit.controlSize = .small
        quit.font = font
        quit.frame = NSRect(x: quitX, y: buttonY, width: 64, height: 26)
        addSubview(quit)

        // 语言：小地球按钮，点开是 12 种语言
        let globe = NSButton(title: "", target: self, action: #selector(languageTapped(_:)))
        globe.bezelStyle = .rounded
        globe.controlSize = .small
        if let image = NSImage(systemSymbolName: "globe", accessibilityDescription: L10n.t("language")) {
            globe.image = image
            globe.imagePosition = .imageOnly
        } else {
            globe.title = "🌐"
        }
        globe.toolTip = L10n.t("language")
        globe.frame = NSRect(x: quitX - 8 - 34, y: buttonY, width: 34, height: 26)
        addSubview(globe)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func backendTapped() { onToggleBackend?() }
    @objc private func loginTapped() { onToggleLogin?() }
    @objc private func donateTapped() { onDonate?() }
    @objc private func quitTapped() { onQuit?() }
    @objc private func languageTapped(_ sender: NSButton) { onLanguage?(sender) }
}
