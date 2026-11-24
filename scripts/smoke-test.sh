#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist
swift - <<'SWIFT'
import Foundation
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let process = Process()
process.executableURL = root.appendingPathComponent("dist/HA Sensor Bar.app/Contents/MacOS/HASensorBarApp")
let snapshot = root.appendingPathComponent("dist/demo-preview.png")
try? FileManager.default.removeItem(at: snapshot)
process.arguments = ["--smoke-test", "--snapshot", snapshot.path]
try process.run()
let watchdog = DispatchSource.makeTimerSource()
watchdog.schedule(deadline: .now() + 30)
watchdog.setEventHandler { if process.isRunning { process.terminate() } }
watchdog.resume()
process.waitUntilExit()
watchdog.cancel()
guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
guard let data = try? Data(contentsOf: snapshot), data.count > 1000 else {
    fatalError("The demo screenshot is missing or empty.")
}
SWIFT
