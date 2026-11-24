import XCTest
@testable import HASensorBarCore

func fixtureEntities() throws -> [HAEntity] {
    let url = Bundle.module.url(forResource: "sensors", withExtension: "json", subdirectory: "Fixtures")!
    return try JSONDecoder().decode([HAEntity].self, from: Data(contentsOf: url))
}

final class ParsingTests: XCTestCase {
    private func resolve(_ raw: String, unit: String = "%", format: ValueFormat = .automatic,
                         direction: QuotaDirection = .remaining) -> FieldValue {
        let id = "sensor.example"
        let entity = HAEntity(entityID: id, state: raw, attributes: ["unit_of_measurement": .string(unit)])
        return FieldResolver.resolve(SensorField(title: "Quota", binding: FieldBinding(entityID: id),
                                                format: format, direction: direction), entities: [id: entity])
    }

    func testRealisticDecimalPercent() throws {
        let entities = try fixtureEntities()
        let id = entities[0].entityID
        let field = SensorField(title: "5h", binding: FieldBinding(entityID: id))
        let value = FieldResolver.resolve(field, entities: Dictionary(uniqueKeysWithValues: entities.map { ($0.entityID, $0) }))
        XCTAssertEqual(value, .percent(87.86, .remaining))
        XCTAssertEqual(value.remainingFraction!, 0.8786, accuracy: 0.00001)
    }

    func testUnavailableIsNeverZero() {
        for raw in ["unavailable", "unknown", "", " ", "none", "null", "UNKNOWN", "invalid", "NaN", "Infinity", "-1", "101"] {
            XCTAssertEqual(resolve(raw), .unavailable, "Unexpected value for \(raw)")
        }
    }

    func testLegitimateZeroRemainsAvailable() {
        for raw in ["0", "0.0", " 0.00 "] {
            XCTAssertEqual(resolve(raw), .percent(0, .remaining))
            XCTAssertEqual(resolve(raw).remainingFraction, 0)
        }
    }

    func testUsedDirectionComputesRemainingFraction() {
        XCTAssertEqual(resolve("80", direction: .used).remainingFraction!, 0.2, accuracy: 0.0001)
        XCTAssertEqual(resolve("0", direction: .used).remainingFraction, 1)
    }

    func testCurrencyNeverBecomesPercentageBasedOnName() throws {
        let entity = try fixtureEntities().first { $0.entityID == "sensor.codex_balance" }!
        let field = SensorField(title: "Codex", binding: FieldBinding(entityID: entity.entityID))
        let value = FieldResolver.resolve(field, entities: [entity.entityID: entity])
        XCTAssertEqual(value, .currency(123.45, "CNY"))
        XCTAssertNil(value.remainingFraction)
        XCTAssertFalse(value.display().contains("%"))
    }

    func testUSDAndUnitOverride() {
        XCTAssertEqual(resolve("10.5", unit: "USD"), .currency(10.5, "USD"))
        let entity = HAEntity(entityID: "sensor.example", state: "20")
        let field = SensorField(title: "Quota", binding: FieldBinding(entityID: entity.id), unitOverride: "%")
        XCTAssertEqual(FieldResolver.resolve(field, entities: [entity.id: entity]), .percent(20, .remaining))
    }

    func testNestedAttributeAndArrayPaths() throws {
        let entity = try fixtureEntities()[0]
        var field = SensorField(title: "Weekly", binding: FieldBinding(entityID: entity.id, valuePath: .attribute("windows.weekly.remaining")))
        XCTAssertEqual(FieldResolver.resolve(field, entities: [entity.id: entity]), .percent(45.5, .remaining))
        field.binding.valuePath = .attribute("models.0.remaining")
        XCTAssertEqual(FieldResolver.resolve(field, entities: [entity.id: entity]), .percent(23.5, .remaining))
        field.binding.valuePath = .attribute("models.99.remaining")
        XCTAssertEqual(FieldResolver.resolve(field, entities: [entity.id: entity]), .unavailable)
        field.binding.valuePath = .attribute("missing.path")
        XCTAssertEqual(FieldResolver.resolve(field, entities: [entity.id: entity]), .unavailable)
    }

