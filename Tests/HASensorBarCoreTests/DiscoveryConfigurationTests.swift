import XCTest
@testable import HASensorBarCore

final class DiscoveryConfigurationTests: XCTestCase {
    func testDiscoveryFiltersSensorsAndSupportsSearch() throws {
        let entities = try fixtureEntities()
        XCTAssertEqual(SensorDiscovery.sensors(in: entities).count, entities.count - 1)
        XCTAssertEqual(SensorDiscovery.sensors(in: entities, search: "Account A 5h").count, 1)
        XCTAssertEqual(SensorDiscovery.sensors(in: entities, search: "argon").count, 1)
    }

    func testDiscoveryPairsIndependentWindowEntitiesAndExtra() throws {
        let suggestions = SensorDiscovery.suggest(try fixtureEntities())
        let codex = try XCTUnwrap(suggestions.first { $0.card.fiveHour?.binding.entityID == "sensor.magpie_codex_account_a_5h_remaining" })
        XCTAssertEqual(codex.group, "Codex")
        XCTAssertEqual(codex.card.sevenDay?.binding.entityID, "sensor.magpie_codex_account_a_7d_remaining")
        XCTAssertEqual(codex.card.extras.count, 1)
        XCTAssertEqual(codex.card.extras.first?.binding.entityID, "sensor.magpie_codex_account_a_image_generation_remaining")
        XCTAssertNil(codex.card.reset)
    }

    func testDiscoverySupportsWeeklyOnlyAndLegacySeparately() throws {
        let suggestions = SensorDiscovery.suggest(try fixtureEntities())
        let weekly = try XCTUnwrap(suggestions.first { $0.card.sevenDay?.binding.entityID.contains("argon") == true })
        XCTAssertNil(weekly.card.fiveHour)
        let legacy = try XCTUnwrap(suggestions.first { $0.card.fiveHour?.binding.entityID == "sensor.codex_5h_quota" })
        XCTAssertEqual(legacy.card.sevenDay?.binding.entityID, "sensor.codex_7d_quota")
        XCTAssertEqual(legacy.card.tag, "Legacy")
        XCTAssertTrue(suggestions.first!.entityIDs.first!.hasPrefix("sensor.magpie_"))
        XCTAssertTrue(suggestions.contains { $0.card.sevenDay?.binding.entityID == "sensor.codex_7d_quota_pro" })
    }

    func testDiscoveryCurrencyIsNotQuotaWindow() {
        let entity = HAEntity(entityID: "sensor.codex_5h_quota", state: "12.5", attributes: ["unit_of_measurement": .string("CNY")])
        let result = SensorDiscovery.suggest([entity])
        XCTAssertEqual(result.count, 1)
        XCTAssertNil(result[0].card.fiveHour)
        XCTAssertEqual(result[0].card.extras.count, 1)
    }

    func testConfigurationRoundTripContainsNoTokenProperty() throws {
        let configuration = DemoData.configuration
        let data = try ConfigurationCodec.export(configuration)
        XCTAssertEqual(try ConfigurationCodec.importData(data), configuration)
        let json = String(decoding: data, as: UTF8.self).lowercased()
        for secretKey in ["token", "password", "authorization", "bearer"] { XCTAssertFalse(json.contains(secretKey)) }
    }

    func testImportDropsUnknownCredentialsOnReexport() throws {
        let data = try ConfigurationCodec.export(DemoData.configuration)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["token"] = "example-secret-not-a-real-token"
        object["password"] = "example-password"
        let imported = try ConfigurationCodec.importData(JSONSerialization.data(withJSONObject: object))
        let exported = String(decoding: try ConfigurationCodec.export(imported), as: UTF8.self)
        XCTAssertFalse(exported.contains("example-secret"))
        XCTAssertFalse(exported.contains("password"))
    }

    func testCredentialURLCannotLeakIntoExport() throws {
        var config = AppConfiguration()
        for url in ["http://user:password@homeassistant.local", "https://example.invalid/?token=secret",
                    "https://example.invalid/#secret", "file:///secret", "ftp://example.invalid"] {
            config.baseURL = url
            XCTAssertThrowsError(try ConfigurationCodec.export(config))
        }
    }

    func testURLValidationAcceptsHTTPHTTPSAndProxyPath() throws {
        for url in ["http://homeassistant.local:8123", "https://example.invalid/ha", "http://[::1]:8123"] {
            XCTAssertNotNil(try BaseURL.parse(url))
        }
        for url in ["", "homeassistant.local", "http://", "https://user@example.invalid"] {
            XCTAssertThrowsError(try BaseURL.parse(url))
        }
    }

    func testValidationRejectsInvalidVersionIDsIntervalsAndBindings() throws {
        var config = AppConfiguration()
        config.version = 2
        XCTAssertThrowsError(try config.validated())
        config = DemoData.configuration
        config.groups.append(config.groups[0])
        XCTAssertThrowsError(try config.validated())
        config = AppConfiguration()
        config.refreshInterval = 0
        XCTAssertThrowsError(try config.validated())
        config.refreshInterval = 60
        config.timeout = 500
        XCTAssertThrowsError(try config.validated())
        config = DemoData.configuration
        config.groups[0].cards[0].fiveHour?.binding.entityID = "sensor.bad/../../path"
        XCTAssertThrowsError(try config.validated())
    }

    func testConfigurationPersistenceAndCorruptFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(url: directory.appendingPathComponent("configuration.json"))
        XCTAssertEqual(try store.load(), AppConfiguration())
        let configuration = DemoData.configuration
        try store.save(configuration)
        XCTAssertEqual(try store.load(), configuration)
        try Data("invalid".utf8).write(to: store.url)
        XCTAssertThrowsError(try store.load())
    }

    func testDeletedPrimaryCardFallsBackToFirst() throws {
        var config = AppConfiguration()
        config.primaryCardID = UUID()
        XCTAssertNil(try config.validated().primaryCardID)
    }
}
