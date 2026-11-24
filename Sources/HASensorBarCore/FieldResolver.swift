import Foundation

public enum DateParser {
    public static func parse(_ value: String) -> Date? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let timestamp = Double(text), timestamp.isFinite {
            let seconds = abs(timestamp) >= 100_000_000_000 ? timestamp / 1000 : timestamp
            guard abs(seconds) <= 253_402_300_799 else { return nil }
            return Date(timeIntervalSince1970: seconds)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

public enum FieldValue: Equatable, Sendable {
    case unavailable
    case percent(Double, QuotaDirection)
    case number(Double, String?)
    case currency(Double, String)
    case text(String)
    case date(Date, countdown: Bool)

    public var remainingFraction: Double? {
        guard case .percent(let value, let direction) = self else { return nil }
        return (direction == .remaining ? value : 100 - value) / 100
    }

    public func display(now: Date = Date()) -> String {
        switch self {
        case .unavailable: return "—"
        case .percent(let value, _): return Self.decimal(value) + "%"
        case .number(let value, let unit):
            return Self.decimal(value) + (unit.map { " " + $0 } ?? "")
        case .currency(let value, let code):
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = code
            return formatter.string(from: NSNumber(value: value)) ?? "\(code) \(Self.decimal(value))"
        case .text(let text): return text
        case .date(let date, let countdown):
            if countdown {
                let seconds = max(0, Int(date.timeIntervalSince(now)))
                if seconds == 0 { return "Due now" }
                if seconds >= 86400 { return "\(seconds / 86400)d \((seconds % 86400) / 3600)h" }
                if seconds >= 3600 { return "\(seconds / 3600)h \((seconds % 3600) / 60)m" }
                return "\(max(1, seconds / 60))m"
            }
            return date.formatted(date: .abbreviated, time: .shortened)
        }
    }

    private static func decimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

public enum FieldResolver {
    public static func resolve(_ field: SensorField, entities: [String: HAEntity]) -> FieldValue {
        guard let entity = entities[field.binding.entityID], !isUnavailable(entity.state) else { return .unavailable }
        let value: JSONValue?
        switch field.binding.valuePath {
        case .state: value = .string(entity.state)
        case .attribute(let path): value = JSONValue.object(entity.attributes).at(path: path)
        }
        guard let raw = value?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !isUnavailable(raw) else { return .unavailable }
        let unit = field.unitOverride.flatMap { $0.isEmpty ? nil : $0 } ?? entity.unit
        var format = field.format
        if format == .automatic {
            if unit == "%" { format = .percent }
            else if ["CNY", "USD", "EUR", "GBP", "JPY"].contains(unit?.uppercased() ?? "") { format = .currency }
            else { format = Double(raw) == nil ? .text : .number }
        }
        switch format {
        case .text: return .text(raw)
        case .date, .countdown:
            return DateParser.parse(raw).map { .date($0, countdown: format == .countdown) } ?? .text(raw)
        default:
            if case .bool? = value { return .unavailable }
            guard let number = Double(raw), number.isFinite else { return .unavailable }
            switch format {
            case .percent:
                guard (0...100).contains(number) else { return .unavailable }
                return .percent(number, field.direction)
            case .currency: return .currency(number, unit?.uppercased() ?? "USD")
            default: return .number(number, unit)
            }
        }
    }

    public static func isUnavailable(_ value: String) -> Bool {
        ["", "unavailable", "unknown", "none", "null"].contains(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}
