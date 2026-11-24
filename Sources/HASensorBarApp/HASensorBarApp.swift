import SwiftUI
import AppKit
import Combine
import HASensorBarCore

@main
struct HASensorBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var store: AppStore!
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var subscription: AnyCancellable?
    private var smokeWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let smoke = CommandLine.arguments.contains("--smoke-test")
        let configStore: ConfigurationStore = smoke
            ? ConfigurationStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "/configuration.json"))
            : .standard
        store = AppStore(persistence: configStore)
        store.openSettings = { [weak self] in self?.showSettings() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: "HA Sensor Bar")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        popover.contentSize = NSSize(width: 414, height: 650)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverView(store: store))
        subscription = store.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.updatePresentation() }
        }
        if smoke {
            store.showDemo()
            runSmokeTest()
        } else if CommandLine.arguments.contains("--demo") {
            store.showDemo()
            showPopover()
        } else {
            store.start()
        }
        updatePresentation()
    }

    private func updatePresentation() {
        let configuration = store.configuration
        switch configuration.menuBarMode {
        case .icon: statusItem.button?.title = ""
        case .status: statusItem.button?.title = store.errorMessage == nil ? " ·" : " !"
        case .summary: statusItem.button?.title = " " + store.menuSummary
        }
        statusItem.button?.toolTip = store.errorMessage ?? (store.isDemo ? "HA Sensor Bar · Demo" : "HA Sensor Bar")
        popover.behavior = store.pinned ? .applicationDefined : .transient
        let appearance: NSAppearance?
        switch configuration.theme {
        case .system: appearance = nil
        case .light: appearance = NSAppearance(named: .aqua)
        case .dark: appearance = NSAppearance(named: .darkAqua)
        }
        popover.appearance = appearance
        settingsWindow?.appearance = appearance
    }

    @objc private func togglePopover() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
            menu.addItem(withTitle: "Settings…", action: #selector(showSettingsAction), keyEquivalent: ",")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit HA Sensor Bar", action: #selector(quit), keyEquivalent: "q")
            for item in menu.items { item.target = self }
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else if popover.isShown {
            popover.performClose(nil)
        } else { showPopover() }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc private func refreshNow() { Task { await store.refresh() } }
    @objc private func showSettingsAction() { showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 740),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "HA Sensor Bar Settings"
            window.minSize = NSSize(width: 820, height: 650)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.titlebarAppearsTransparent = true
            window.center()
            settingsWindow = window
        }
        if settingsWindow?.contentView == nil {
            settingsWindow?.contentView = NSHostingView(rootView: SettingsView(store: store))
        }
        updatePresentation()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === settingsWindow {
            window.contentView = nil
        }
    }

    /// Renders demo views without contacting a server or touching the user's configuration.
    private func runSmokeTest() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 414, height: 650),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: PopoverView(store: store))
        window.center()
        window.makeKeyAndOrderFront(nil)
        smokeWindow = window
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, let view = self.smokeWindow?.contentView else { exit(1) }
            view.layoutSubtreeIfNeeded()
            if let index = CommandLine.arguments.firstIndex(of: "--snapshot"),
               CommandLine.arguments.indices.contains(index + 1) {
                let path = CommandLine.arguments[index + 1]
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(2) }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(3) }
                do { try png.write(to: URL(fileURLWithPath: path)) } catch { exit(4) }
            }
            self.showSettings()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                print("Smoke test passed: demo panel and settings rendered.")
                NSApp.terminate(nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { store.shutdown() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
