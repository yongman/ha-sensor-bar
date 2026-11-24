import XCTest
@testable import HASensorBarCore

final class SchedulerKeychainTests: XCTestCase {
    @MainActor
    func testStopCancelsInFlightRefresh() async {
        let scheduler = RefreshScheduler()
        let began = expectation(description: "Refresh began")
        let cancelled = expectation(description: "Refresh cancelled")
        scheduler.start(interval: 60) {
            began.fulfill()
            do { try await Task.sleep(nanoseconds: 10_000_000_000) }
            catch { cancelled.fulfill() }
        }
        await fulfillment(of: [began], timeout: 2)
        scheduler.stop()
        await fulfillment(of: [cancelled], timeout: 2)
    }

    @MainActor
    func testRestartCancelsOldLoopAndRunsNewOperation() async {
        let scheduler = RefreshScheduler()
        let old = expectation(description: "Old operation")
        let cancelled = expectation(description: "Old operation cancelled")
        let new = expectation(description: "New operation")
        scheduler.start(interval: 60) {
            old.fulfill()
            do { try await Task.sleep(nanoseconds: 10_000_000_000) }
            catch { cancelled.fulfill() }
        }
        await fulfillment(of: [old], timeout: 2)
        scheduler.start(interval: 60) { new.fulfill() }
        await fulfillment(of: [cancelled, new], timeout: 2)
        scheduler.stop()
    }

    #if canImport(Security)
    func testKeychainWriteReplaceReadDeleteAndServerIsolation() throws {
        let store = KeychainTokenStore(service: "com.hasensorbar.tests." + UUID().uuidString)
        let server = "http://homeassistant.local:8123"
        let other = "https://other.example.invalid"
        defer { try? store.delete(for: server); try? store.delete(for: other) }
        XCTAssertNil(try store.read(for: server))
        try store.write("example-only-not-a-real-secret", for: server)
        XCTAssertEqual(try store.read(for: server + "/"), "example-only-not-a-real-secret")
        XCTAssertNil(try store.read(for: other))
        try store.write("example-replacement", for: server)
        XCTAssertEqual(try store.read(for: server), "example-replacement")
        try store.delete(for: server)
        XCTAssertNil(try store.read(for: server))
        try store.delete(for: server)
    }
    #endif
}
