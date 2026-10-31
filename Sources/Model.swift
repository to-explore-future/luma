import AppKit
import CoreGraphics

/// 一块屏幕的运行时信息。key 用于持久化，跨唤醒/插拔保持不变。
struct DisplayInfo {
    let id: CGDirectDisplayID
    let name: String
    let builtin: Bool
    let vendor: UInt32
    let model: UInt32
    let serial: UInt32
    let key: String
    let maker: String
    let backend: Backend
    var level: Float
    let asleep: Bool
    let main: Bool
}

enum Displays {
    static func onlineIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    static func isBuiltin(_ id: CGDirectDisplayID) -> Bool {
        CGDisplayIsBuiltin(id) != 0
    }

    /// EDID 厂商码：16 位里塞了三个 5 位字母，AOC / XMI / APP 之类。
    static func makerName(_ vendor: UInt32) -> String {
        guard vendor != 0 else { return "" }
        let chars = [Int((vendor >> 10) & 0x1F), Int((vendor >> 5) & 0x1F), Int(vendor & 0x1F)]
        guard chars.allSatisfy({ (1...26).contains($0) }) else { return "" }
        return String(chars.map { Character(UnicodeScalar(UInt8(64 + $0))) })
    }

    /// NSScreen.localizedName 比私有 CoreDisplay 字典省事，而且本地化过。
    static func screenNames() -> [CGDirectDisplayID: String] {
        var names: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                names[num.uint32Value] = screen.localizedName
            }
        }
        return names
    }

    static func screensByID() -> [CGDirectDisplayID: NSScreen] {
        var map: [CGDirectDisplayID: NSScreen] = [:]
        for screen in NSScreen.screens {
            if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                map[num.uint32Value] = screen
            }
        }
        return map
    }

    /// 枚举所有在线屏幕。override 为强制后端（nil = 自动）。
    static func enumerate(override: Backend? = nil) -> [DisplayInfo] {
        let names = screenNames()
        var usedKeys: [String: Int] = [:]
        var result: [DisplayInfo] = []

        for id in onlineIDs() {
            let builtin = isBuiltin(id)
            let vendor = CGDisplayVendorNumber(id)
            let model = CGDisplayModelNumber(id)
            let serial = CGDisplaySerialNumber(id)

            let baseKey: String
            if builtin {
                baseKey = "builtin"
            } else {
                baseKey = String(format: "%04x%04x%u", vendor, model, serial)
            }
            let count = (usedKeys[baseKey] ?? 0) + 1
            usedKeys[baseKey] = count
            let key = count == 1 ? baseKey : "\(baseKey)#\(count)"

            let maker = makerName(vendor)
            // EDID 厂商码解不出来 = 不是真显示器（屏幕共享/虚拟屏），
            // 对它们写 gamma 可能直接卡住，跳过。
            if !builtin && maker.isEmpty { continue }

            let backend: Backend
            if let override = override {
                backend = builtin ? .native : override
            } else {
                backend = (builtin || Brightness.nativeSupported(id)) ? .native : .gamma
            }

            let name = names[id] ?? (builtin ? "内建显示器" : String(format: "外接显示器 %04x:%04x", vendor, model))
            let level = Brightness.read(id, backend: backend) ?? 1.0

            result.append(DisplayInfo(
                id: id, name: name, builtin: builtin,
                vendor: vendor, model: model, serial: serial,
                key: key, maker: maker, backend: backend,
                level: level,
                asleep: CGDisplayIsAsleep(id) != 0,
                main: CGDisplayIsMain(id) != 0
            ))
        }
        return result
    }
}
