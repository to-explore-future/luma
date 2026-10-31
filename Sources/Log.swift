import Foundation

enum Log {
    private static let path = NSHomeDirectory() + "/Library/Application Support/Luma/luma-swift.log"
    private static let queue = DispatchQueue(label: "luma.log")

    static func write(_ message: String) {
        queue.async {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let line = "\(formatter.string(from: Date()))  \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
    }
}
