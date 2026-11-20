import Foundation
import Security

public enum CredentialStoreError: LocalizedError {
    case keychain(OSStatus)
    case verificationFailed
    case accessDenied

    public var errorDescription: String? {
        switch self {
        case .keychain(let status):
            return "Keychain 错误 \(status)"
        case .verificationFailed:
            return "Keychain 写入后无法读回同一密码"
        case .accessDenied:
            return "Keychain 拒绝访问：需要在系统弹窗中允许 OpenFuse 读取"
        }
    }
}

/// Where a credential is kept.
///
/// - `keychain`: the login Keychain (default). Nothing is written to disk in
///   plain text.
/// - `session`: memory only. Used for test accounts and for anyone who does not
///   want the password to survive quitting the app.
public enum CredentialMode: String, Sendable {
    case keychain
    case session
}

public struct CredentialMigrationReport: Sendable {
    public var migrated: Int = 0
    public var failed: Int = 0
    public var removedPlaintextFile: Bool = false
    public var hadLegacyStore: Bool = false

    public var summary: String {
        if !hadLegacyStore { return "没有旧版明文凭据" }
        if failed == 0 {
            return removedPlaintextFile
                ? "已迁移 \(migrated) 条凭据到 Keychain，并删除明文文件"
                : "已迁移 \(migrated) 条凭据到 Keychain"
        }
        return "已迁移 \(migrated) 条凭据到 Keychain，\(failed) 条失败并保留在旧文件"
    }
}

/// Generic-password storage for source credentials.
///
/// Design rules:
/// - Keychain is the only persistent backend. `save` never writes a plaintext
///   file; a failed Keychain write throws and leaves no trace on disk.
/// - `session` mode keeps secrets in this process only, so an acceptance run can
///   use real accounts without persisting anything.
/// - Old builds wrote `Application Support/OpenFuse/credentials.json`. That file
///   is migrated entry by entry: Keychain write, read-back verification, then the
///   entry is removed. An entry that cannot be verified stays where it was.
public enum CredentialStore {
    public static let service = "com.openfuse.webdav"

    private static let lock = NSLock()
    private nonisolated(unsafe) static var sessionItems: [String: String] = [:]

    // MARK: - Mode

