import AppKit
import CoreGraphics

/// gamma（软件调光）的屏幕有个坑：gamma 表已经写进系统、读回也是新值，
/// 但如果那块屏画面完全静止，WindowServer 不会把新表推上去——要等别的窗口重绘才变。
/// 这里在那块屏右上角放一个 2×2 的黑色小窗口，每次抖 1 像素，逼它合成一帧。
final class Nudge {
    static let shared = Nudge()
    private var windows: [CGDirectDisplayID: NSWindow] = [:]
    private var tick = 0

    func kick(_ id: CGDirectDisplayID) {
        guard let screen = Displays.screensByID()[id] else { return }
        let frame = screen.frame
        let window: NSWindow
        if let existing = windows[id] {
            window = existing
        } else {
            window = NSWindow(contentRect: NSRect(x: frame.maxX - 4, y: frame.maxY - 4, width: 2, height: 2),
                              styleMask: [.borderless], backing: .buffered, defer: false)
            window.isOpaque = true
            window.backgroundColor = .black
            window.ignoresMouseEvents = true
            window.level = NSWindow.Level(rawValue: 3)
            window.hasShadow = false
            window.alphaValue = 0.02
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]
            windows[id] = window
        }
        let jitter: CGFloat = tick % 2 == 0 ? 4 : 5
        tick += 1
        window.setFrameOrigin(NSPoint(x: frame.maxX - jitter, y: frame.maxY - jitter))
        window.orderFront(nil)
        window.display()
    }
}
