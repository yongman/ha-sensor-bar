import SwiftUI
import HASensorBarCore

struct DiscoveryView: View {
    @ObservedObject var store: AppStore
    let configuration: AppConfiguration
    let token: DraftToken
    @Binding var groups: [SensorGroup]
    @Environment(\.dismiss) private var dismiss
    @State private var entities: [HAEntity] = []
    @State private var suggestions: [CardSuggestion] = []
    @State private var selectedSuggestions = Set<UUID>()
    @State private var selectedEntities = Set<String>()
    @State private var query = ""
    @State private var loading = true
    @State private var error: String?
    @State private var mode = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Find your signals.").font(.system(size: 24, weight: .medium, design: .rounded))
                    Text("Choose the cards you want. Nothing is added until you confirm.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if loading {
                ProgressView("Reading Home Assistant sensors…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                ContentUnavailableView("Could not discover sensors", systemImage: "wifi.exclamationmark", description: Text(error))
                Button("Retry") { Task { await load() } }
            } else {
                Picker("Show", selection: $mode) {
                    Text("Recommended Cards (\(suggestions.count))").tag(0)
                    Text("All Sensors (\(entities.count))").tag(1)
                }.pickerStyle(.segmented)
                TextField("Search sensor ID or name", text: $query)
                List {
                    if mode == 0 {
                        ForEach(suggestions.filter { query.isEmpty || $0.card.title.localizedCaseInsensitiveContains(query) ||
                            $0.entityIDs.contains(where: { $0.localizedCaseInsensitiveContains(query) }) }) { suggestion in
                            Toggle(isOn: Binding(get: { selectedSuggestions.contains(suggestion.id) }, set: {
                                if $0 { selectedSuggestions.insert(suggestion.id) } else { selectedSuggestions.remove(suggestion.id) }
                            })) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(suggestion.group + " · " + suggestion.card.title).font(.headline)
                                        if !suggestion.card.tag.isEmpty { Pill(text: suggestion.card.tag) }
                                    }
                                    ForEach(suggestion.warnings, id: \.self) { warning in
                                        Label(warning, systemImage: "exclamationmark.triangle")
                                            .font(.caption).foregroundStyle(.orange)
                                    }
                                    ForEach(suggestion.entityIDs, id: \.self) { Text($0).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary) }
                                }.padding(.vertical, 5)
                            }.toggleStyle(.checkbox)
                        }
                    } else {
                        ForEach(SensorDiscovery.sensors(in: entities, search: query)) { entity in
                            Toggle(isOn: Binding(get: { selectedEntities.contains(entity.id) }, set: {
                                if $0 { selectedEntities.insert(entity.id) } else { selectedEntities.remove(entity.id) }
                            })) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entity.friendlyName).font(.headline)
                                    Text("\(entity.entityID) · \(entity.state) \(entity.unit ?? "")")
                                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                                }.padding(.vertical, 3)
                            }.toggleStyle(.checkbox)
                        }
                    }
                }.scrollContentBackground(.hidden)
                Text("Magpie cards appear first. Legacy sensors and currency values remain visible for review. Adding from All Sensors creates a card with a Value field.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text("\(mode == 0 ? selectedSuggestions.count : selectedEntities.count) selected").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Add Selected") { addSelected(); dismiss() }
                    .buttonStyle(.borderedProminent).tint(.teal)
                    .disabled(loading || (mode == 0 ? selectedSuggestions.isEmpty : selectedEntities.isEmpty))
            }
        }
        .padding(24).frame(width: 740, height: 600)
        .background(GlassBackground())
        .task { await load() }
    }

    private func load() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let client = try store.makeClient(configuration: configuration.validated(), draftToken: token)
            let result = try await client.fetchStates()
            try Task.checkCancellation()
            entities = SensorDiscovery.sensors(in: result)
            suggestions = SensorDiscovery.suggest(entities)
            selectedSuggestions = []
            selectedEntities = []
        } catch is CancellationError {
        } catch { self.error = error.localizedDescription }
    }

    private func addSelected() {
        if mode == 0 {
            for suggestion in suggestions where selectedSuggestions.contains(suggestion.id) {
                append(suggestion.card, to: suggestion.group)
            }
        } else {
            for entity in entities where selectedEntities.contains(entity.id) {
                append(SensorCard(title: entity.friendlyName, symbol: "waveform.path",
                                  extras: [SensorField(title: "Value", binding: FieldBinding(entityID: entity.id))]), to: "Sensors")
            }
        }
    }

    private func append(_ card: SensorCard, to name: String) {
        if let index = groups.firstIndex(where: { $0.title == name }) {
            let sources = Set(card.fields.map(\.binding))
            guard !groups[index].cards.contains(where: { Set($0.fields.map(\.binding)) == sources }) else { return }
            groups[index].cards.append(card)
        } else { groups.append(SensorGroup(title: name, cards: [card])) }
    }
}
