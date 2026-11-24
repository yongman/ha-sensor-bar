import XCTest
import Network
@testable import HASensorBarCore

/// A real loopback response that keeps sending bytes without completing the resource.
private final class DrippingHTTPServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.hasensorbar.tests.dripping-http")
    private let listener: NWListener
    private var connections: [NWConnection] = []
    private var timers: [DispatchSourceTimer] = []

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    func start() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [self] state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    continuation.resume(returning: "http://127.0.0.1:\(listener.port!.rawValue)")
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [self] connection in
                connections.append(connection)
                connection.start(queue: queue)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [self] _, _, _, error in
                    guard error == nil else { return }
                    let header = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 65536\r\nConnection: close\r\n\r\n["
                    connection.send(content: Data(header.utf8), completion: .contentProcessed { _ in })
                    let timer = DispatchSource.makeTimerSource(queue: queue)
                    timer.schedule(deadline: .now(), repeating: .milliseconds(200))
                    timer.setEventHandler {
                        connection.send(content: Data(" ".utf8), completion: .contentProcessed { _ in })
                    }
                    timers.append(timer)
                    timer.resume()
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        queue.sync {
            timers.forEach { $0.cancel() }
            connections.forEach { $0.cancel() }
            listener.cancel()
            listener.newConnectionHandler = nil
            timers = []
            connections = []
        }
    }
}

final class StreamingTimeoutTests: XCTestCase {
    func testProductionSessionTimesOutEvenWhileBytesKeepArriving() async throws {
        let server = try DrippingHTTPServer()
        defer { server.stop() }
        let endpoint = try await server.start()
        let client = try HomeAssistantClient(baseURL: endpoint, token: "example-test-token",
                                             timeout: 3, allowInsecureHTTP: true)
        let start = Date()
        do {
            _ = try await client.fetchStates()
            XCTFail("A never-ending response must time out.")
        } catch let error as HAClientError {
            XCTAssertEqual(error, .transport)
        }
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 2.5)
        XCTAssertLessThan(Date().timeIntervalSince(start), 6)
    }

    func testCancellationStillInterruptsAnActiveResourceTransfer() async throws {
        let server = try DrippingHTTPServer()
        defer { server.stop() }
        let endpoint = try await server.start()
        let client = try HomeAssistantClient(baseURL: endpoint, token: "example-test-token",
                                             timeout: 15, allowInsecureHTTP: true)
        let operation = Task { try await client.fetchStates() }
        try await Task.sleep(nanoseconds: 300_000_000)
        let start = Date()
        operation.cancel()
        do {
            _ = try await operation.value
            XCTFail("Expected cancellation.")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }
}
