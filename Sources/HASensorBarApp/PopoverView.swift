import SwiftUI
import HASensorBarCore

struct PopoverView: View {
    @ObservedObject var store: AppStore
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 22)).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sensor Bar").font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text(store.isDemo ? "A LITTLE PREVIEW" : "HOME ASSISTANT")
                        .font(.system(size: 8, weight: .bold)).tracking(1.8).foregroundStyle(.secondary)
                }
                Spacer()
                IconButton(symbol: store.pinned ? "pin.fill" : "pin", help: "Pin panel", active: store.pinned) {
                    store.pinned.toggle()
                }
                IconButton(symbol: "arrow.clockwise", help: "Refresh sensors") { Task { await store.refresh() } }
                    .disabled(store.isRefreshing || store.isDemo)
                IconButton(symbol: "slider.horizontal.3", help: "Open Settings") { store.openSettings() }
            }.padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 17)

            if let message = store.errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.wifi")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(message)
                        if store.lastSync != nil { Text("Showing the last successful sync.").font(.caption2) }
                    }
                    Spacer(minLength: 0)
                    Button("Settings") { store.openSettings() }.buttonStyle(.link)
                }.font(.caption).foregroundStyle(.orange)
                    .padding(12).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 18).padding(.bottom, 10)
            }

            if store.displayedConfiguration.groups.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 19) {
                        if store.isDemo {
                            HStack {
                                Pill(text: "DEMO", tint: .teal)
                                Text("Sample data, room to make it yours.").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("Exit") { store.leaveDemo() }.buttonStyle(.link).font(.caption)
                            }
                        }
                        ForEach(store.displayedConfiguration.groups) { group in
                            VStack(spacing: 10) {
                                Button { store.toggleGroup(group.id) } label: {
                                    HStack {
                                        Text(group.title.uppercased()).font(.system(size: 9, weight: .bold)).tracking(1.5)
                                        Text("\(group.cards.count)").font(.system(size: 9, weight: .medium))
                                            .padding(.horizontal, 5).padding(.vertical, 2)
                                            .background(Color.primary.opacity(0.05), in: Capsule())
                                        Spacer()
                                        Image(systemName: group.collapsed ? "chevron.right" : "chevron.down").font(.system(size: 9, weight: .semibold))
                                    }.foregroundStyle(.secondary).padding(.horizontal, 3).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                    .draggable(group.id.uuidString)
                                    .dropDestination(for: String.self) { items, _ in
                                        guard let id = items.first else { return false }
                                        store.moveGroup(id, before: group.id)
                                        return true
                                    }
                                if !group.collapsed {
                                    ForEach(group.cards) { card in SensorCardView(card: card, entities: store.entities) }
                                }
                            }
                        }
                    }.padding(.horizontal, 18).padding(.top, 5).padding(.bottom, 18)
                }.scrollIndicators(.hidden)
            }
            footer
        }
        .frame(width: 414, height: 650)
        .background(GlassBackground(style: store.configuration.glassStyle))
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.3)).frame(height: 1) }
        .alert("HA Sensor Bar", isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })) {
            Button("OK") { store.notice = nil }
        } message: { Text(store.notice ?? "") }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle().fill(.teal.opacity(0.07)).frame(width: 98, height: 98)
                Image(systemName: "waveform.path").font(.system(size: 38, weight: .light)).foregroundStyle(.teal)
            }
            Text("Your quotas, at a glance.").font(.system(size: 21, weight: .medium, design: .rounded))
            Text("Bring your Home Assistant sensors into a\nquiet corner of your menu bar.")
                .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(4)
            Button(store.hasConnection ? "Discover your sensors" : "Connect Home Assistant") { store.openSettings() }
                .buttonStyle(.borderedProminent).tint(.teal).controlSize(.large)
            Button("Explore demo mode") { store.showDemo() }.buttonStyle(.plain).foregroundStyle(.secondary).font(.caption)
            Spacer()
        }.frame(maxWidth: .infinity).padding(26)
    }

    private var footer: some View {
        VStack(spacing: 5) {
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
            HStack(spacing: 6) {
                Circle().fill(store.errorMessage != nil ? Color.orange : store.lastSync != nil ? .teal : .secondary)
                    .frame(width: 5, height: 5)
                if store.isRefreshing {
                    Text("Syncing…").font(.system(size: 10)).foregroundStyle(.secondary)
                } else if let date = store.lastSync {
                    Text("Synced \(date.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .help("Client fetch completed: \(date.formatted())")
                } else {
                    Text("Ready when you are").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                if let date = store.latestHAUpdate {
                    Text("HA \(date.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 9)).foregroundStyle(.tertiary)
                        .help("Latest last_updated among configured sensors: \(date.formatted())")
                }
            }.padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 13)
        }
    }
}
