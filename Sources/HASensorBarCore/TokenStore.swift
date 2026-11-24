import Foundation
#if canImport(Security)
import Security
#endif

public protocol TokenStore {
    func read(for server: String) throws -> String?
    func write(_ token: String, for server: String) throws
    func delete(for server: String) throws
}

#if canImport(Security)
public struct KeychainError: LocalizedError {
    public let status: OSStatus
    public var errorDescription: String? { "Keychain access failed (status \(status))." }
}

public struct KeychainTokenStore: TokenStore {
    private let service: String
    public init(service: String = "com.hasensorbar.app.homeassistant") { self.service = service }

    private func query(for server: String) throws -> [String: Any] {
        let normalized = try BaseURL.parse(server).absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: normalized
        ]
    }

    public func read(for server: String) throws -> String? {
        var query = try query(for: server)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func write(_ token: String, for server: String) throws {
        let query = try query(for: server)
        let attributes = [kSecValueData as String: Data(token.utf8)]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = Data(token.utf8)
            item[kSecAttrSynchronizable as String] = false
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public func delete(for server: String) throws {
        let status = SecItemDelete(try query(for: server) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}
#endif
