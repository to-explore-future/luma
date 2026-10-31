import AppKit

/// 一块屏在图里的"瓦片"：外框 + 名字 + 百分比 + 亮度条。
final class DisplayTile: NSView {
    let display: DisplayInfo
    private var nameLabel: NSTextField!
    private var pctLabel: NSTextField!
    var slider: LumaSlider!
    var onChanged: ((Float) -> Void)?

    init(display: DisplayInfo, active: Bool, frame: NSRect, compact: Bool) {
        self.display = display
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = active ? 1.5 : 1
        layer?.borderColor = (active
            ? NSColor.controlAccentColor
            : NSColor.labelColor.withAlphaComponent(0.16)).cgColor
        layer?.backgroundColor = (active
            ? NSColor.controlAccentColor.withAlphaComponent(0.10)
            : NSColor.controlBackgroundColor.withAlphaComponent(0.55)).cgColor

        let pad: CGFloat = 9
        let nameY = frame.height - (compact ? 20 : 24)

        nameLabel = NSTextField(labelWithString: display.name)
        nameLabel.font = active ? .boldSystemFont(ofSize: compact ? 10 : 11) : .systemFont(ofSize: compact ? 10 : 11)
        nameLabel.textColor = active ? .controlAccentColor : .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.frame = NSRect(x: pad, y: nameY, width: max(20, frame.width - pad * 2 - 46), height: 14)
        addSubview(nameLabel)

        pctLabel = NSTextField(labelWithString: "\(Int((display.level * 100).rounded()))%")
        pctLabel.font = .monospacedDigitSystemFont(ofSize: compact ? 10 : 11, weight: .regular)
        pctLabel.alignment = .right
        pctLabel.frame = NSRect(x: frame.width - pad - 44, y: nameY, width: 44, height: 14)
        addSubview(pctLabel)

        slider = LumaSlider(frame: NSRect(x: pad, y: compact ? 4 : 6,
                                          width: max(30, frame.width - pad * 2), height: compact ? 18 : 20))
        slider.compact = compact
        slider.value = display.level
        slider.onChanged = { [weak self] value in
            guard let self = self else { return }
            self.pctLabel.stringValue = "\(Int((value * 100).rounded()))%"
            self.onChanged?(value)
        }
        addSubview(slider)
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// 按真实排列把每块屏画成瓦片，瓦片里各自带亮度条。
final class ScreenMapView: NSView {
    private(set) var usedMap = true

    var onLevel: ((DisplayInfo, Float) -> Void)?

    init(displays: [DisplayInfo], activeID: CGDirectDisplayID,
         width: CGFloat, height: CGFloat, compact: Bool) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        wantsLayer = true
        guard !displays.isEmpty else { usedMap = false; return }

        // 真实 frame（Cocoa 全局坐标）：用 NSScreen 的坐标，不是 CG 的
        var frames: [(DisplayInfo, NSRect)] = []
        for screen in NSScreen.screens {
            guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            if let display = displays.first(where: { $0.id == num.uint32Value }) {
                frames.append((display, screen.frame))
            }
        }
        // 有屏没匹配上（极少见）：退回简单横排
        if frames.count != displays.count {
            frames = simpleRow(displays)
        }

        var union = frames[0].1
        for (_, f) in frames.dropFirst() { union = union.union(f) }
        guard union.width > 0, union.height > 0 else { usedMap = false; return }

        // 瓦片和弹框边缘之间留白，别贴着边框
        let pad: CGFloat = 14
        let scale = min((width - 2 * pad) / union.width, (height - 2 * pad) / union.height)
        let drawnW = union.width * scale
        let drawnH = union.height * scale
        let ox = pad + (width - 2 * pad - drawnW) / 2 - union.minX * scale
        let oy = pad + (height - 2 * pad - drawnH) / 2 - union.minY * scale

        for (display, frame) in frames {
            var r = NSRect(x: frame.minX * scale + ox,
                           y: frame.minY * scale + oy,
                           width: frame.width * scale,
                           height: frame.height * scale)
            // 相邻屏在系统坐标里是无缝相接的，缩一点让边界看得见
            r = r.insetBy(dx: 2, dy: 2)
            guard r.width >= 90, r.height >= 56 else { usedMap = false; return }
            let tile = DisplayTile(display: display, active: display.id == activeID,
                                   frame: r, compact: compact)
            tile.onChanged = { [weak self] value in self?.onLevel?(display, value) }
            addSubview(tile)
        }
    }

    private func simpleRow(_ displays: [DisplayInfo]) -> [(DisplayInfo, NSRect)] {
        displays.enumerated().map { index, d in
            (d, NSRect(x: CGFloat(index) * 200, y: 0, width: 200, height: 120))
        }
    }

    required init?(coder: NSCoder) { fatalError() }
}
