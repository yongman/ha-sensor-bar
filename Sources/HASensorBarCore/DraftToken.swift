import Foundation

/// A transient credential bound to the validated endpoint where it was entered.
public struct DraftToken: Sendable {
    public let value: String
    private let endpoint: URL?

    public init() {
        value = ""
        endpoint = nil
    }

    public init(value: String, server: String) throws {
        self.value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        endpoint = try BaseURL.parse(server)
    }

    /// Used at both the request and persistence boundaries, even if the UI missed a change.
    public func value(for server: String) throws -> String? {
        guard !value.isEmpty else { return nil }
        guard try BaseURL.parse(server) == endpoint else { throw HAClientError.draftTokenEndpointMismatch }
        return value
    }
}
