import AppKit
import Foundation
import Darwin

@main
enum SmokeLauncher {
    @MainActor static func main() {
        func argument(_ name: String) -> String {
            guard let index = CommandLine.arguments.firstIndex(of: name),
                  CommandLine.arguments.indices.contains(index + 1) else { exit(1) }
            return CommandLine.arguments[index + 1]
        }
        guard let log = try? FileHandle(forWritingTo: URL(fileURLWithPath: argument("--log"))) else { exit(1) }
        dup2(log.fileDescriptor, STDOUT_FILENO)
        dup2(log.fileDescriptor, STDERR_FILENO)
        try? log.close()
        let application = NSApplication.shared
        let delegate = SmokeDelegate(root: URL(fileURLWithPath: argument("--root")),
                                     result: URL(fileURLWithPath: argument("--result")))
        application.setActivationPolicy(.regular)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class SmokeDelegate: NSObject, NSApplicationDelegate {
    private var foregroundWindow: NSWindow!
    private let root: URL
    private let result: URL

    init(root: URL, result: URL) {
        self.root = root
        self.result = result
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        foregroundWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
                                    styleMask: [.titled], backing: .buffered, defer: false)
        foregroundWindow.title = "Smoke test foreground application"
        foregroundWindow.center()
        Task {
            do {
                try await runTests()
                try "passed".write(to: result, atomically: true, encoding: .utf8)
            }
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
            if let application = NSRunningApplication(processIdentifier: process.processIdentifier) {
                NSApp.yieldActivation(to: application)
            }
            let started = Date()
            var changedFocus = false
            while process.isRunning && Date().timeIntervalSince(started) < 30 {
                if demo && !changedFocus && Date().timeIntervalSince(started) > 2.2 {
                    takeFocus()
                    changedFocus = NSApp.isActive
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
