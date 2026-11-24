import AppKit
import Combine
import SwiftUI
import HASensorBarCore

@MainActor
final class AppStore: ObservableObject {
    @Published var configuration = AppConfiguration()
    @Published private(set) var entities: [String: HAEntity] = [:]
    @Published private(set) var lastSync: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isDemo = false
    @Published var pinned = false
    @Published var notice: String?
    private let persistence: ConfigurationStore
    private let tokens: any TokenStore
    private let scheduler = RefreshScheduler()
    private var refreshTask: Task<Void, Never>?
    private var generation = UUID()
    private var demoConfiguration = DemoData.configuration
    var openSettings: () -> Void = {}

    init(persistence: ConfigurationStore = .standard, tokens: any TokenStore = KeychainTokenStore()) {
        self.persistence = persistence
        self.tokens = tokens
        do { configuration = try persistence.load() }
        catch { errorMessage = "Configuration could not be loaded. Import a valid backup in Settings." }
    }

    var displayedConfiguration: AppConfiguration { isDemo ? demoConfiguration : configuration }
    var hasConnection: Bool { !configuration.baseURL.isEmpty }

    func start() {
        scheduler.start(interval: configuration.refreshInterval) { [weak self] in await self?.refresh() }
    }

    func shutdown() {
        scheduler.stop()
        refreshTask?.cancel()
    }

    func save(_ candidate: AppConfiguration, token: String? = nil) throws {
        let next = try candidate.validated()
        if let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try tokens.write(token.trimmingCharacters(in: .whitespacesAndNewlines), for: next.baseURL)
        }
        try persistence.save(next)
        generation = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
        let connectionChanged = configuration.baseURL != next.baseURL
        configuration = next
        if connectionChanged { entities = [:]; lastSync = nil }
        errorMessage = nil
        isDemo = false
        start()
    }

    func persistLayout() {
        if isDemo { return }
        do { try persistence.save(configuration) }
        catch { notice = "The layout could not be saved." }
    }

    func toggleGroup(_ id: UUID) {
        if isDemo {
            if let index = demoConfiguration.groups.firstIndex(where: { $0.id == id }) {
                demoConfiguration.groups[index].collapsed.toggle()
                objectWillChange.send()
            }
        } else if let index = configuration.groups.firstIndex(where: { $0.id == id }) {
            configuration.groups[index].collapsed.toggle()
            persistLayout()
        }
    }

    func moveGroup(_ dragged: String, before target: UUID) {
        guard !isDemo, let source = configuration.groups.firstIndex(where: { $0.id.uuidString == dragged }),
              let destination = configuration.groups.firstIndex(where: { $0.id == target }), source != destination else { return }
        configuration.groups.move(fromOffsets: IndexSet(integer: source), toOffset: destination > source ? destination + 1 : destination)
        persistLayout()
    }

    func showDemo() {
        scheduler.stop()
        refreshTask?.cancel()
        refreshTask = nil
        generation = UUID()
        isRefreshing = false
        errorMessage = nil
        isDemo = true
        entities = Dictionary(uniqueKeysWithValues: DemoData.entities.map { ($0.entityID, $0) })
        lastSync = Date()
    }

    func leaveDemo() {
        isDemo = false
        entities = [:]
        lastSync = nil
        start()
    }

    func makeClient(configuration: AppConfiguration, draftToken: String? = nil) throws -> HomeAssistantClient {
        let saved = try tokens.read(for: configuration.baseURL)
        let token = draftToken.flatMap { $0.isEmpty ? nil : $0 } ?? saved ?? ""
        return try HomeAssistantClient(baseURL: configuration.baseURL, token: token, timeout: configuration.timeout)
    }

    func hasSavedToken(for server: String) -> Bool { (try? tokens.read(for: server)) != nil }

    func removeToken(for server: String) throws {
        try tokens.delete(for: server)
        generation = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
        entities = [:]
        lastSync = nil
        errorMessage = "Access token removed. Add a token in Settings to reconnect."
    }

    func refresh() async {
        guard !isDemo, hasConnection else { return }
        if let refreshTask { await refreshTask.value; return }
        let currentGeneration = generation
        isRefreshing = true
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let client = try makeClient(configuration: configuration)
                let result = try await client.fetchStates()
                try Task.checkCancellation()
                guard currentGeneration == generation else { return }
                entities = Dictionary(result.map { ($0.entityID, $0) }, uniquingKeysWith: { _, new in new })
                lastSync = Date()
                errorMessage = nil
            } catch is CancellationError {
                // A newer configuration or shutdown owns the next result.
            } catch {
                guard currentGeneration == generation else { return }
                errorMessage = error.localizedDescription
            }
            if currentGeneration == generation {
                isRefreshing = false
                refreshTask = nil
            }
        }
        refreshTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    var menuSummary: String {
        let config = displayedConfiguration
        let card = config.cards.first(where: { $0.id == configuration.primaryCardID }) ?? config.cards.first
        let fractions = [card?.fiveHour, card?.sevenDay].compactMap { $0 }
            .compactMap { FieldResolver.resolve($0, entities: entities).remainingFraction }
        guard let lowest = fractions.min() else { return "—" }
        return "\(Int((lowest * 100).rounded()))%"
    }

    var latestHAUpdate: Date? {
        let ids = Set(displayedConfiguration.cards.flatMap(\.fields).map(\.binding.entityID))
        return ids.compactMap { entities[$0]?.updatedDate }.max()
    }
}
