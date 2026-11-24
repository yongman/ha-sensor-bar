import XCTest
import Foundation
@testable import HASensorBarCore

private final class MockURLProtocol: URLProtocol {
    static let lock = NSLock()
    private static var responses: [String: (Int, Data)] = [:]
    private static var requests: [URLRequest] = []

    static func prepare(path: String, status: Int = 200, data: Data = Data()) {
        lock.lock()
        defer { lock.unlock() }
        responses[path] = (status, data)
        requests = []
    }

    static var lastRequest: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return requests.last
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let (status, data) = Self.responses[request.url!.path] ?? (404, Data())
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class ClientTests: XCTestCase {
    private func client(baseURL: String = "http://homeassistant.local:8123") throws -> HomeAssistantClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return try HomeAssistantClient(baseURL: baseURL, token: "example-test-token", timeout: 7,
                                       allowInsecureHTTP: true,
                                       session: URLSession(configuration: configuration))
    }

    func testBearerRequestAndDecoding() async throws {
        let entities = try fixtureEntities()
        MockURLProtocol.prepare(path: "/api/states", data: try JSONEncoder().encode(entities))
        let result = try await client().fetchStates()
        XCTAssertEqual(result, entities)
        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer example-test-token")
        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(MockURLProtocol.lastRequest?.timeoutInterval, 7)
        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.scheme, "http")
    }

    func testConnectionAndReverseProxyPath() async throws {
        MockURLProtocol.prepare(path: "/home/api", data: Data(#"{"message":"API running."}"#.utf8))
        try await client(baseURL: "https://example.invalid/home").testConnection()
        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.absoluteString, "https://example.invalid/home/api/")
    }

    func testConnectionRejectsHTMLMissingEmptyAndNonStringMessages() async throws {
        for body in ["<html>Sign in</html>", "{}", #"{"message":null}"#, #"{"message":42}"#,
                     #"{"message":""}"#, #"{"message":" \n "}"#, "[]", "null"] {
            MockURLProtocol.prepare(path: "/api", data: Data(body.utf8))
            do { try await client().testConnection(); XCTFail("Expected invalid API response") }
            catch let error as HAClientError { XCTAssertEqual(error, .invalidResponse) }
        }
    }

    func testProductionSessionBoundsRequestAndTotalResourceTime() throws {
        for timeout in [3.0, 7, 120] {
            let configuration = try HomeAssistantClient.sessionConfiguration(timeout: timeout)
            XCTAssertEqual(configuration.timeoutIntervalForRequest, timeout)
            XCTAssertEqual(configuration.timeoutIntervalForResource, timeout)
            XCTAssertNil(configuration.urlCache)
            XCTAssertNil(configuration.httpCookieStorage)
            XCTAssertNil(configuration.urlCredentialStorage)
        }
        for timeout in [0.0, 2.9, 121, .infinity, .nan] {
            XCTAssertThrowsError(try HomeAssistantClient(baseURL: "https://example.invalid",
                                                        token: "example", timeout: timeout))
        }
    }

    func testHTTPRequiresExplicitConsentAfterURLNormalization() throws {
        for endpoint in ["http://homeassistant.local:8123", " \nHTTP://homeassistant.local:8123/ "] {
            XCTAssertThrowsError(try HomeAssistantClient(baseURL: endpoint, token: "example")) {
                XCTAssertEqual($0 as? HAClientError, .insecureHTTPRequiresConsent)
            }
            XCTAssertNoThrow(try HomeAssistantClient(baseURL: endpoint, token: "example", allowInsecureHTTP: true))
        }
        XCTAssertNoThrow(try HomeAssistantClient(baseURL: "https://example.invalid", token: "example"))
    }

    func testSingleEntityEndpoint() async throws {
        let entity = try fixtureEntities()[0]
        MockURLProtocol.prepare(path: "/api/states/" + entity.id, data: try JSONEncoder().encode(entity))
        let result = try await client().fetchState(entityID: entity.id)
        XCTAssertEqual(result, entity)
    }

    func testAuthenticationErrorsAreSpecificAndSanitized() async throws {
        for status in [401, 403] {
            MockURLProtocol.prepare(path: "/api/states", status: status, data: Data("private response".utf8))
            do {
                _ = try await client().fetchStates()
                XCTFail("Expected authorization failure")
            } catch let error as HAClientError {
                XCTAssertEqual(error, .unauthorized)
                XCTAssertFalse(error.localizedDescription.contains("private response"))
                XCTAssertFalse(error.localizedDescription.contains("example-test-token"))
            }
        }
    }

    func testHTTPFailureAndMalformedData() async throws {
        for status in [302, 404, 500] {
            MockURLProtocol.prepare(path: "/api/states", status: status)
            do { _ = try await client().fetchStates(); XCTFail("Expected HTTP failure") }
            catch let error as HAClientError { XCTAssertEqual(error, .http(status)) }
        }
        MockURLProtocol.prepare(path: "/api/states", data: Data("not json".utf8))
        do { _ = try await client().fetchStates(); XCTFail("Expected decoding failure") }
        catch let error as HAClientError { XCTAssertEqual(error, .decoding) }
    }

    func testInvalidConfigurationAndEntityCannotSendRequest() async throws {
        XCTAssertThrowsError(try HomeAssistantClient(baseURL: "file:///tmp", token: "example"))
        XCTAssertThrowsError(try HomeAssistantClient(baseURL: "https://example.invalid", token: " "))
        let client = try client()
        do { _ = try await client.fetchState(entityID: "../../other"); XCTFail("Expected entity validation") }
        catch { XCTAssertTrue(error is ConfigurationError) }
    }
}
