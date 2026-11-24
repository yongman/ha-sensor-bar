import Foundation

public enum DemoData {
    public static var configuration: AppConfiguration {
        var configuration = AppConfiguration()
        func field(_ name: String, _ id: String, format: ValueFormat = .automatic) -> SensorField {
            SensorField(title: name, binding: FieldBinding(entityID: "sensor.demo_" + id), format: format)
        }
        configuration.groups = [
            SensorGroup(title: "Codex", cards: [
                SensorCard(title: "Personal workspace", symbol: "terminal", tag: "Pro",
                           fiveHour: field("5 hours", "codex_5h"), sevenDay: field("7 days", "codex_7d"),
                           extras: [field("Images", "images"), field("Balance", "balance")]),
                SensorCard(title: "Team workspace", symbol: "person.2", tag: "Team",
                           fiveHour: field("5 hours", "team_5h"), sevenDay: field("7 days", "team_7d"))
            ]),
            SensorGroup(title: "Antigravity", cards: [
                SensorCard(title: "Gemini · Studio", symbol: "sparkles", tag: "Ultra",
                           fiveHour: field("5 hours", "gemini_5h"), sevenDay: field("7 days", "gemini_7d"),
                           extras: [field("Status", "status")]),
                SensorCard(title: "Argon", symbol: "moon.stars", tag: "Weekly",
                           sevenDay: field("7 days", "argon_7d"))
            ])
        ]
        return configuration
    }

    public static var entities: [HAEntity] {
        let values: [(String, String, String?)] = [
            ("codex_5h", "87.86", "%"), ("codex_7d", "63.2", "%"), ("images", "94", "%"),
            ("balance", "128.50", "CNY"), ("team_5h", "42", "%"), ("team_7d", "18.4", "%"),
            ("gemini_5h", "76", "%"), ("gemini_7d", "unavailable", "%"),
            ("status", "All systems ready", nil), ("argon_7d", "91", "%")
        ]
        return values.map { id, state, unit in
            HAEntity(entityID: "sensor.demo_" + id, state: state,
                     attributes: unit.map { ["unit_of_measurement": .string($0)] } ?? [:],
                     lastUpdated: "2026-01-15T10:30:00.123456+00:00")
        }
    }
}
