import Foundation

public enum ConfigurationError: LocalizedError {
    case invalidURL, invalidPath, invalidEntity, invalidVersion, invalidLayout, invalidInterval
    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Enter an HTTP or HTTPS base URL without credentials, query, or fragment."
        case .invalidPath: return "Use state or attributes.<nested.path>."
        case .invalidEntity: return "Bindings must use a valid sensor entity ID."
        case .invalidVersion: return "This configuration version is not supported."
        case .invalidLayout: return "Group, card, and field identifiers must be unique, and titles cannot be empty."
        case .invalidInterval: return "Refresh must be 15–3600 seconds and timeout must be 3–120 seconds."
        }
    }
}

public enum BaseURL {
    public static func parse(_ input: String) throws -> URL {
        guard let parts = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              let url = parts.url else { throw ConfigurationError.invalidURL }
        return url
    }
}

public enum EntityID {
    public static func isValid(_ value: String) -> Bool {
        value.range(of: #"^sensor\.[a-z0-9_]+$"#, options: .regularExpression) != nil
    }
}

public enum AppTheme: String, Codable, CaseIterable, Sendable { case system, light, dark }
public enum GlassStyle: String, Codable, CaseIterable, Sendable { case clear, balanced, solid }
public enum MenuBarMode: String, Codable, CaseIterable, Sendable { case icon, status, summary }

public struct AppConfiguration: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var baseURL: String = ""
    public var refreshInterval: Double = 60
    public var timeout: Double = 15
    public var groups: [SensorGroup] = []
    public var theme: AppTheme = .system
    public var glassStyle: GlassStyle = .balanced
    public var menuBarMode: MenuBarMode = .summary
    public var primaryCardID: UUID?

    public init() {}
    public var cards: [SensorCard] { groups.flatMap(\.cards) }

    public func validated() throws -> Self {
        guard version == 1 else { throw ConfigurationError.invalidVersion }
        if !baseURL.isEmpty { _ = try BaseURL.parse(baseURL) }
        guard refreshInterval.isFinite, (15...3600).contains(refreshInterval),
              timeout.isFinite, (3...120).contains(timeout) else { throw ConfigurationError.invalidInterval }
        var identifiers = Set<UUID>()
        for group in groups {
            guard identifiers.insert(group.id).inserted, !group.title.trimmingCharacters(in: .whitespaces).isEmpty
            else { throw ConfigurationError.invalidLayout }
            for card in group.cards {
                guard identifiers.insert(card.id).inserted, !card.title.trimmingCharacters(in: .whitespaces).isEmpty
                else { throw ConfigurationError.invalidLayout }
                for field in card.fields {
                    guard identifiers.insert(field.id).inserted, !field.title.trimmingCharacters(in: .whitespaces).isEmpty
                    else { throw ConfigurationError.invalidLayout }
                    guard EntityID.isValid(field.binding.entityID) else { throw ConfigurationError.invalidEntity }
                    _ = try ValuePath(field.binding.valuePath.string)
                }
            }
        }
        var result = self
        if let primary = primaryCardID, !cards.contains(where: { $0.id == primary }) { result.primaryCardID = nil }
        return result
    }
}

public enum ConfigurationCodec {
    public static func export(_ configuration: AppConfiguration) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(configuration.validated())
    }

    public static func importData(_ data: Data) throws -> AppConfiguration {
        try JSONDecoder().decode(AppConfiguration.self, from: data).validated()
    }
}

public struct ConfigurationStore {
    public let url: URL
    public init(url: URL) { self.url = url }

    public static var standard: ConfigurationStore {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ConfigurationStore(url: root.appendingPathComponent("HA Sensor Bar/configuration.json"))
    }

    public func load() throws -> AppConfiguration {
        guard FileManager.default.fileExists(atPath: url.path) else { return AppConfiguration() }
        return try ConfigurationCodec.importData(Data(contentsOf: url))
    }

    public func save(_ configuration: AppConfiguration) throws {
        let data = try ConfigurationCodec.export(configuration)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
