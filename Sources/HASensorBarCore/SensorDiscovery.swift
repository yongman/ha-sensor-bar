import Foundation

public struct CardSuggestion: Identifiable, Equatable, Sendable {
    public var id: UUID { card.id }
    public var group: String
    public var card: SensorCard
    public var entityIDs: [String] { card.fields.map(\.binding.entityID) }
}

public enum SensorDiscovery {
    public static func sensors(in entities: [HAEntity], search: String = "") -> [HAEntity] {
        entities.filter {
            $0.entityID.hasPrefix("sensor.") &&
            (search.isEmpty || $0.entityID.localizedCaseInsensitiveContains(search) ||
             $0.friendlyName.localizedCaseInsensitiveContains(search))
        }.sorted { $0.entityID < $1.entityID }
    }

    public static func suggest(_ entities: [HAEntity]) -> [CardSuggestion] {
        let sensors = sensors(in: entities)
        var cards: [String: SensorCard] = [:]
        var groups: [String: String] = [:]
        var used = Set<String>()
        let regex = try! NSRegularExpression(pattern: #"^(.*)_(5h|7d)_(remaining|quota)(.*)$"#)
        for entity in sensors {
            guard let provider = provider(entity.entityID) else { continue }
            let name = String(entity.entityID.dropFirst("sensor.".count))
            let range = NSRange(name.startIndex..., in: name)
            guard let match = regex.firstMatch(in: name, range: range),
                  let rootRange = Range(match.range(at: 1), in: name),
                  let windowRange = Range(match.range(at: 2), in: name),
                  let suffixRange = Range(match.range(at: 4), in: name),
                  entity.unit == "%" || entity.unit == nil else { continue }
            let root = String(name[rootRange])
            let suffix = String(name[suffixRange])
            let key = root + suffix
            let window = String(name[windowRange])
            var card = cards[key] ?? SensorCard(
                title: title(key, provider: provider),
                symbol: provider == "Codex" ? "terminal" : "sparkles",
                tag: name.hasPrefix("magpie_") ? "" : "Legacy"
            )
            let field = SensorField(title: window == "5h" ? "5 hours" : "7 days",
                                    binding: FieldBinding(entityID: entity.entityID))
            if window == "5h" { card.fiveHour = field } else { card.sevenDay = field }
            cards[key] = card
            groups[key] = provider
            used.insert(entity.entityID)
        }
        for entity in sensors where !used.contains(entity.entityID) {
            guard let provider = provider(entity.entityID) else { continue }
            let name = String(entity.entityID.dropFirst("sensor.".count))
            if let key = cards.keys.sorted(by: { $0.count > $1.count }).first(where: { name.hasPrefix($0 + "_") }) {
                let label = String(name.dropFirst(key.count + 1)).replacingOccurrences(of: "_", with: " ").capitalized
                cards[key]?.extras.append(SensorField(title: label, binding: FieldBinding(entityID: entity.entityID)))
            } else {
                cards[name] = SensorCard(title: entity.friendlyName == entity.entityID
                                        ? title(name, provider: provider) : entity.friendlyName,
                                        symbol: entity.unit == "%" ? "chart.bar" : "circle.grid.2x2",
                                        tag: entity.unit ?? "",
                                        extras: [SensorField(title: "Value", binding: FieldBinding(entityID: entity.entityID))])
                groups[name] = provider
            }
        }
        return cards.keys.sorted {
            if $0.hasPrefix("magpie_") != $1.hasPrefix("magpie_") { return $0.hasPrefix("magpie_") }
            return $0 < $1
        }.compactMap { key in
            cards[key].map { CardSuggestion(group: groups[key] ?? "Sensors", card: $0) }
        }
    }

    private static func provider(_ id: String) -> String? {
        let name = id.replacingOccurrences(of: "sensor.", with: "")
        if name.hasPrefix("magpie_codex_") || name.hasPrefix("codex_") { return "Codex" }
        if name.hasPrefix("magpie_antigravity_") || name.hasPrefix("antigravity_") { return "Antigravity" }
        return nil
    }

    private static func title(_ name: String, provider: String) -> String {
        var text = name
        for prefix in ["magpie_", provider.lowercased() + "_"] {
            if text.hasPrefix(prefix) { text = String(text.dropFirst(prefix.count)) }
        }
        return text.isEmpty || text == provider.lowercased() ? provider : text.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
