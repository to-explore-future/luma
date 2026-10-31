import Foundation

/// 状态持久化：每块屏的亮度按稳定 key 记账，外加全局设置。
final class Store {
    struct State: Codable {
        var levels: [String: Double] = [:]
        var forceGamma: Bool = false
    }

    private(set) var state = State()
    private let path: String
    private var savePending: DispatchWorkItem?

    static let shared = Store()

    private init() {
        let dir = NSHomeDirectory() + "/Library/Application Support/Luma"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        path = dir + "/state.json"
        if let data = FileManager.default.contents(atPath: path),
           let decoded = try? JSONDecoder().decode(State.self, from: data) {
            state = decoded
        }
    }

    func level(for key: String) -> Float? {
        state.levels[key].map { Float($0) }
    }

    func setLevel(_ value: Float, for key: String) {
        state.levels[key] = Double(value)
        scheduleSave()
    }

    var forceGamma: Bool {
        get { state.forceGamma }
        set { state.forceGamma = newValue; scheduleSave() }
    }

    private func scheduleSave() {
        savePending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        savePending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func saveNow() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