    /// `OPENFUSE_CREDENTIAL_MODE=session` keeps every credential in memory for
    /// this run. The Add Source sheets expose the same switch as a checkbox.
    public static var sessionModeRequested: Bool {
        let value = ProcessInfo.processInfo.environment["OPENFUSE_CREDENTIAL_MODE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return value == "session" || value == "session-only"
            || ProcessInfo.processInfo.environment["OPENFUSE_SESSION_CREDENTIALS"] == "1"
    }

    public static var defaultMode: CredentialMode {
        sessionModeRequested ? .session : .keychain
    }

    // MARK: - Public API

    public static func save(
        password: String,
        account: String,
        service: String = service,
        mode: CredentialMode? = nil,
        interactive: Bool = false
    ) throws {
        let mode = mode ?? defaultMode
        switch mode {
        case .session:
            storeSession(password, account: account, service: service)
        case .keychain:
            do {
                try writeKeychain(password, account: account, service: service, interactive: interactive)
                guard readKeychain(account: account, service: service) == password else {
                    throw CredentialStoreError.verificationFailed
                }
            } catch {
                // The source keeps working for this run; the caller reports that
                // the Keychain copy failed (locked keychain, denied prompt).
                storeSession(password, account: account, service: service)
                throw error
            }
            // Only after the Keychain copy is proven readable do we touch the
            // legacy plaintext entry for this account.
            removeLegacyEntry(account: account, service: service)
            storeSession(password, account: account, service: service)
        }
    }

    /// What a lookup found in the Keychain.
    public enum LoadResult: Sendable, Equatable {
        case found(String)
        case missing
        /// The item exists but this build may not read it without the user
        /// answering the Keychain dialog. `interactiveLoad` asks for it.
        case needsAuthorization
    }

    public static func load(account: String, service: String = service) -> String? {
        switch loadDetailed(account: account, service: service, interactive: false) {
        case .found(let value): return value
        default: return nil
        }
    }

    /// Reads a credential, optionally allowing the system Keychain dialog.
    /// The non-interactive path is the default so a rebuild with a new ad-hoc
    /// signature can never freeze the app behind an invisible prompt.
    public static func loadDetailed(
        account: String,
        service: String = service,
        interactive: Bool = false
    ) -> LoadResult {
        if let cached = sessionValue(account: account, service: service) {
            return .found(cached)
        }
        switch readKeychainResult(account: account, service: service, interactive: interactive) {
        case .success(let value?):
            storeSession(value, account: account, service: service)
            return .found(value)
        case .failure(.accessDenied):
            return .needsAuthorization
        default:
            break
        }
        // A previous build may still have a plaintext entry. Try to migrate it
        // now (Keychain write + read-back); keep using the value either way so a
        // denied Keychain prompt never locks the user out.
        guard let legacy = legacyPassword(account: account, service: service) else { return .missing }
        if defaultMode == .keychain {
            do {
                try writeKeychain(legacy, account: account, service: service)
                if readKeychain(account: account, service: service) == legacy {
                    removeLegacyEntry(account: account, service: service)
                }
            } catch {
                // Keep the legacy entry; the caller still gets the password.
            }
        }
        storeSession(legacy, account: account, service: service)
        return .found(legacy)
    }

    /// Explicit retry from a user action: this is the only path that may show
    /// the macOS Keychain dialog.
    public static func loadInteractive(account: String, service: String = service) -> String? {
        if case .found(let value) = loadDetailed(account: account, service: service, interactive: true) {
            return value
        }
        return nil
    }

    public static func delete(account: String, service: String = service) {
        removeSessionValue(account: account, service: service)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        _ = withKeychainInteraction(false) { SecItemDelete(query as CFDictionary) }
        removeLegacyEntry(account: account, service: service)
    }

    /// True when this account has a value in this process' session cache. The
    /// UI uses it to show "本次会话" next to a source.
    public static func hasSessionValue(account: String, service: String = service) -> Bool {
        sessionValue(account: account, service: service) != nil
    }

    // MARK: - Legacy plaintext store

    public static var legacyStoreURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("OpenFuse/credentials.json")
    }

    public static var legacyStoreExists: Bool {
        FileManager.default.fileExists(atPath: legacyStoreURL.path)
    }

