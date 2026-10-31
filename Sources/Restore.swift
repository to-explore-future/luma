import AppKit
import CoreGraphics

/// 负责在睡眠唤醒、显示器插拔/重排之后，把每块屏的亮度恢复回去。
final class RestoreController {
    static let shared = RestoreController()

    private var pending: DispatchWorkItem?
    private var callbackInstalled = false
    private var observer: NSObjectProtocol?
    private var pollTimer: Timer?

    var onDisplaysChanged: (() -> Void)?

    func start() {
        installReconfigCallback()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.schedulePasses("唤醒")
        }
        _ = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.schedulePasses("屏幕唤醒")
        }
        // 唤醒后系统还会在稍晚的时候重置一次 gamma，多补两轮
        let timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.verifyQuietly()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func installReconfigCallback() {
        guard !callbackInstalled else { return }
        callbackInstalled = true
        // 回调是 C 函数指针，不能在闭包里捕获 self，用全局单例转发
        CGDisplayRegisterReconfigurationCallback({ _, flags, _ in
            let added = flags.contains(.addFlag)
            let removed = flags.contains(.removeFlag)
            let reason: String
            if added { reason = "接入" } else if removed { reason = "移除" } else { reason = "变化" }
            RestoreController.shared.schedule(reason, delay: added ? 0.05 : 0.4)
            RestoreController.shared.schedulePasses(reason)
        }, nil)
    }

    /// 唤醒后系统会在稍晚的时候再把 gamma 重置一次，而且刚醒时显示器可能还没就绪，
    /// 单次恢复一定漏。按几次不同延迟补写，谁先成功算谁的。
    func schedulePasses(_ reason: String) {
        let delays: [TimeInterval] = [0.05, 0.12, 0.3, 0.7, 1.5, 3.0, 5.0]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.restore(reason: reason)
            }
        }
    }

    func schedule(_ reason: String, delay: TimeInterval = 0.4) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.restore(reason: reason)
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// 只补写「和记录值差得多」的屏，避免盖掉用户刚拖的动作。
    func restore(reason: String) {
        let displays = Displays.enumerate(override: Store.shared.forceGamma ? .gamma : nil)
        for d in displays {
            guard let target = Store.shared.level(for: d.key) else { continue }
            guard abs(d.level - target) > 0.03 else { continue }
            Brightness.write(d.id, backend: d.backend, target)
            if d.backend == .gamma { Nudge.shared.kick(d.id) }
            Log.write("恢复（\(reason)）\(d.name): \(Int(d.level * 100))% → \(Int(target * 100))%")
            for _ in 0..<3 {
                usleep(60_000)
                if let check = Brightness.read(d.id, backend: d.backend),
                   abs(check - target) < 0.03 { break }
                Brightness.write(d.id, backend: d.backend, target)
                if d.backend == .gamma { Nudge.shared.kick(d.id) }
            }
        }
        onDisplaysChanged?()
    }

    private func verifyQuietly() {
        // 只在没有窗口交互时做一次轻量校正
        let displays = Displays.enumerate(override: Store.shared.forceGamma ? .gamma : nil)
        for d in displays where d.backend == .gamma {
            guard let target = Store.shared.level(for: d.key) else { continue }
            if abs(d.level - target) > 0.05 {
                Brightness.write(d.id, backend: .gamma, target)
                Nudge.shared.kick(d.id)
            }
        }
    }
}
