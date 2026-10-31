import CoreGraphics
import Darwin

/// 两块调光后端：
/// - native：DisplayServices（Apple 私有框架），内置屏和部分外接屏走这条，改的是真背光
/// - gamma ：CGSetDisplayTransferByFormula，任何显示器都能用，但只是把画面压暗
enum Backend {
    case native
    case gamma

    var label: String {
        self == .native ? "系统原生" : "软件调光"
    }
}

private let dsPath = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"

private enum DS {
    static let handle: UnsafeMutableRawPointer? = dlopen(dsPath, RTLD_NOW)

    typealias CanChangeFn = @convention(c) (CGDirectDisplayID) -> Bool
    typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    static let canChange: CanChangeFn? = {
        guard let h = handle, let sym = dlsym(h, "DisplayServicesCanChangeBrightness") else { return nil }
        return unsafeBitCast(sym, to: CanChangeFn.self)
    }()

    static let get: GetFn? = {
        guard let h = handle, let sym = dlsym(h, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(sym, to: GetFn.self)
    }()

    static let set: SetFn? = {
        guard let h = handle, let sym = dlsym(h, "DisplayServicesSetBrightness") else { return nil }
        return unsafeBitCast(sym, to: SetFn.self)
    }()
}

enum Brightness {
    /// 系统是否认为这块屏的亮度可以由软件直接改。
    static func nativeSupported(_ id: CGDirectDisplayID) -> Bool {
        guard let fn = DS.canChange else { return false }
        return fn(id)
    }

    static func nativeGet(_ id: CGDirectDisplayID) -> Float? {
        guard let fn = DS.get else { return nil }
        var value: Float = 0
        guard fn(id, &value) == 0 else { return nil }
        return min(1, max(0, value))
    }

    @discardableResult
    static func nativeSet(_ id: CGDirectDisplayID, _ value: Float) -> Bool {
        guard let fn = DS.set else { return false }
        return fn(id, min(1, max(0, value))) == 0
    }

    /// 读 gamma 的当前上限（三通道取最大值），1.0 = 没有压暗。
    static func gammaGet(_ id: CGDirectDisplayID) -> Float? {
        var rMin: Float = 0, rMax: Float = 0, rGamma: Float = 0
        var gMin: Float = 0, gMax: Float = 0, gGamma: Float = 0
        var bMin: Float = 0, bMax: Float = 0, bGamma: Float = 0
        let err = CGGetDisplayTransferByFormula(id, &rMin, &rMax, &rGamma,
                                                &gMin, &gMax, &gGamma,
                                                &bMin, &bMax, &bGamma)
        guard err == .success else { return nil }
        return min(1, max(0, max(rMax, max(gMax, bMax))))
    }

    /// 用 gamma 把整块屏压暗；value = 1.0 即恢复原样。
    @discardableResult
    static func gammaSet(_ id: CGDirectDisplayID, _ value: Float) -> Bool {
        let v = min(1, max(0, value))
        let err = CGSetDisplayTransferByFormula(id, 0, v, 1, 0, v, 1, 0, v, 1)
        return err == .success
    }

    static func read(_ id: CGDirectDisplayID, backend: Backend) -> Float? {
        backend == .native ? nativeGet(id) : gammaGet(id)
    }

    @discardableResult
    static func write(_ id: CGDirectDisplayID, backend: Backend, _ value: Float) -> Bool {
        if backend == .native {
            return nativeSet(id, value)
        }
        return gammaSet(id, value)
    }
}
