import SwiftUI
import HASensorBarCore

struct CardsEditor: View {
    @Binding var groups: [SensorGroup]
    @State private var selected: UUID?
    @State private var draggedGroup: String?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 8) {
                List(selection: $selected) {
                    ForEach($groups) { $group in
                        Text(group.title).tag(group.id)
                            .draggable(group.id.uuidString)
                            .dropDestination(for: String.self) { items, _ in
                                guard let id = items.first,
                                      let from = groups.firstIndex(where: { $0.id.uuidString == id }),
                                      let to = groups.firstIndex(where: { $0.id == group.id }), from != to else { return false }
                                groups.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                                return true
                            }
                    }
                    .onDelete { groups.remove(atOffsets: $0) }
                    .onMove { groups.move(fromOffsets: $0, toOffset: $1) }
                }.scrollContentBackground(.hidden)
                HStack {
                    Button { let group = SensorGroup(title: "New Group"); groups.append(group); selected = group.id } label: {
                        Label("Group", systemImage: "plus")
                    }
                    Button(role: .destructive) {
                        groups.removeAll { $0.id == selected }
                        selected = groups.first?.id
                    } label: { Image(systemName: "minus") }.disabled(selected == nil)
                    Spacer(minLength: 0)
                }.padding(10)
            }.frame(width: 170)
            Divider()
            if let index = groups.firstIndex(where: { $0.id == selected }) {
                GroupEditor(group: $groups[index]).id(groups[index].id)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.stack.badge.plus").font(.largeTitle).foregroundStyle(.teal)
                    Text("A place for every account.").font(.headline)
                    Text("Add a group or discover sensors to get started.").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { if selected == nil { selected = groups.first?.id } }
        .onChange(of: groups.map(\.id)) { _, ids in
            if !ids.contains(selected ?? UUID()) { selected = ids.first }
        }
    }
}

private struct GroupEditor: View {
    @Binding var group: SensorGroup
    @State private var selectedCard: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Group title", text: $group.title).font(.headline)
                Toggle("Collapsed", isOn: $group.collapsed).toggleStyle(.checkbox)
            }.padding(.horizontal, 14).padding(.top, 12)
            HStack(spacing: 8) {
                Picker("Card", selection: $selectedCard) {
                    Text("Select a card").tag(nil as UUID?)
                    ForEach(group.cards) { card in Text(card.title).tag(Optional(card.id)) }
                }
                Button {
                    let card = SensorCard(title: "New Card")
                    group.cards.append(card)
                    selectedCard = card.id
                } label: { Image(systemName: "plus") }.help("Add card")
                Button(role: .destructive) {
                    group.cards.removeAll { $0.id == selectedCard }
                    selectedCard = group.cards.first?.id
                } label: { Image(systemName: "trash") }.disabled(selectedCard == nil)
                Button { moveCard(by: -1) } label: { Image(systemName: "arrow.up") }.help("Move card up").disabled(!canMove(-1))
                Button { moveCard(by: 1) } label: { Image(systemName: "arrow.down") }.help("Move card down").disabled(!canMove(1))
            }.padding(.horizontal, 14)
            if let index = group.cards.firstIndex(where: { $0.id == selectedCard }) {
                CardEditor(card: $group.cards[index]).id(group.cards[index].id)
            } else {
                Text("Add a card, then bind its fields to your sensors.").foregroundStyle(.secondary).padding(20)
                Spacer()
            }
        }.onAppear { selectedCard = group.cards.first?.id }
            .onChange(of: group.cards.map(\.id)) { _, ids in
                if !ids.contains(selectedCard ?? UUID()) { selectedCard = ids.first }
            }
    }
    private func canMove(_ offset: Int) -> Bool {
        guard let index = group.cards.firstIndex(where: { $0.id == selectedCard }) else { return false }
        return group.cards.indices.contains(index + offset)
    }
    private func moveCard(by offset: Int) {
        guard let index = group.cards.firstIndex(where: { $0.id == selectedCard }), canMove(offset) else { return }
        group.cards.swapAt(index, index + offset)
    }
}

private struct CardEditor: View {
    @Binding var card: SensorCard
    var body: some View {
        Form {
            Section("Identity") {
                TextField("Title", text: $card.title)
                HStack {
                    TextField("SF Symbol", text: $card.symbol)
                    Image(systemName: card.symbol).frame(width: 28)
                }
                TextField("Plan / label", text: $card.tag)
            }
            Section("Quota windows") {
                OptionalFieldEditor(title: "5-hour field", field: $card.fiveHour, defaultTitle: "5 hours")
                OptionalFieldEditor(title: "7-day field", field: $card.sevenDay, defaultTitle: "7 days")
            }
            Section("Reset time (optional)") {
                OptionalFieldEditor(title: "Explicit reset binding", field: $card.reset, defaultTitle: "Resets", defaultFormat: .countdown)
                Text("Use an actual reset field: ISO8601, Unix seconds/milliseconds, or text. Never bind last_updated as a quota reset.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Extra fields") {
                ForEach($card.extras) { $field in
                    VStack(alignment: .leading, spacing: 6) {
                        FieldEditor(field: $field)
                        Button("Remove Field", role: .destructive) { card.extras.removeAll { $0.id == field.id } }
                            .font(.caption)
                    }
                }
                Button("Add Extra Field") {
                    card.extras.append(SensorField(title: "Extra", binding: FieldBinding(entityID: "sensor.example")))
                }
            }
        }.formStyle(.grouped)
    }
}

private struct OptionalFieldEditor: View {
    let title: String
    @Binding var field: SensorField?
    let defaultTitle: String
    var defaultFormat: ValueFormat = .automatic
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(title, isOn: Binding(get: { field != nil }, set: { enabled in
                field = enabled ? SensorField(title: defaultTitle, binding: FieldBinding(entityID: "sensor.example"), format: defaultFormat) : nil
            })).toggleStyle(.checkbox)
            if field != nil {
                FieldEditor(field: Binding(get: { field! }, set: { field = $0 }))
            }
        }.padding(.vertical, 4)
    }
}

private struct FieldEditor: View {
    @Binding var field: SensorField
    @State private var path = ""
    @State private var pathError = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Label", text: $field.title)
            TextField("Entity ID", text: $field.binding.entityID, prompt: Text("sensor.example"))
                .font(.system(.caption, design: .monospaced))
            if !EntityID.isValid(field.binding.entityID) {
                Text("Use a valid sensor.* entity ID.").font(.caption2).foregroundStyle(.orange)
            }
            TextField("Value path", text: $path, prompt: Text("state or attributes.quota.remaining"))
                .font(.system(.caption, design: .monospaced))
                .onChange(of: path) { _, newPath in
                    if let parsed = try? ValuePath(newPath) { field.binding.valuePath = parsed; pathError = false }
                    else { pathError = true }
                }
            if pathError { Text("Enter state or attributes.<nested.path>. The last valid path is kept.").font(.caption2).foregroundStyle(.orange) }
            HStack {
                Picker("Format", selection: $field.format) {
                    ForEach(ValueFormat.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                TextField("Unit (auto)", text: Binding(get: { field.unitOverride ?? "" }, set: { field.unitOverride = $0.isEmpty ? nil : $0 }))
                    .frame(width: 110)
            }
            Picker("Percentage means", selection: $field.direction) {
                Text("Remaining").tag(QuotaDirection.remaining)
                Text("Used").tag(QuotaDirection.used)
            }
        }.onAppear { path = field.binding.valuePath.string }
    }
}
