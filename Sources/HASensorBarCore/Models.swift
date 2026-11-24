import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool)
    case object([String: JSONValue]), array([JSONValue]), null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public var text: String? {
        switch self {
        case .string(let value): return value
        case .number(let value): return String(value)
        case .bool(let value): return value ? "true" : "false"
        default: return nil
        }
    }

    public func at(path: String) -> JSONValue? {
        var current = self
        for part in path.split(separator: ".", omittingEmptySubsequences: false) {
            switch current {
            case .object(let object):
                guard let next = object[String(part)] else { return nil }
                current = next
            case .array(let array):
                guard let index = Int(part), array.indices.contains(index) else { return nil }
                current = array[index]
            default: return nil
            }
        }
        return current
    }
}

public struct HAEntity: Codable, Equatable, Sendable, Identifiable {
    public var entityID: String
    public var state: String
    public var attributes: [String: JSONValue]
    public var lastChanged: String?
    public var lastUpdated: String?
    public var id: String { entityID }
    public var friendlyName: String { attributes["friendly_name"]?.text ?? entityID }
    public var unit: String? { attributes["unit_of_measurement"]?.text }
    public var updatedDate: Date? { lastUpdated.flatMap(DateParser.parse) }

    enum CodingKeys: String, CodingKey {
        case entityID = "entity_id", state, attributes
        case lastChanged = "last_changed", lastUpdated = "last_updated"
    }

    public init(entityID: String, state: String, attributes: [String: JSONValue] = [:],
                lastChanged: String? = nil, lastUpdated: String? = nil) {
        self.entityID = entityID
        self.state = state
        self.attributes = attributes
        self.lastChanged = lastChanged
        self.lastUpdated = lastUpdated
    }
}

public enum ValuePath: Hashable, Sendable, Codable {
    case state
    case attribute(String)

    public var string: String {
        switch self {
        case .state: return "state"
        case .attribute(let path): return "attributes." + path
        }
    }

    public init(_ string: String) throws {
        if string == "state" { self = .state; return }
        guard string.hasPrefix("attributes.") else { throw ConfigurationError.invalidPath }
        let path = String(string.dropFirst("attributes.".count))
        guard !path.isEmpty, !path.split(separator: ".", omittingEmptySubsequences: false).contains("")
        else { throw ConfigurationError.invalidPath }
        self = .attribute(path)
    }

    public init(from decoder: Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(string)
    }
}

public struct FieldBinding: Codable, Hashable, Sendable {
    public var entityID: String
    public var valuePath: ValuePath
    public init(entityID: String, valuePath: ValuePath = .state) {
        self.entityID = entityID
        self.valuePath = valuePath
    }
}

public enum ValueFormat: String, Codable, CaseIterable, Sendable {
    case automatic, percent, number, currency, text, date, countdown
}

public enum QuotaDirection: String, Codable, CaseIterable, Sendable {
    case remaining, used
}

public struct SensorField: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var binding: FieldBinding
    public var format: ValueFormat
    public var unitOverride: String?
    public var direction: QuotaDirection

    public init(id: UUID = UUID(), title: String, binding: FieldBinding,
                format: ValueFormat = .automatic, unitOverride: String? = nil,
                direction: QuotaDirection = .remaining) {
        self.id = id
        self.title = title
        self.binding = binding
        self.format = format
        self.unitOverride = unitOverride
        self.direction = direction
    }
}

public struct SensorCard: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var symbol: String
    public var tag: String
    public var fiveHour: SensorField?
    public var sevenDay: SensorField?
    public var reset: SensorField?
    public var extras: [SensorField]

    public init(id: UUID = UUID(), title: String, symbol: String = "sparkles", tag: String = "",
                fiveHour: SensorField? = nil, sevenDay: SensorField? = nil,
                reset: SensorField? = nil, extras: [SensorField] = []) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.tag = tag
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.reset = reset
        self.extras = extras
    }

    public var fields: [SensorField] { [fiveHour, sevenDay, reset].compactMap { $0 } + extras }
}

public struct SensorGroup: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var collapsed: Bool
    public var cards: [SensorCard]

    public init(id: UUID = UUID(), title: String, collapsed: Bool = false, cards: [SensorCard] = []) {
        self.id = id
        self.title = title
        self.collapsed = collapsed
        self.cards = cards
    }
}
