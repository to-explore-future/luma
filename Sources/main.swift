import AppKit
import Darwin

if CommandLine.arguments.contains("--selftest") {
    exit(SelfTest.run())
}

// 单实例：两个进程同时写亮度会互相打架
let lockFD = open("/tmp/luma-swift.lock", O_CREAT | O_RDWR, 0o644)
if lockFD >= 0 && flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
