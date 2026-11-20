import XCTest
@testable import OpenFuseCore
@testable import OpenFuseData

final class CredentialStoreTests: XCTestCase {
    private let service = "com.openfuse.tests.credentials"
    private let probeService = "com.openfuse.tests.probe"
    private var accounts: [String] = []

    /// A locked login keychain cannot create items at all (the system wants the
    /// user's password). Keychain assertions are skipped in that state instead of
    /// reporting a product failure; `Scripts/verify-keychain.sh` runs the same
    /// checks and reports the locked state explicitly.
    private func requireUnlockedKeychain() throws {
        let account = "probe-\(UUID().uuidString.prefix(6))"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: probeService,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data("probe".utf8),
        ]
        SecKeychainSetUserInteractionAllowed(false)
        let status = SecItemAdd(query as CFDictionary, nil)
        SecKeychainSetUserInteractionAllowed(true)
        if status == errSecSuccess {
            _ = SecItemDelete(query as CFDictionary)
            return
        }
        if status == errSecAuthFailed || status == errSecInteractionNotAllowed {
            throw XCTSkip("login keychain is locked (status \(status)); unlock the Mac and rerun")
        }
        XCTAssertEqual(status, errSecSuccess, "unexpected Keychain status")
    }

    override func tearDownWithError() throws {
        for account in accounts {
            CredentialStore.delete(account: account, service: service)
        }
        accounts.removeAll()
        CredentialStore.resetSessionCache()
    }

    private func uniqueAccount(_ label: String) -> String {
        let account = "test-\(label)-\(UUID().uuidString.prefix(8))"
        accounts.append(account)
        return account
    }

    /// Reads the raw Keychain item, bypassing the in-process cache, so a test
    /// can tell a session-only save from a real Keychain write.
    private func keychainValue(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func testKeychainRoundTripThenDelete() throws {
        try requireUnlockedKeychain()
        let account = uniqueAccount("roundtrip")
        try CredentialStore.save(password: "fake-password-123", account: account, service: service, mode: .keychain)
        // Written through to the Keychain, and read back verbatim.
        XCTAssertEqual(keychainValue(account: account), "fake-password-123")
        CredentialStore.resetSessionCache()
        XCTAssertEqual(CredentialStore.load(account: account, service: service), "fake-password-123")

        // No plaintext copy is left behind for this account.
        let legacy = try legacyFileContents()
        XCTAssertNil(legacy?["\(service)|\(account)"])

        CredentialStore.delete(account: account, service: service)
        XCTAssertNil(keychainValue(account: account))
        XCTAssertNil(CredentialStore.load(account: account, service: service))
    }

    func testSaveOverwritesExistingKeychainItem() throws {
        try requireUnlockedKeychain()
        let account = uniqueAccount("overwrite")
        try CredentialStore.save(password: "first-value", account: account, service: service, mode: .keychain)
        try CredentialStore.save(password: "second-value", account: account, service: service, mode: .keychain)
        XCTAssertEqual(keychainValue(account: account), "second-value")
        CredentialStore.resetSessionCache()
        XCTAssertEqual(CredentialStore.load(account: account, service: service), "second-value")
    }

    func testSessionModeNeverTouchesKeychainOrDisk() throws {
        let account = uniqueAccount("session")
        let before = try legacyFileContents()
        try CredentialStore.save(password: "session-secret", account: account, service: service, mode: .session)

        XCTAssertEqual(CredentialStore.load(account: account, service: service), "session-secret")
        XCTAssertNil(keychainValue(account: account), "session mode must not write the Keychain")

        let after = try legacyFileContents()
        XCTAssertEqual(before, after, "session mode must not write credentials.json")

        CredentialStore.delete(account: account, service: service)
        XCTAssertNil(CredentialStore.load(account: account, service: service))
    }

    func testSessionModeRequestedByEnvironment() throws {
        // The process environment cannot be changed at runtime, so this asserts
        // the contract the acceptance run relies on: the flag maps to session
        // mode when it is present.
        let previous = getenv("OPENFUSE_CREDENTIAL_MODE").map { String(cString: $0) }
        setenv("OPENFUSE_CREDENTIAL_MODE", "session", 1)
        defer {
            if let previous { setenv("OPENFUSE_CREDENTIAL_MODE", previous, 1) }
            else { unsetenv("OPENFUSE_CREDENTIAL_MODE") }
        }
        XCTAssertTrue(CredentialStore.sessionModeRequested)
        XCTAssertEqual(CredentialStore.defaultMode, .session)
        XCTAssertEqual(CredentialStore.defaultMode, CredentialMode.session)
    }

    func testMigrationMovesEntriesAndDeletesPlaintextFile() throws {
        try requireUnlockedKeychain()
        let accountA = uniqueAccount("migrate-a")
        let accountB = uniqueAccount("migrate-b")
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("openfuse-legacy-\(UUID().uuidString).json")
        let legacy: [String: String] = [
            "\(service)|\(accountA)": "legacy-secret-a",
            "\(service)|\(accountB)": "legacy-secret-b",
        ]
        let data = try JSONSerialization.data(withJSONObject: legacy, options: [.sortedKeys])
        try data.write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)

        let report = CredentialStore.migrateLegacyStore(at: file)
        XCTAssertEqual(report.migrated, 2)
        XCTAssertEqual(report.failed, 0)
        XCTAssertTrue(report.removedPlaintextFile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(keychainValue(account: accountA), "legacy-secret-a")
        XCTAssertEqual(keychainValue(account: accountB), "legacy-secret-b")
        CredentialStore.resetSessionCache()
        XCTAssertEqual(CredentialStore.load(account: accountA, service: service), "legacy-secret-a")
    }

    func testMigrationLeavesUnreadableFileAlone() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("openfuse-legacy-bad-\(UUID().uuidString).json")
        try Data("not json".utf8).write(to: file)
        let report = CredentialStore.migrateLegacyStore(at: file)
        XCTAssertEqual(report.migrated, 0)
        XCTAssertFalse(report.removedPlaintextFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        try? FileManager.default.removeItem(at: file)
    }

    private func legacyFileContents() throws -> [String: String]? {
        let url = CredentialStore.legacyStoreURL
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try JSONSerialization.jsonObject(with: data) as? [String: String]
    }
}