    /// Migrates every entry of the old plaintext file into the Keychain. Each
    /// entry is verified by reading it back before it is removed from the file;
    /// the file itself disappears once no entries remain.
    @discardableResult
    public static func migrateLegacyStore(at url: URL? = nil) -> CredentialMigrationReport {
        var report = CredentialMigrationReport()
        let file = url ?? legacyStoreURL
        guard let data = try? Data(contentsOf: file),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              !object.isEmpty
        else {
            report.hadLegacyStore = FileManager.default.fileExists(atPath: file.path)
            return report
        }
        report.hadLegacyStore = true
        var remaining: [String: String] = [:]
        for (rawKey, password) in object.sorted(by: { $0.key < $1.key }) {
            let key = parseLegacyKey(rawKey)
            do {
                try writeKeychain(password, account: key.account, service: key.service)
                guard readKeychain(account: key.account, service: key.service) == password else {
                    throw CredentialStoreError.verificationFailed
                }
                storeSession(password, account: key.account, service: key.service)
                report.migrated += 1
            } catch {
                remaining[rawKey] = password
                report.failed += 1
            }
        }
        if remaining.isEmpty {
            try? FileManager.default.removeItem(at: file)
            report.removedPlaintextFile = !FileManager.default.fileExists(atPath: file.path)
        } else if let data = try? JSONSerialization.data(
            withJSONObject: remaining,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: file, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
        return report
    }

    private static func parseLegacyKey(_ raw: String) -> (service: String, account: String) {
        let parts = raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        if parts.count == 2 { return (parts[0], parts[1]) }
        return (service, raw)
    }

    private static func legacyObject() -> [String: String]? {
        guard let data = try? Data(contentsOf: legacyStoreURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return nil }
        return object
    }

    private static func legacyPassword(account: String, service: String) -> String? {
        legacyObject()?["\(service)|\(account)"]
    }

    private static func removeLegacyEntry(account: String, service: String) {
        let file = legacyStoreURL
        guard var object = legacyObject() else { return }
        let key = "\(service)|\(account)"
        guard object.removeValue(forKey: key) != nil else { return }
        if object.isEmpty {
            try? FileManager.default.removeItem(at: file)
            return
        }
        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: file, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
    }

    // MARK: - Session memory

    private static func sessionKey(_ account: String, _ service: String) -> String {
        "\(service)|\(account)"
    }

    private static func storeSession(_ password: String, account: String, service: String) {
        lock.lock()
        sessionItems[sessionKey(account, service)] = password
        lock.unlock()
    }

    private static func sessionValue(account: String, service: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return sessionItems[sessionKey(account, service)]
    }

    private static func removeSessionValue(account: String, service: String) {
        lock.lock()
        sessionItems.removeValue(forKey: sessionKey(account, service))
        lock.unlock()
    }

    /// Test seam: drops the in-process cache without touching the Keychain.
    public static func resetSessionCache() {
        lock.lock()
        sessionItems.removeAll()
        lock.unlock()
    }

    // MARK: - Keychain

    private static func writeKeychain(
        _ password: String,
        account: String,
        service: String,
        interactive: Bool = false
    ) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(password.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrLabel as String: "OpenFuse",
        ]
        let updateStatus = withKeychainInteraction(interactive) {
            SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        }
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            if updateStatus == errSecAuthFailed || updateStatus == errSecInteractionNotAllowed
                || updateStatus == errSecUserCanceled || updateStatus == errSecNoAccessForItem {
                throw CredentialStoreError.accessDenied
            }
            throw CredentialStoreError.keychain(updateStatus)
        }
        var insert = query
        insert.merge(attributes) { _, new in new }
        let status = withKeychainInteraction(interactive) {
            SecItemAdd(insert as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw CredentialStoreError.keychain(status)
        }
    }

    private static func readKeychain(account: String, service: String, interactive: Bool = false) -> String? {
        if case .success(let value) = readKeychainResult(account: account, service: service, interactive: interactive) {
            return value
        }
        return nil
    }

    private static func readKeychainResult(
        account: String,
        service: String,
        interactive: Bool
    ) -> Result<String?, CredentialStoreError> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status: OSStatus = withKeychainInteraction(interactive) {
            SecItemCopyMatching(query as CFDictionary, &item)
        }
        if status == errSecSuccess {
            guard let data = item as? Data else { return .success(nil) }
            return .success(String(data: data, encoding: .utf8))
        }
        if status == errSecItemNotFound { return .success(nil) }
        if status == errSecAuthFailed || status == errSecInteractionNotAllowed || status == errSecUserCanceled
            || status == errSecNoAccessForItem {
            return .failure(.accessDenied)
        }
        return .failure(.keychain(status))
    }

    /// Runs a Keychain call with the legacy UI switch. Reads and writes default
    /// to "no UI" so a stale item from another build fails fast instead of
    /// blocking the main thread behind a dialog the user cannot see.
    private static func withKeychainInteraction<T>(_ allowed: Bool, _ body: () -> T) -> T {
        #if os(macOS)
        // macOS-only: suppresses the classic login-keychain ACL dialog so a
        // stale item from another build fails fast instead of blocking the
        // main thread. iOS has no equivalent switch; the system handles
        // Keychain access prompts itself.
        SecKeychainSetUserInteractionAllowed(allowed)
        defer { SecKeychainSetUserInteractionAllowed(true) }
        #endif
        return body()
    }
}
