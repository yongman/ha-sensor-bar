import XCTest
@testable import HASensorBarCore

final class DraftTokenTests: XCTestCase {
    func testDraftAcceptsOnlyTheNormalizedEndpointWhereItWasEntered() throws {
        let token = try DraftToken(value: " example-test-token \n", server: " HTTPS://EXAMPLE.invalid:443/home/ ")
        XCTAssertEqual(try token.value(for: "https://example.invalid/home"), "example-test-token")
        for changed in ["https://other.example.invalid/home", "http://example.invalid/home",
                        "https://example.invalid:8123/home", "https://example.invalid/other"] {
            XCTAssertThrowsError(try token.value(for: changed)) {
                XCTAssertEqual($0 as? HAClientError, .draftTokenEndpointMismatch)
                XCTAssertFalse($0.localizedDescription.contains("example-test-token"))
            }
        }
    }

    func testDraftCannotBindToAnInvalidURLAndClearingDiscardsTheCredential() throws {
        XCTAssertThrowsError(try DraftToken(value: "example-test-token", server: "invalid"))
        let empty = DraftToken()
        XCTAssertNil(try empty.value(for: "https://other.example.invalid"))
        XCTAssertTrue(empty.value.isEmpty)
        let whitespace = try DraftToken(value: " \n", server: "https://example.invalid")
        XCTAssertNil(try whitespace.value(for: "https://other.example.invalid"))
    }
}
