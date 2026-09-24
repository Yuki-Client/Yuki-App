import Foundation
import Security

public actor KeychainStore {
    public static let shared = KeychainStore()
    private let service = "chat.yuki.ios"
    /// Service name used by earlier builds, migrated on first read.
    private let legacyService = "chat.stoat.ios"

    private init() {}

    @discardableResult
    public func save(token: String, for account: String) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { _, new in new }
            return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    public func load(account: String) -> String? {
        if let value = read(service: service, account: account) {
            return value
        }
        if let legacy = read(service: legacyService, account: account) {
            save(token: legacy, for: account)
            delete(service: legacyService, account: account)
            return legacy
        }
        return nil
    }

    public func delete(account: String) {
        delete(service: service, account: account)
        delete(service: legacyService, account: account)
    }

    private func read(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
