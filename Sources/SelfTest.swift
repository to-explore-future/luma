import AppKit
import CoreGraphics

/// 无界面自测：枚举、读、写、读回、恢复。
enum SelfTest {
    static func run() -> Int32 {
        var failures = 0
        let originalLanguage = L10n.code
        func check(_ ok: Bool, _ name: String, _ detail: String = "") {
            print("\(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : "  — \(detail)")")
            if !ok { failures += 1 }
        }

        let displays = Displays.enumerate(override: nil)
        check(!displays.isEmpty, "枚举显示器", "\(displays.count) 块")

        for d in displays {
            print("  · \(d.name)  id=\(d.id)  backend=\(d.backend.label)  key=\(d.key)  当前=\(Int(d.level * 100))%")

            let original = d.level
            let target: Float = 0.62
            let wrote = Brightness.write(d.id, backend: d.backend, target)
            usleep(180_000)
            let readback = Brightness.read(d.id, backend: d.backend)
            let ok = wrote && (readback.map { abs($0 - target) < 0.15 } ?? false)
            check(ok, "\(d.name) 写入并读回", "写入=\(wrote) 读回=\(readback.map { Int($0 * 100) } ?? -1)%")

            // 恢复
            Brightness.write(d.id, backend: d.backend, original)
            usleep(120_000)
            let restored = Brightness.read(d.id, backend: d.backend) ?? -1
            check(abs(restored - original) < 0.12, "\(d.name) 恢复", "原=\(Int(original * 100))% 现=\(Int(restored * 100))%")
        }

        // 下限
        if let d = displays.first {
            Brightness.write(d.id, backend: d.backend, 0.01)
            usleep(150_000)
            let low = Brightness.read(d.id, backend: d.backend) ?? -1
            check(low > 0.0, "下限不会全黑", "写 1% 读回 \(Int(low * 100))%")
            Brightness.write(d.id, backend: d.backend, d.level)
        }

        // 唤醒恢复：把亮度改掉，触发恢复，看是否回到记录值
        if let d = displays.first {
            let original = d.level
            Store.shared.setLevel(original, for: d.key)
            Brightness.write(d.id, backend: d.backend, 0.30)
            usleep(200_000)
            let tampered = Brightness.read(d.id, backend: d.backend) ?? -1
            RestoreController.shared.restore(reason: "自测")
            usleep(200_000)
            let restored = Brightness.read(d.id, backend: d.backend) ?? -1
            check(abs(restored - original) < 0.1, "唤醒恢复",
                  "改成 \(Int(tampered * 100))% 后恢复到 \(Int(restored * 100))%（原 \(Int(original * 100))%）")
        }

        // 滑块映射：点在中点应得到约 50%
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 120),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let slider = LumaSlider(frame: NSRect(x: 0, y: 0, width: 332, height: 30))
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 120))
        window.contentView?.addSubview(slider)
        if let event = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 166, y: 15),
                                          modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                          context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
            slider.mouseDown(with: event)
            let expected: Float = 0.5
            check(abs(slider.value - expected) < 0.06, "滑块中点映射",
                  "得到 \(Int(slider.value * 100))%（期望约 50%）")
            if let left = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 2, y: 15),
                                             modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                             context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                slider.mouseDown(with: left)
                check(slider.value >= 0.049 && slider.value <= 0.08, "滑块最左=下限 5%",
                      "得到 \(Int(slider.value * 100))%")
            }
        }

        // 12 种语言的面板都能正常构建
        var built = 0
        for lang in L10n.languages {
            L10n.code = lang.code
            let sample = Displays.enumerate(override: nil)
            let view = PanelView(displays: sample, activeID: sample.first?.id ?? 0,
                                 forceGamma: false, loginOn: false, hint: L10n.t("hint"),
                                 maxHeight: 640)
            if view.height > 100 { built += 1 }
        }
        check(built == L10n.languages.count, "12 种语言面板构建", "\(built)/\(L10n.languages.count)")

        // 多屏布局：面板不能超出屏幕，超出时必须可滚动
        for n in [1, 2, 3, 5, 8, 12] {
            var fake: [DisplayInfo] = []
            for i in 0..<n {
                let info = DisplayInfo(
                    id: CGDirectDisplayID(i + 1),
                    name: "显示器 \(i + 1)",
                    builtin: i == 0,
                    vendor: 0x1234,
                    model: UInt32(i),
                    serial: UInt32(i),
                    key: "k\(i)",
                    maker: "ABC",
                    backend: Backend.gamma,
                    level: 1.0,
                    asleep: false,
                    main: i == 0)
                fake.append(info)
            }
            let maxH: CGFloat = 640
            let view = PanelView(displays: fake, activeID: 1, forceGamma: false,
                                 loginOn: false, hint: L10n.t("hint"), maxHeight: maxH)
            let fits = view.height <= maxH + 0.5
            let needed = Double(n) * Double(DisplayRow.height) + 14.0 + Double(PanelView.footerHeight)
            let needsScroll = needed > Double(maxH)
            let scrollOK = view.usesMap ? !view.scrolls : (view.scrolls == needsScroll)
            check(fits && scrollOK,
                  "\(n) 块屏布局",
                  "面板高 \(Int(view.height))pt 地图=\(view.usesMap) 可滚动=\(view.scrolls)")
        }

        L10n.code = originalLanguage
        print(failures == 0 ? "SELFTEST PASS" : "SELFTEST FAIL (\(failures))")
        return failures == 0 ? 0 : 1
    }
}
