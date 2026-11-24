import AppKit
import Foundation

@main
enum SmokeLauncher {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = SmokeDelegate()
        application.setActivationPolicy(.regular)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class SmokeDelegate: NSObject, NSApplicationDelegate {
    private var foregroundWindow: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        foregroundWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
                                    styleMask: [.titled], backing: .buffered, defer: false)
        foregroundWindow.title = "Smoke test foreground application"
        foregroundWindow.center()
        Task {
            do { try await runTests() }
            catch {
                FileHandle.standardError.write(Data("Smoke launcher failed: \(error)\n".utf8))
                exit(1)
            }
            NSApp.terminate(nil)
        }
    }

    private func takeFocus() {
        foregroundWindow.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func runTests() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        // Keep a real AppKit event loop alive while another process owns the demo panel.
        for (index, demo) in [false, true, true, true].enumerated() {
            takeFocus()
            try await Task.sleep(nanoseconds: 200_000_000)
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
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
            guard let data = try? Data(contentsOf: snapshot), data.count > 1000 else {
                fatalError("The screenshot is missing or empty.")
            }
            print("Startup smoke pass \(index + 1): \(demo ? "pinned demo with foreground focus change" : "menu bar only").")
        }
    }
}
