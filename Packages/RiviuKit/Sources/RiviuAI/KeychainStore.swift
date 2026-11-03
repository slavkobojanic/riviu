import Foundation
import Security

/// Saves small secrets (API keys) in the user's login keychain.
public struct KeychainStore: Sendable {
    public let service: String

    public init(service: String) {
        self.service = service
    }

    public func string(for account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Saves the value, or deletes it when `value` is nil or empty.
    public func set(_ value: String?, for account: String) throws {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard let value, !value.isEmpty else { return }

        var item = baseQuery(account: account)
        item[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
