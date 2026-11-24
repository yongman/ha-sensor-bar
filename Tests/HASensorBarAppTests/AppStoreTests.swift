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
    func testTestDiscoverySaveAndPollingRejectHTTPWithoutConsent() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = ConfigurationStore(url: directory.appendingPathComponent("configuration.json"))
        let tokens = MemoryTokens()
        var config = AppConfiguration()
        config.baseURL = " \nHTTP://homeassistant.local:8123/ "
        try persistence.save(config)
        let store = AppStore(persistence: persistence, tokens: tokens)
        defer { store.shutdown() }
        XCTAssertThrowsError(try store.makeClient(configuration: config)) {
            XCTAssertEqual($0 as? HAClientError, .insecureHTTPRequiresConsent)
        }
        XCTAssertThrowsError(try store.save(config)) {
            XCTAssertEqual($0 as? HAClientError, .insecureHTTPRequiresConsent)
        }
        await store.refresh()
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(tokens.reads, 0)
        XCTAssertEqual(tokens.writes, 0)
        XCTAssertFalse(store.isRefreshing)
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
