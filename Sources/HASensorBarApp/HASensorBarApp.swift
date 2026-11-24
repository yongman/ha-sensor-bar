import SwiftUI
import AppKit
import Combine
import HASensorBarCore

@main
enum HASensorBarApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var store: AppStore!
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let popoverPresenter = PopoverPresenter()
    private var settingsWindow: NSWindow?
    private var subscription: AnyCancellable?
    private var smokeWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let smoke = CommandLine.arguments.contains("--smoke-test")
        let demo = CommandLine.arguments.contains("--demo")
        let configStore: ConfigurationStore = smoke
            ? ConfigurationStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "/configuration.json"))
            : .standard
        store = AppStore(persistence: configStore)
        store.openSettings = { [weak self] in self?.showSettings() }
        installMainMenu()
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
        if demo {
            store.showDemo()
            // A launch preview must survive activation changes from the user's desktop.
            store.pinned = true
        } else if !smoke {
            store.start()
        }
        updatePresentation()
        if demo { showPopover() }
        if smoke {
            if demo, let index = CommandLine.arguments.firstIndex(of: "--foreground-pid"),
               CommandLine.arguments.indices.contains(index + 1),
               let pid = Int32(CommandLine.arguments[index + 1]) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if let application = NSRunningApplication(processIdentifier: pid) {
                        NSApp.yieldActivation(to: application)
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self else { exit(1) }
                let visibleWindows = NSApp.windows.filter { $0.isVisible && $0.level == .normal }
                precondition(self.settingsWindow == nil, "Startup must not open Settings.")
                precondition(!visibleWindows.contains { $0.title.contains("Settings") },
                             "Startup must not open a blank Settings window.")
                if demo {
                    let windowVisible = self.popover.contentViewController?.view.window?.isVisible == true
                    let foregroundPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
                    let state = "Demo smoke: pinned=\(self.store.pinned), shown=\(self.popover.isShown), "
                        + "windowVisible=\(windowVisible), foregroundPID=\(foregroundPID), "
                        + "anchorAttached=\(self.statusItem.button?.window != nil)\n"
                    FileHandle.standardError.write(Data(state.utf8))
                    precondition(self.store.isDemo && self.store.pinned
                                 && self.popover.behavior == .applicationDefined
                                 && self.popover.isShown
                                 && windowVisible,
                                 "Demo startup must keep the pinned demo popover visible after focus changes.")
                    if let index = CommandLine.arguments.firstIndex(of: "--foreground-pid"),
                       CommandLine.arguments.indices.contains(index + 1),
                       let foregroundPID = Int32(CommandLine.arguments[index + 1]) {
                        precondition(NSWorkspace.shared.frontmostApplication?.processIdentifier == foregroundPID,
                                     "The smoke launcher must own foreground focus while the demo stays visible.")
                    }
                } else {
                    precondition(visibleWindows.isEmpty, "Normal startup must remain in the menu bar.")
                }
                precondition(NSApp.activationPolicy() == .accessory, "The app must remain an accessory.")
                self.closePopover()
                self.store.showDemo()
                self.runSmokeTest()
            }
        }
    }

    private func installMainMenu() {
        let menu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "HA Sensor Bar")
        applicationMenu.addItem(withTitle: "Settings…", action: #selector(showSettingsAction), keyEquivalent: ",")
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Quit HA Sensor Bar", action: #selector(quit), keyEquivalent: "q")
        for item in applicationMenu.items { item.target = self }
        applicationItem.submenu = applicationMenu
        menu.addItem(applicationItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApp.mainMenu = menu
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
            closePopover()
        } else { showPopover() }
    }

    private func showPopover() {
        updatePresentation()
        popoverPresenter.show { [weak self] in
            guard let self else { return false }
            NSApp.activate()
            guard let button = self.statusItem.button, let window = button.window else { return false }
            window.contentView?.layoutSubtreeIfNeeded()
            button.layoutSubtreeIfNeeded()
            guard !button.bounds.isEmpty else { return false }
            self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            if self.store.pinned { self.popover.contentViewController?.view.window?.hidesOnDeactivate = false }
            self.popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
            return self.popover.isShown && self.popover.contentViewController?.view.window?.isVisible == true
        }
    }

    private func closePopover() {
        popoverPresenter.cancel()
        popover.performClose(nil)
    }

    @objc private func refreshNow() { Task { await store.refresh() } }
    @objc private func showSettingsAction() { showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func showSettings() {
        closePopover()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 740),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "HA Sensor Bar Settings"
            window.identifier = NSUserInterfaceItemIdentifier("HASensorBarSettings")
            window.minSize = NSSize(width: 820, height: 650)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.titlebarAppearsTransparent = true
            window.contentView = NSHostingView(rootView: SettingsView(store: store))
            window.center()
            settingsWindow = window
        }
        if settingsWindow?.contentView == nil {
            settingsWindow?.contentView = NSHostingView(rootView: SettingsView(store: store))
        }
        updatePresentation()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
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
            guard let menu = NSApp.mainMenu?.items.first?.submenu,
                  let item = menu.items.first(where: { $0.keyEquivalent == "," }) else { exit(5) }
            menu.performActionForItem(at: menu.index(of: item))
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                guard let settings = self.settingsWindow, settings.isVisible,
                      settings.contentView is NSHostingView<SettingsView> else { exit(6) }
                settings.close()
                menu.performActionForItem(at: menu.index(of: item))
                guard self.settingsWindow === settings, settings.isVisible,
                      settings.contentView is NSHostingView<SettingsView> else { exit(7) }
                print("Smoke test passed: accessory startup, demo, Settings menu shortcut, and Settings reopening.")
                NSApp.terminate(nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        popoverPresenter.cancel()
        store.shutdown()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
