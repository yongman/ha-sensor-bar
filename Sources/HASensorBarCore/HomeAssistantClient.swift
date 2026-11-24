import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum HAClientError: LocalizedError, Equatable {
    case unauthorized, invalidResponse, http(Int), decoding, missingToken, transport
    public var errorDescription: String? {
        switch self {
        case .unauthorized: return "Authentication failed. Check the access token in Settings."
        case .invalidResponse: return "Home Assistant returned an unexpected response."
        case .http(let status): return "Home Assistant returned HTTP \(status)."
        case .decoding: return "The server did not return valid Home Assistant sensor data."
        case .missingToken: return "Add a Long-Lived Access Token in Settings."
        case .transport: return "Home Assistant is unreachable. Check the connection and try again."
        }
    }
}

public protocol HAClient: Sendable {
    func testConnection() async throws
    func fetchStates() async throws -> [HAEntity]
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public actor HomeAssistantClient: HAClient {
    private let baseURL: URL
    private let token: String
    private let timeout: TimeInterval
    private let session: URLSession
    private let ownsSession: Bool

    public init(baseURL: String, token: String, timeout: TimeInterval = 15, session: URLSession? = nil) throws {
        self.baseURL = try BaseURL.parse(baseURL)
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw HAClientError.missingToken }
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        self.timeout = timeout
        self.ownsSession = session == nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = session ?? URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }

    deinit { if ownsSession { session.invalidateAndCancel() } }

    public func testConnection() async throws { _ = try await request(path: "api/") }

    public func fetchStates() async throws -> [HAEntity] {
        let data = try await request(path: "api/states")
        do { return try JSONDecoder().decode([HAEntity].self, from: data) }
        catch { throw HAClientError.decoding }
    }

    public func fetchState(entityID: String) async throws -> HAEntity {
        guard EntityID.isValid(entityID) else { throw ConfigurationError.invalidEntity }
        let data = try await request(path: "api/states/" + entityID)
        do { return try JSONDecoder().decode(HAEntity.self, from: data) }
        catch { throw HAClientError.decoding }
    }

    private func request(path: String) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.timeoutInterval = timeout
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch { throw HAClientError.transport }
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw HAClientError.invalidResponse }
        if [401, 403].contains(response.statusCode) { throw HAClientError.unauthorized }
        guard (200...299).contains(response.statusCode) else { throw HAClientError.http(response.statusCode) }
        return data
    }
}