    func testMissingEntityAndNullAttribute() {
        let field = SensorField(title: "Value", binding: FieldBinding(entityID: "sensor.missing"))
        XCTAssertEqual(FieldResolver.resolve(field, entities: [:]), .unavailable)
        let entity = HAEntity(entityID: "sensor.example", state: "ok", attributes: ["value": .null])
        let nested = SensorField(title: "Value", binding: FieldBinding(entityID: entity.id, valuePath: .attribute("value")))
        XCTAssertEqual(FieldResolver.resolve(nested, entities: [entity.id: entity]), .unavailable)
    }

    func testNoUnitMeansNumberRatherThanInferredPercent() {
        XCTAssertEqual(resolve("87.86", unit: ""), .number(87.86, ""))
        XCTAssertNil(resolve("87.86", unit: "").remainingFraction)
    }

    func testTextAndBooleanAttributes() {
        XCTAssertEqual(resolve("Ready", unit: ""), .text("Ready"))
        let entity = HAEntity(entityID: "sensor.example", state: "ok", attributes: ["healthy": .bool(true)])
        var field = SensorField(title: "Healthy", binding: FieldBinding(entityID: entity.id, valuePath: .attribute("healthy")), format: .text)
        XCTAssertEqual(FieldResolver.resolve(field, entities: [entity.id: entity]), .text("true"))
        field.format = .percent
        XCTAssertEqual(FieldResolver.resolve(field, entities: [entity.id: entity]), .unavailable)
    }

    func testISO8601FractionalSecondsAndTimezone() throws {
        let entity = try fixtureEntities()[0]
        XCTAssertNotNil(entity.updatedDate)
        let whole = try XCTUnwrap(DateParser.parse("2026-02-18T06:30:00Z"))
        XCTAssertEqual(entity.updatedDate!.timeIntervalSince(whole), 0.654321, accuracy: 0.001)
        XCTAssertNotNil(DateParser.parse("2026-02-18T14:30:00+08:00"))
    }

    func testUnixSecondsMillisecondsAndTextFallback() {
        XCTAssertEqual(DateParser.parse("1770000000"), DateParser.parse("1770000000000"))
        XCTAssertNil(DateParser.parse("tomorrow"))
        XCTAssertNil(DateParser.parse("Infinity"))
        XCTAssertNil(DateParser.parse("1e99"))
        XCTAssertEqual(resolve("After maintenance", unit: "", format: .countdown), .text("After maintenance"))
    }

    func testExplicitResetAndNoInferredReset() throws {
        let entity = try fixtureEntities()[0]
        let card = SensorCard(title: "Account")
        XCTAssertNil(card.reset)
        let field = SensorField(title: "Resets", binding: FieldBinding(entityID: entity.id, valuePath: .attribute("windows.weekly.reset_at")), format: .date)
        guard case .date(let date, false) = FieldResolver.resolve(field, entities: [entity.id: entity]) else {
            return XCTFail("Expected an explicit reset date")
        }
        XCTAssertNotEqual(date, entity.updatedDate)
    }

    func testCountdownFormatting() {
        let now = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(FieldValue.date(now.addingTimeInterval(90061), countdown: true).display(now: now), "1d 1h")
        XCTAssertEqual(FieldValue.date(now.addingTimeInterval(3660), countdown: true).display(now: now), "1h 1m")
        XCTAssertEqual(FieldValue.date(now.addingTimeInterval(-10), countdown: true).display(now: now), "Due now")
    }

    func testValuePathCodingAndValidation() throws {
        for string in ["state", "attributes.a.b", "attributes.list.0.value"] {
            let path = try ValuePath(string)
            XCTAssertEqual(try JSONDecoder().decode(ValuePath.self, from: JSONEncoder().encode(path)), path)
        }
        for invalid in ["", "last_updated", "attributes.", "attributes..x", "attributes.x."] {
            XCTAssertThrowsError(try ValuePath(invalid))
        }
    }

    func testJSONValueRoundTrip() throws {
        let value = JSONValue.object(["a": .array([.null, .bool(false), .number(1.5), .string("x")])])
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value)), value)
    }
}
