import XCTest
import HASensorBarCore
@testable import HASensorBarApp

private final class MemoryTokens: TokenStore {
    var values: [String: String] = [:]
    var reads = 0
    var writes = 0
    func read(for server: String) throws -> String? { reads += 1; return values[server] }
    func write(_ token: String, for server: String) throws { writes += 1; values[server] = token }
    func delete(for server: String) throws { values.removeValue(forKey: server) }
}

private actor SuspendedClient: HAClient {
    let began: XCTestExpectation
    let cancelled: XCTestExpectation

    init(began: XCTestExpectation, cancelled: XCTestExpectation) {
        self.began = began
        self.cancelled = cancelled
    }

    func testConnection() async throws {}
    func fetchStates() async throws -> [HAEntity] {
        began.fulfill()
        do { try await Task.sleep(nanoseconds: 60_000_000_000) }
        catch { cancelled.fulfill(); throw error }
        return []
    }
}

final class AppStoreTests: XCTestCase {
    @MainActor
    func testTestDiscoveryAndSaveRejectDraftBoundToAnotherServer() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = ConfigurationStore(url: directory.appendingPathComponent("configuration.json"))
        let tokens = MemoryTokens()
        let store = AppStore(persistence: persistence, tokens: tokens)
        defer { store.shutdown() }
        var config = AppConfiguration()
        config.baseURL = "https://other.example.invalid"
        let draft = try DraftToken(value: "example-test-token", server: "https://example.invalid")
        // Test Connection and Discovery share this guarded client factory.
        XCTAssertThrowsError(try store.makeClient(configuration: config, draftToken: draft)) {
            XCTAssertEqual($0 as? HAClientError, .draftTokenEndpointMismatch)
        }
        XCTAssertThrowsError(try store.save(config, draftToken: draft)) {
            XCTAssertEqual($0 as? HAClientError, .draftTokenEndpointMismatch)
        }
        XCTAssertEqual(tokens.reads, 0)
        XCTAssertEqual(tokens.writes, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: persistence.url.path))
    }

    @MainActor
    func testDisabledHTTPSaveAndPollingNeverAccessCredentialsOrConstructAClient() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = ConfigurationStore(url: directory.appendingPathComponent("configuration.json"))
        let tokens = MemoryTokens()
        var config = AppConfiguration()
        config.baseURL = " \nHTTP://homeassistant.local:8123/ "
        try persistence.save(config)
        var clientCreations = 0
        let store = AppStore(persistence: persistence, tokens: tokens, clientFactory: { _, _ in
            clientCreations += 1
            throw HAClientError.transport
        })
        defer { store.shutdown() }
        XCTAssertThrowsError(try store.makeClient(configuration: config)) {
            XCTAssertEqual($0 as? HAClientError, .insecureHTTPRequiresConsent)
        }
        let draft = try DraftToken(value: "example-unsaved-token", server: config.baseURL)
        try store.save(config, draftToken: draft)
        XCTAssertFalse(try persistence.load().allowsInsecureHTTP)
        await store.refresh()
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(tokens.reads, 0)
        XCTAssertEqual(tokens.writes, 0)
        XCTAssertEqual(clientCreations, 0)
        XCTAssertFalse(store.isRefreshing)
    }

    @MainActor
    func testRevokingSavedHTTPConsentCancelsActivePollingAndPersistsAcrossRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = ConfigurationStore(url: directory.appendingPathComponent("configuration.json"))
        let tokens = MemoryTokens()
        var config = AppConfiguration()
        config.baseURL = "http://homeassistant.local:8123"
        config.insecureHTTPAllowedFor = config.baseURL
        try persistence.save(config)
        tokens.values[config.baseURL] = "example-saved-token"
        let began = expectation(description: "Consented HTTP refresh began")
        let cancelled = expectation(description: "Revocation cancelled the active request")
        let client = SuspendedClient(began: began, cancelled: cancelled)
        var clientCreations = 0
        let store = AppStore(persistence: persistence, tokens: tokens, clientFactory: { _, _ in
            clientCreations += 1
            return client
        })
        defer { store.shutdown() }
        store.start()
        await fulfillment(of: [began], timeout: 2)
        XCTAssertTrue(store.isRefreshing)
        XCTAssertEqual(tokens.reads, 1)
        config.insecureHTTPAllowedFor = nil
        let replacement = try DraftToken(value: "example-replacement", server: config.baseURL)
        try store.save(config, draftToken: replacement)
        XCTAssertFalse(store.configuration.allowsInsecureHTTP)
        XCTAssertFalse(try persistence.load().allowsInsecureHTTP)
        XCTAssertFalse(store.isRefreshing)
        await fulfillment(of: [cancelled], timeout: 2)
        await store.refresh()
        XCTAssertEqual(tokens.reads, 1)
        XCTAssertEqual(tokens.writes, 0)
        XCTAssertEqual(tokens.values[config.baseURL], "example-saved-token")
        XCTAssertEqual(clientCreations, 1)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertNil(store.lastSync)
        let restarted = AppStore(persistence: persistence, tokens: tokens, clientFactory: { _, _ in
            clientCreations += 1
            return client
        })
        defer { restarted.shutdown() }
        restarted.start()
        await restarted.refresh()
        XCTAssertEqual(tokens.reads, 1)
        XCTAssertEqual(clientCreations, 1)
        XCTAssertFalse(restarted.configuration.allowsInsecureHTTP)
    }

    @MainActor
    func testSaveStoresDraftOnlyForItsCanonicalEndpoint() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = ConfigurationStore(url: directory.appendingPathComponent("configuration.json"))
        let tokens = MemoryTokens()
        let store = AppStore(persistence: persistence, tokens: tokens)
        defer { store.shutdown() }
        var config = AppConfiguration()
        config.baseURL = " HTTPS://EXAMPLE.invalid:443/home/ "
        let draft = try DraftToken(value: "example-test-token", server: config.baseURL)
        try store.save(config, draftToken: draft)
        XCTAssertEqual(tokens.values, ["https://example.invalid/home": "example-test-token"])
        XCTAssertEqual(try persistence.load().baseURL, "https://example.invalid/home")
    }
}
