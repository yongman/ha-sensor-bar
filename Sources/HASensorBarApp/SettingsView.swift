import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers
import HASensorBarCore

struct SettingsView: View {
    @ObservedObject var store: AppStore
    @State private var draft: AppConfiguration
    @State private var token = DraftToken()
    @State private var message = ""
    @State private var failed = false
    @State private var testing = false
    @State private var connectionTask: Task<Void, Never>?
    @State private var discovering = false
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled

    init(store: AppStore) {
        self.store = store
        _draft = State(initialValue: store.configuration)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 29)).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Make room for your signals.").font(.system(size: 22, weight: .medium, design: .rounded))
                    Text("A personal view of Home Assistant, always close by.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(24)
            TabView {
                connection.tabItem { Label("Connection", systemImage: "network") }
                cards.tabItem { Label("Cards & Sensors", systemImage: "rectangle.stack") }
                appearance.tabItem { Label("Appearance & Menu Bar", systemImage: "paintpalette") }
                general.tabItem { Label("Import/Export & General", systemImage: "square.and.arrow.up") }
            }.padding(.horizontal, 18)
            HStack {
                if !message.isEmpty {
                    Image(systemName: failed ? "exclamationmark.circle" : "checkmark.circle").foregroundStyle(failed ? .orange : .teal)
                    Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                } else {
                    Text("Changes apply when you save. Tokens stay in Keychain.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Save Changes") {
                    perform {
                        try store.save(draft, draftToken: token)
                        draft = store.configuration
                        token = DraftToken()
                        return (try? BaseURL.parse(draft.baseURL))?.scheme == "http" && !draft.allowsInsecureHTTP
                            ? "Settings saved. HTTP is disabled and polling is paused." : "Settings saved."
                    }
                }.buttonStyle(.borderedProminent).tint(.teal).keyboardShortcut("s", modifiers: .command)
                    .disabled(testing)
            }.padding(20)
        }
        .background(GlassBackground(style: draft.glassStyle))
        .sheet(isPresented: $discovering) { DiscoveryView(store: store, configuration: draft, token: token, groups: $draft.groups) }
        .onChange(of: draft.baseURL) { old, new in
            token = DraftToken()
            if (try? BaseURL.parse(old)) != (try? BaseURL.parse(new)) {
                draft.insecureHTTPAllowedFor = nil
            }
            connectionTask?.cancel()
            message = ""
        }
        .onChange(of: draft.insecureHTTPAllowedFor) { _, _ in connectionTask?.cancel() }
        .onDisappear { token = DraftToken(); connectionTask?.cancel() }
    }

    private var connection: some View {
        Form {
            Section("Home Assistant") {
                TextField("Base URL", text: Binding(get: { draft.baseURL }, set: {
                    token = DraftToken()
                    draft.insecureHTTPAllowedFor = nil
                    connectionTask?.cancel()
                    draft.baseURL = $0
                }), prompt: Text("http://homeassistant.local:8123"))
                    .textContentType(.URL)
                SecureField(store.hasSavedToken(for: draft.baseURL) ? "Token saved in Keychain · enter to replace" : "Long-Lived Access Token",
                            text: Binding(get: { token.value }, set: { value in
                                perform { token = try DraftToken(value: value, server: draft.baseURL); return "" }
                            }))
                    .disabled((try? BaseURL.parse(draft.baseURL)) == nil)
                Text("Create a token from your Home Assistant profile → Security. The token is saved only in macOS Keychain and is scoped to this server URL.")
                    .font(.caption).foregroundStyle(.secondary)
                if let endpoint = try? BaseURL.parse(draft.baseURL), endpoint.scheme == "http" {
                    Label("HTTP sends your token without encryption. Use it only on a trusted local network.",
                          systemImage: "network.badge.shield.half.filled").font(.caption).foregroundStyle(.secondary)
                    Toggle("Allow unencrypted HTTP for this server", isOn: Binding(
                        get: { draft.allowsInsecureHTTP },
                        set: {
                            draft.insecureHTTPAllowedFor = $0 ? endpoint.absoluteString : nil
                            if !$0 { token = DraftToken() }
                        }
                    ))
                    Text("Turn this off and save to stop HTTP polling. Your saved token stays in Keychain.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button(testing ? "Testing…" : "Test Connection") {
                        testing = true
                        connectionTask = Task {
                            defer { testing = false }
                            do {
                                let client = try store.makeClient(configuration: draft.validated(), draftToken: token)
                                try await client.testConnection()
                                try Task.checkCancellation()
                                message = "Connected to Home Assistant."
                                failed = false
                            } catch is CancellationError {
                            } catch { message = error.localizedDescription; failed = true }
                        }
                    }.disabled(testing)
                    Button("Forget Saved Token", role: .destructive) {
                        perform { try store.removeToken(for: draft.baseURL); token = DraftToken(); return "Saved token removed." }
                    }.disabled(!store.hasSavedToken(for: draft.baseURL))
                }
            }
            Section("Refresh") {
                Picker("Poll every", selection: $draft.refreshInterval) {
                    Text("30 seconds").tag(30.0)
                    Text("1 minute").tag(60.0)
                    Text("2 minutes").tag(120.0)
                    Text("5 minutes").tag(300.0)
                    if ![30.0, 60, 120, 300].contains(draft.refreshInterval) {
                        Text("\(Int(draft.refreshInterval)) seconds").tag(draft.refreshInterval)
                    }
                }
                HStack {
                    Text("Request timeout")
                    Spacer()
                    TextField("Seconds", value: $draft.timeout, format: .number).frame(width: 70)
                    Text("seconds").foregroundStyle(.secondary)
                }
                Text("Refreshes run sequentially. Failed requests keep the last successful snapshot and display an error.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }

    private var cards: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Bind each field to a sensor state or a nested attribute.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Discover Sensors…") { discovering = true }.disabled(draft.baseURL.isEmpty)
            }.padding(.horizontal, 12).padding(.top, 12)
            CardsEditor(groups: $draft.groups)
        }
    }

    private var appearance: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $draft.theme) {
                    Text("Follow System").tag(AppTheme.system)
                    Text("Light").tag(AppTheme.light)
                    Text("Dark").tag(AppTheme.dark)
                }
                Picker("Glass", selection: $draft.glassStyle) {
                    Text("Airy").tag(GlassStyle.clear)
                    Text("Balanced").tag(GlassStyle.balanced)
                    Text("Quiet / Solid").tag(GlassStyle.solid)
                }
            }
            Section("Menu Bar") {
                Picker("Display", selection: $draft.menuBarMode) {
                    Text("Icon only").tag(MenuBarMode.icon)
                    Text("Icon + connection status").tag(MenuBarMode.status)
                    Text("Icon + lowest remaining quota").tag(MenuBarMode.summary)
                }
                Picker("Primary card", selection: $draft.primaryCardID) {
                    Text("First card").tag(nil as UUID?)
                    ForEach(draft.cards) { card in Text(card.title).tag(Optional(card.id)) }
                }
                Text("The summary uses the lower remaining percentage of the primary card's 5h and 7d fields. Amounts and unavailable values are excluded.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Login") {
                Toggle("Open HA Sensor Bar at login", isOn: Binding(get: { loginEnabled }, set: { enabled in
                    perform {
                        if enabled { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                        loginEnabled = SMAppService.mainApp.status == .enabled
                        return SMAppService.mainApp.status == .requiresApproval
                            ? "Allow HA Sensor Bar in System Settings → Login Items." : "Login preference updated."
                    }
                }))
                Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
                Text("Install the app in Applications before enabling launch at login.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }

    private var general: some View {
        Form {
            Section("Your layout, anywhere") {
                Text("Export connection preferences, groups, cards, and every field binding. Access tokens are never included. Imports remain editable until you save.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Export JSON…") {
                        perform {
                            let data = try ConfigurationCodec.export(draft)
                            let panel = NSSavePanel()
                            panel.allowedContentTypes = [.json]
                            panel.nameFieldStringValue = "HA-Sensor-Bar.json"
                            if panel.runModal() == .OK, let url = panel.url {
                                try data.write(to: url, options: .atomic)
                                return "Configuration exported without access tokens."
                            }
                            return ""
                        }
                    }
                    Button("Import JSON…") {
                        perform {
                            let panel = NSOpenPanel()
                            panel.allowedContentTypes = [.json]
                            panel.allowsMultipleSelection = false
                            guard panel.runModal() == .OK, let url = panel.url else { return "" }
                            let data = try Data(contentsOf: url)
                            guard data.count <= 2_000_000 else {
                                throw NSError(domain: "Import", code: 1, userInfo: [NSLocalizedDescriptionKey: "Configuration is too large (maximum 2 MB)."])
                            }
                            draft = try ConfigurationCodec.importData(data)
                            draft.insecureHTTPAllowedFor = nil
                            token = DraftToken()
                            return "Imported layout ready. Review it, then save. Add a token if this server is new."
                        }
                    }
                }
            }
            Section("Preview") {
                Button("Load Demo Mode") { store.showDemo(); message = "Demo is active in the menu bar panel."; failed = false }
                if store.isDemo { Button("Exit Demo Mode") { store.leaveDemo() } }
                Text("Demo data is temporary and never replaces your saved layout.").font(.caption).foregroundStyle(.secondary)
            }
            Section("HA Sensor Bar") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")
                Text("Made for Apple Silicon · macOS 14 or later").font(.caption).foregroundStyle(.secondary)
                Text("Reset times appear only when explicitly bound. HA last_updated is shown separately from the client sync time.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }

    private func perform(_ action: () throws -> String) {
        do { message = try action(); failed = false }
        catch { message = error.localizedDescription; failed = true }
    }
}
