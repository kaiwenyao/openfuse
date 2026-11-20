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

    /// Local fallback for ad-hoc development builds. macOS shows a blocking
    /// Keychain prompt for unsigned apps on every read, which makes the app
    /// unusable after a fresh launch. The fallback is a 0600 file under
    /// Application Support; Keychain remains the primary store for signed
    /// builds and is written in parallel.
    public enum LocalFallback {
        static var fileURL: URL {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            return base.appendingPathComponent("OpenFuse/credentials.json")
        }

        static func load(account: String, service: String) -> String? {
            guard let data = try? Data(contentsOf: fileURL),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: String]
            else { return nil }
            return object["\(service)|\(account)"]
        }

        static func save(password: String, account: String, service: String) throws {
            let file = fileURL
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            var object: [String: String] = [:]
            if let data = try? Data(contentsOf: file),
               let existing = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                object = existing
            }
            object["\(service)|\(account)"] = password
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: file, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }

        static func delete(account: String, service: String) {
            guard let data = try? Data(contentsOf: fileURL),
                  var object = try? JSONSerialization.jsonObject(with: data) as? [String: String]
            else { return }
            object.removeValue(forKey: "\(service)|\(account)")
            if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }

    /// Ad-hoc development builds cannot get a stable Keychain ACL, and macOS
    /// blocks the UI on a password prompt. The 0600 local store is the default;
    /// a signed release build can opt back into Keychain with this flag.
    static var useKeychain: Bool {
        ProcessInfo.processInfo.environment["OPENFUSE_KEYCHAIN"] == "1"
    }

    public static func save(password: String, account: String, service: String = service) throws {
        try LocalFallback.save(password: password, account: account, service: service)
        guard useKeychain else { return }
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
        if let local = LocalFallback.load(account: account, service: service) {
            return local
        }
        guard useKeychain else { return nil }
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
        LocalFallback.delete(account: account, service: service)
        guard useKeychain else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
