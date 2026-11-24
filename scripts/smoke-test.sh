#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist
swift - <<'SWIFT'
import Foundation
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let application = NSApplication.shared
application.setActivationPolicy(.regular)
let foregroundWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
                                styleMask: [.titled], backing: .buffered, defer: false)
foregroundWindow.title = "Smoke test foreground application"
foregroundWindow.center()
@MainActor func takeFocus() {
    foregroundWindow.makeKeyAndOrderFront(nil)
    application.activate()
}
// Repeated demo launches exercise status-item startup while another app owns focus.
for (index, demo) in [false, true, true, true].enumerated() {
    takeFocus()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
    let process = Process()
    process.executableURL = root.appendingPathComponent("dist/HA Sensor Bar.app/Contents/MacOS/HASensorBarApp")
    let snapshot = root.appendingPathComponent(demo ? "dist/demo-preview.png" : "dist/startup-preview.png")
    try? FileManager.default.removeItem(at: snapshot)
    process.arguments = ["--smoke-test", "--snapshot", snapshot.path]
        + (demo ? ["--demo", "--foreground-pid", String(ProcessInfo.processInfo.processIdentifier)] : [])
    try process.run()
    let started = Date()
    var changedFocus = false
    while process.isRunning && Date().timeIntervalSince(started) < 30 {
        if demo && !changedFocus && Date().timeIntervalSince(started) > 2.2 {
            takeFocus()
            changedFocus = true
        }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    }
    if process.isRunning { process.terminate() }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
    guard let data = try? Data(contentsOf: snapshot), data.count > 1000 else {
        fatalError("The screenshot is missing or empty.")
    }
    print("Startup smoke pass \(index + 1): \(demo ? "pinned demo with foreground focus change" : "menu bar only").")
}
foregroundWindow.orderOut(nil)
SWIFT
