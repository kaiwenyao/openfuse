import Foundation
import Security

public enum CredentialStoreError: LocalizedError {
    case keychain(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .keychain(let status):
            return "Keychain 错误 \(status)"
        }
    }
}

/// Generic-password storage for source credentials. Passwords never enter
/// sources.json, logs or test reports.
public enum CredentialStore {
    public static let service = "com.openfuse.webdav"

    public static func save(password: String, account: String, service: String = service) throws {
        let data = Data(password.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            throw CredentialStoreError.keychain(updateStatus)
        }
        var insert = query
        insert.merge(attributes) { _, new in new }
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CredentialStoreError.keychain(status)
        }
    }

    public static func load(account: String, service: String = service) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func delete(account: String, service: String = service) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
