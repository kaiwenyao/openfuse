import AppKit
import Combine
import Foundation
import OpenFuseCore
import UniformTypeIdentifiers

enum AppRoute: Equatable {
    case home
    case player
    case browser(WebDAVSource)
    case jellyfinBrowser(JellyfinSource)
    case plexBrowser(PlexSource)
    case library(LibraryWork)
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case title
    case year
    case added
    case episodes
    case recentlyPlayed

    var id: String { rawValue }
    var label: String {
        switch self {
        case .title: return "标题"
        case .year: return "年份"
        case .added: return "最近添加"
        case .episodes: return "集数"
        case .recentlyPlayed: return "最近播放"
        }
    }
}

enum LibraryWatchFilter: String, CaseIterable, Identifiable {
    case all
    case unwatched
    case inProgress
    case watched

    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "全部"
        case .unwatched: return "未看"
        case .inProgress: return "观看中"
        case .watched: return "已看"
        }
    }
}

enum LibraryResolutionFilter: String, CaseIterable, Identifiable {
    case all
    case uhd
    case hd1080
    case hd720

    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "全部"
        case .uhd: return "4K"
        case .hd1080: return "1080p"
        case .hd720: return "720p"
        }
    }
}

enum LibraryWatchState: Sendable {
    case unwatched
    case inProgress
    case watched
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var route: AppRoute = .home
    @Published var recent: [PlaybackRecord] = []
    @Published var player: PlayerModel?
    @Published var statusMessage: String?
    @Published var sources: [WebDAVSource] = []
    @Published var browsingSource: WebDAVSource?
    @Published var showAddSource = false
    @Published var showSeekPrompt = false
    @Published var seekPromptText = ""
    @Published var credentialMigrationSummary: String?
    @Published var showAddJellyfin = false
    @Published var showSettings = false
    @Published var jellyfinSources: [JellyfinSource] = []
    @Published var plexSources: [PlexSource] = []
    @Published var smbSources: [SMBSource] = []
    @Published var localRoots: [LocalRoot] = []
    @Published var libraryWorks: [LibraryWork] = []
    @Published var libraryGroups: [LibraryGroup] = []
    @Published var libraryWorkCount = 0
    @Published var libraryEpisodeCount = 0
    @Published var isScanningLibrary = false
    @Published var libraryStatus: String?
    @Published var syncStatus: String?
    @Published var syncURLText = ""
    @Published var syncTokenInput = ""
    @Published var syncCAPath: String?
    @Published var syncBusy = false
    @Published var traktClientID = ""
    @Published var traktClientSecret = ""
    @Published var traktBaseURL = "https://api.trakt.tv"
    @Published var traktUserCode: String?
    @Published var traktVerificationURL: String?
    @Published var traktDeviceCode: String?
    @Published var traktMessage: String?
    @Published var traktBusy = false
    private var smbStreamServer: SMBStreamServer?
    @Published var librarySearch = ""
    @Published var librarySort: LibrarySort = .title
    @Published var libraryKindFilter: LibraryKind?
    @Published var libraryWatchFilter: LibraryWatchFilter = .all
    @Published var libraryResolutionFilter: LibraryResolutionFilter = .all
    @Published var scanProgress = 0
    /// Directory/episode position per source, so closing the player returns to
    /// the same folder or season instead of the home screen.
    @Published var webdavPaths: [String: [String]] = [:]
    @Published var jellyfinPaths: [String: [JellyfinItem]] = [:]
    private var playerReturnRoute: AppRoute?
    private var activeScanToken: ScanCancellationToken?
    private var activeScanTask: Task<Void, Never>?

    let supportDirectory: URL
    let store: PlaybackStore
    let sourceStore: SourceStore
    let jellyfinStore: JellyfinSourceStore
    let plexStore: PlexSourceStore
    let smbStore: SMBSourceStore
    let localRootStore: LocalRootStore
    let libraryStore: LibraryStore
    let libraryOverrideStore: LibraryOverrideStore
    @Published var libraryOverrides: [String: LibraryOverride] = [:]
    private var sessionJellyfinTokens: [String: String] = [:]
    private var sessionPlexTokens: [String: String] = [:]
    private var sessionSMBPasswords: [String: String] = [:]
    private var traktPollTask: Task<Void, Never>?
    private var playerMenuObservation: AnyCancellable?
    private var keychainPromptedAccounts: Set<String> = []

    init(supportDirectory: URL? = nil) {
        let directory = supportDirectory ?? Self.defaultSupportDirectory()
        self.supportDirectory = directory
        do {
            self.store = try PlaybackStore(directory: directory)
            self.sourceStore = try SourceStore(directory: directory)
            self.jellyfinStore = try JellyfinSourceStore(directory: directory)
            self.plexStore = try PlexSourceStore(directory: directory)
            self.smbStore = try SMBSourceStore(directory: directory)
            self.localRootStore = try LocalRootStore(directory: directory)
            self.libraryStore = try LibraryStore(directory: directory)
            self.libraryOverrideStore = try LibraryOverrideStore(directory: directory)
        } catch {
            fatalError("cannot open OpenFuse store: \(error)")
        }
        self.sources = sourceStore.sources
        self.jellyfinSources = jellyfinStore.sources
        let defaults = UserDefaults.standard
        self.syncURLText = ProcessInfo.processInfo.environment["OPENFUSE_SYNC_URL"]
            ?? defaults.string(forKey: "openfuse.sync.url")
            ?? ""
        self.syncCAPath = defaults.string(forKey: "openfuse.sync.ca")
        self.plexSources = plexStore.sources
        self.smbSources = smbStore.sources
        self.localRoots = localRootStore.roots
        self.libraryOverrides = libraryOverrideStore.all
        if CredentialStore.defaultMode == .keychain, CredentialStore.legacyStoreExists {
            // Old builds kept passwords in Application Support/OpenFuse/credentials.json.
            // Move them into the Keychain entry by entry and drop the plaintext
            // only after each write has been read back successfully.
            let report = CredentialStore.migrateLegacyStore()
            credentialMigrationSummary = report.summary
            statusMessage = report.summary
        }
        loadTraktConfiguration()
        refreshRecent()
        reloadLibrary()
    }

    var traktConfigured: Bool { TraktService.shared.isConfigured }

    private func loadTraktConfiguration() {
        let environment = ProcessInfo.processInfo.environment
        let envBase = environment["OPENFUSE_TRAKT_BASE_URL"]
        let envClient = environment["OPENFUSE_TRAKT_CLIENT_ID"]
        let envToken = environment["OPENFUSE_TRAKT_TOKEN"]
        let defaults = UserDefaults.standard
        let storedClient = defaults.string(forKey: "openfuse.trakt.clientID") ?? ""
        let storedBase = defaults.string(forKey: "openfuse.trakt.baseURL") ?? "https://api.trakt.tv"
        traktClientID = envClient ?? storedClient
        traktBaseURL = envBase ?? storedBase
        guard !traktClientID.isEmpty || envToken != nil else {
            traktMessage = "Trakt 未连接"
            return
        }
        let storedSecret = envToken == nil
            ? CredentialStore.load(account: "trakt-secret", service: "com.openfuse.trakt") ?? ""
            : ""
        let storedToken = envToken == nil
            ? CredentialStore.load(account: "trakt-token", service: "com.openfuse.trakt")
            : nil
        traktClientSecret = storedSecret
        let token = envToken ?? storedToken
        guard let client = Optional(traktClientID), !client.isEmpty,
              let base = URL(string: traktBaseURL), token != nil else {
            traktMessage = "Trakt 未配置完成"
            return
        }
        TraktService.shared.configure(
            baseURL: base,
            clientID: client,
            clientSecret: traktClientSecret,
            token: token
        )
        traktMessage = envToken != nil ? "Trakt 已连接（环境变量）" : "Trakt 已连接"
    }

    @discardableResult
    func saveTraktSettings() -> Bool {
        let client = traktClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !client.isEmpty, let base = URL(string: traktBaseURL) else {
            traktMessage = "请填写 Client ID 与有效 API 地址"
            return false
        }
        UserDefaults.standard.set(client, forKey: "openfuse.trakt.clientID")
        UserDefaults.standard.set(base.absoluteString, forKey: "openfuse.trakt.baseURL")
        if !traktClientSecret.isEmpty {
            try? CredentialStore.save(
                password: traktClientSecret,
                account: "trakt-secret",
                service: "com.openfuse.trakt"
            )
        }
        let token = CredentialStore.load(account: "trakt-token", service: "com.openfuse.trakt")
        TraktService.shared.configure(
            baseURL: base,
            clientID: client,
            clientSecret: traktClientSecret,
            token: token
        )
        traktMessage = token == nil ? "配置已保存，请完成设备授权" : "Trakt 配置已更新"
        return true
    }

    func beginTraktDeviceCode() async {
        guard saveTraktSettings() else { return }
        traktBusy = true
        do {
            let code = try await TraktService.shared.requestDeviceCode()
            traktDeviceCode = code.deviceCode
            traktUserCode = code.userCode
            traktVerificationURL = code.verificationURL
            traktMessage = "在浏览器打开 \(code.verificationURL) 输入 \(code.userCode)"
            startTraktPolling(deviceCode: code.deviceCode, interval: code.interval, expiresIn: code.expiresIn)
        } catch {
            traktBusy = false
            traktMessage = "获取设备码失败：\(error.localizedDescription)"
        }
    }

    func cancelTraktPolling() {
        traktPollTask?.cancel()
        traktPollTask = nil
        traktBusy = false
    }

    private func startTraktPolling(deviceCode: String, interval: Int, expiresIn: Int) {
        traktPollTask?.cancel()
        traktPollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let interval = max(1, interval)
            let attempts = max(1, expiresIn / interval)
            for _ in 0..<attempts {
                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                if Task.isCancelled { return }
                do {
                    let token = try await TraktService.shared.pollDeviceToken(code: deviceCode)
                    self.saveTraktToken(token.accessToken)
                    return
                } catch TraktError.pending {
                    continue
                } catch {
                    self.traktBusy = false
                    self.traktMessage = "自动授权失败：\(error.localizedDescription)"
                    return
                }
            }
            self.traktBusy = false
            self.traktMessage = "设备码已过期，请重新获取"
        }
    }

    private func saveTraktToken(_ token: String) {
        if ProcessInfo.processInfo.environment["OPENFUSE_TRAKT_SKIP_KEYCHAIN"] != "1" {
            try? CredentialStore.save(
                password: token,
                account: "trakt-token",
                service: "com.openfuse.trakt"
            )
        }
        traktBusy = false
        traktMessage = "Trakt 授权成功"
        traktDeviceCode = nil
        traktUserCode = nil
        traktVerificationURL = nil
    }

    func pollTraktToken() async {
        guard let code = traktDeviceCode else {
            traktMessage = "请先获取设备码"
            return
        }
        cancelTraktPolling()
        traktBusy = true
        do {
            let token = try await TraktService.shared.pollDeviceToken(code: code)
            saveTraktToken(token.accessToken)
        } catch TraktError.pending {
            traktBusy = false
            traktMessage = "尚未授权，请完成网页授权后再检查"
        } catch {
            traktBusy = false
            traktMessage = "授权失败：\(error.localizedDescription)"
        }
    }

    static func defaultSupportDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["OPENFUSE_SUPPORT_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("OpenFuse", isDirectory: true)
    }

    func refreshRecent() {
        recent = store.recentlyPlayed(limit: 24)
    }

    func syncPlaybackProgressFromEnvironment() async {
        let environment = ProcessInfo.processInfo.environment
        if let raw = environment["OPENFUSE_SYNC_URL"], let url = URL(string: raw) {
            await runSync(
                transport: HTTPProgressTransport(
                    url: url,
                    token: environment["OPENFUSE_SYNC_TOKEN"],
                    caPath: environment["OPENFUSE_SYNC_CA"]
                )
            )
            return
        }
        if let path = environment["OPENFUSE_SYNC_FILE"], !path.isEmpty {
            await runSync(transport: LocalProgressTransport(fileURL: URL(fileURLWithPath: path)))
            return
        }
        if let container = environment["OPENFUSE_CLOUDKIT_CONTAINER"], !container.isEmpty {
            await runSync(transport: CloudKitProgressTransport(containerIdentifier: container))
            return
        }
        await syncWithSettings()
    }

    @discardableResult
    func saveSyncSettings(urlText: String, token: String, caURL: URL?) -> Bool {
        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            syncStatus = "同步地址需要 http:// 或 https://"
            return false
        }
        let defaults = UserDefaults.standard
        defaults.set(url.absoluteString, forKey: "openfuse.sync.url")
        syncURLText = url.absoluteString
        if let caURL {
            let directory = Self.defaultSupportDirectory()
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let target = directory.appendingPathComponent("sync-ca.pem")
            let accessing = caURL.startAccessingSecurityScopedResource()
            defer { if accessing { caURL.stopAccessingSecurityScopedResource() } }
            do {
                try Data(contentsOf: caURL).write(to: target, options: .atomic)
                syncCAPath = target.path
                defaults.set(target.path, forKey: "openfuse.sync.ca")
            } catch {
                syncStatus = "CA 导入失败：\(error.localizedDescription)"
                return false
            }
        }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            try? CredentialStore.save(password: trimmed, account: "sync-token", service: "com.openfuse.sync")
        } else if CredentialStore.load(account: "sync-token", service: "com.openfuse.sync") == nil {
            syncTokenInput = ""
        }
        syncTokenInput = ""
        syncStatus = "同步设置已保存：\(url.absoluteString)"
        return true
    }

    func syncWithSettings() async {
        let environment = ProcessInfo.processInfo.environment
        guard let raw = environment["OPENFUSE_SYNC_URL"].flatMap(URL.init(string:))
                ?? URL(string: syncURLText) else {
            syncStatus = "未配置同步地址"
            return
        }
        let token = environment["OPENFUSE_SYNC_TOKEN"]
            ?? CredentialStore.load(account: "sync-token", service: "com.openfuse.sync")
        let caPath = environment["OPENFUSE_SYNC_CA"] ?? syncCAPath
        await runSync(
            transport: HTTPProgressTransport(url: raw, token: token, caPath: caPath)
        )
    }

    func saveAndSyncSettings() async {
        syncBusy = true
        defer { syncBusy = false }
        if saveSyncSettings(urlText: syncURLText, token: syncTokenInput, caURL: nil) {
            await syncWithSettings()
        }
    }

    private func runSync(transport: ProgressSyncTransport) async {
        do {
            let result = try await ProgressSyncService(store: store, transport: transport).sync()
            syncStatus = "同步完成：远端 \(result.remoteCount) 条，本地 \(result.localCount) 条，更新 \(result.changed) 条"
            refreshRecent()
        } catch {
            syncStatus = "同步失败：\(error.localizedDescription)"
        }
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        var types: [UTType] = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        for ext in ["mkv", "mka", "m4v", "ts", "m2ts", "webm", "avi", "flv", "wmv", "iso", "mpg", "mpeg"] {
            if let type = UTType(filenameExtension: ext) { types.append(type) }
        }
        panel.allowedContentTypes = types
        panel.message = "选择要播放的视频文件"
        panel.prompt = "打开"
        if panel.runModal() == .OK, let url = panel.url {
            open(url: url)
        }
    }

    func open(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            statusMessage = "文件不存在：\(url.lastPathComponent)"
            return
        }
        do {
            let item = try MediaItem.local(url: url)
            startPlayer(with: item)
        } catch {
            statusMessage = "无法读取文件：\(error.localizedDescription)"
        }
    }

    private func startPlayer(
        with item: MediaItem,
        serverStart: Double = 0,
        serverLastPlayedAt: Date? = nil
    ) {
        smbStreamServer?.stop()
        smbStreamServer = nil
        if let current = player {
            current.stopAndClose()
        }
        let record = store.record(forPath: item.fingerprint.resumeKey)
        let startAt = ResumeMerge.startPosition(
            local: record,
            serverPosition: serverStart,
            serverLastPlayedAt: serverLastPlayedAt
        )
        if let serverLastPlayedAt {
            let runtime = item.jellyfinContext?.runtime ?? record?.duration ?? 0
            store.mergeRemotePosition(
                fingerprint: item.fingerprint,
                position: serverStart,
                duration: runtime,
                lastPlayedAt: serverLastPlayedAt,
                finished: ResumePolicy.isFinished(position: serverStart, duration: runtime)
            )
        }
        if route != .player {
            playerReturnRoute = route
        }
        let model = PlayerModel(item: item, startAt: startAt, store: store)
        // Keep the menu bar's 播放/字幕/音轨 items in sync with the player without
        // republishing every position tick.
        playerMenuObservation = Publishers.Merge3(
            model.$subtitleTracks.map { $0.count },
            model.$audioTracks.map { $0.count },
            model.$selectedSubtitleID.map { _ in 0 }
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in self?.objectWillChange.send() }
        model.onClose = { [weak self] in
            self?.smbStreamServer?.stop()
            self?.smbStreamServer = nil
            self?.player = nil
            self?.route = self?.playerReturnRoute ?? .home
            self?.refreshRecent()
        }
        model.onFinished = { [weak self] in
            self?.refreshRecent()
        }
        player = model
        route = .player
        model.start()
        refreshRecent()
    }

    // MARK: - WebDAV sources

    func password(for source: WebDAVSource) -> String? {
        if let override = ProcessInfo.processInfo.environment["OPENFUSE_WEBDAV_PASSWORD"], !override.isEmpty {
            return override
        }
        return credential(account: source.id, service: CredentialStore.service)
    }

    /// Reads a source credential without ever freezing the UI behind a Keychain
    /// dialog. The first denied lookup explains what to do; the next user action
    /// retries with the system dialog enabled (where "Always Allow" is offered).
    private func credential(account: String, service: String) -> String? {
        switch CredentialStore.loadDetailed(account: account, service: service, interactive: false) {
        case .found(let value):
            return value
        case .missing:
            return nil
        case .needsAuthorization:
            if keychainPromptedAccounts.contains(account) {
                return CredentialStore.loadInteractive(account: account, service: service)
            }
            keychainPromptedAccounts.insert(account)
            statusMessage = "Keychain 需要授权访问此来源的凭据：请在系统弹窗中允许 OpenFuse，然后再次操作"
            return nil
        }
    }

    func webdavClient(for source: WebDAVSource) -> WebDAVClient? {
        guard let password = password(for: source) else { return nil }
        return WebDAVClient(source: source, password: password)
    }

    @discardableResult
    func addSource(
        name: String,
        urlText: String,
        username: String,
        password: String,
        rememberInKeychain: Bool = true
    ) async -> WebDAVSource? {
        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            statusMessage = "服务器地址需要是 http:// 或 https://"
            return nil
        }
        let source = WebDAVSource(name: name.isEmpty ? url.host ?? "WebDAV" : name, baseURL: url, username: username)
        let client = WebDAVClient(source: source, password: password)
        do {
            let entries = try await client.list()
            var keychainError: Error?
            let usesEnvironmentPassword = ProcessInfo.processInfo.environment["OPENFUSE_WEBDAV_PASSWORD"] != nil
            let mode: CredentialMode = rememberInKeychain ? .keychain : .session
            if !usesEnvironmentPassword {
                do {
                    try CredentialStore.save(password: password, account: source.id, mode: mode)
                } catch {
                    keychainError = error
                }
            }
            try sourceStore.upsert(source)
            sources = sourceStore.sources
            if let keychainError {
                // The source still works for this run through the in-memory copy;
                // nothing was written to disk.
                statusMessage = "来源已保存到本次会话，但 Keychain 写入失败：\(keychainError.localizedDescription)"
            } else if usesEnvironmentPassword {
                statusMessage = "已添加 \(source.name)（密码来自环境变量，未写入 Keychain）"
            } else if mode == .session {
                statusMessage = "已添加 \(source.name)（仅本次会话，退出后需重新输入密码），根目录 \(entries.count) 项"
            } else {
                statusMessage = "已添加 \(source.name)，凭据已存入 Keychain，根目录 \(entries.count) 项"
            }
            return source
        } catch {
            statusMessage = error.localizedDescription
            return nil
        }
    }

    func removeSource(_ source: WebDAVSource) {
        try? sourceStore.remove(id: source.id)
        CredentialStore.delete(account: source.id)
        sources = sourceStore.sources
        if let browsingSource, browsingSource.id == source.id {
            self.browsingSource = nil
            route = .home
        }
    }

    func browse(_ source: WebDAVSource) {
        browsingSource = source
        route = .browser(source)
    }

    func webdavPath(for source: WebDAVSource) -> [String] {
        let path = webdavPaths[source.id] ?? [""]
        return path.isEmpty ? [""] : path
    }

    func setWebDAVPath(_ path: [String], for source: WebDAVSource) {
        webdavPaths[source.id] = path.isEmpty ? [""] : path
    }

    func jellyfinPath(for source: JellyfinSource) -> [JellyfinItem] {
        jellyfinPaths[source.id] ?? []
    }

    func setJellyfinPath(_ path: [JellyfinItem], for source: JellyfinSource) {
        jellyfinPaths[source.id] = path
    }

    func loadDirectory(source: WebDAVSource, path: String) async throws -> [RemoteEntry] {
        guard let client = webdavClient(for: source) else {
            throw WebDAVError.unauthorized
        }
        return try await client.list(path: path)
    }

    func openRemote(source: WebDAVSource, entry: RemoteEntry, siblings: [RemoteEntry]) async {
        guard let password = password(for: source) else {
            statusMessage = "缺少 \(source.name) 的密码，请重新添加来源"
            return
        }
        var directoryEntries = siblings
        if directoryEntries.isEmpty {
            let parent = (entry.path as NSString).deletingLastPathComponent
            if let client = webdavClient(for: source) {
                directoryEntries = (try? await client.list(path: parent)) ?? []
            }
        }
        let subtitles = WebDAVClient.subtitleTracks(for: entry, siblings: directoryEntries)
        let item = MediaItem.webdav(source: source, entry: entry, subtitles: subtitles, password: password)
        startPlayer(with: item)
    }

    func openRemote(source: WebDAVSource, path: String) async {
        guard let client = webdavClient(for: source) else {
            statusMessage = "缺少 \(source.name) 的密码，请重新添加来源"
            return
        }
        do {
            guard let entry = try await client.stat(path: path) else {
                statusMessage = "远程条目不存在：\(path)"
                return
            }
            let parent = (path as NSString).deletingLastPathComponent
            let siblings = (try? await client.list(path: parent)) ?? []
            await openRemote(source: source, entry: entry, siblings: siblings)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func closePlayer() {
        smbStreamServer?.stop()
        smbStreamServer = nil
        player?.stopAndClose()
        player = nil
        route = playerReturnRoute ?? .home
        refreshRecent()
    }

    func resume(_ record: PlaybackRecord) {
        if record.sourceKind == "jellyfin" || record.sourceKind == "emby",
           let sourceID = record.sourceID,
           let source = jellyfinSources.first(where: { $0.id == sourceID }) {
            let parts = (record.remotePath ?? "").split(separator: "|", maxSplits: 1).map(String.init)
            guard let itemID = parts.first, !itemID.isEmpty else { return }
            let mediaID = parts.count > 1 ? parts[1] : nil
            Task { await openJellyfinItem(source: source, itemID: itemID, preferredMediaSourceID: mediaID) }
            return
        }
        if record.sourceKind == "smb",
           let sourceID = record.sourceID,
           let path = record.remotePath,
           let source = smbSources.first(where: { $0.id == sourceID }) {
            Task { await openSMBItem(source: source, path: path, title: record.displayTitle ?? "SMB") }
            return
        }
        if record.sourceKind == "webdav",
           let sourceID = record.sourceID,
           let path = record.remotePath,
           let source = sources.first(where: { $0.id == sourceID }) {
            Task { await openRemote(source: source, path: path) }
            return
        }
        open(url: record.url)
    }

    func removeRecent(_ record: PlaybackRecord) {
        store.remove(path: record.mediaPath)
        refreshRecent()
    }

    func saveForTermination() {
        player?.finishSession()
    }

    // MARK: - Jellyfin

    func jellyfinToken(for source: JellyfinSource) -> String? {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment[source.kind == "emby" ? "OPENFUSE_EMBY_TOKEN" : "OPENFUSE_JELLYFIN_TOKEN"],
           !override.isEmpty {
            return override
        }
        if let override = environment["OPENFUSE_JELLYFIN_TOKEN"], !override.isEmpty {
            return override
        }
        if let cached = sessionJellyfinTokens[source.id] { return cached }
        return credential(account: source.id, service: "com.openfuse.jellyfin")
    }

    func smbPassword(for source: SMBSource) -> String? {
        if let password = sessionSMBPasswords[source.id] { return password }
        if let password = ProcessInfo.processInfo.environment["OPENFUSE_SMB_PASSWORD"], !password.isEmpty {
            return password
        }
        return credential(account: source.id, service: "com.openfuse.smb")
    }

    @discardableResult
    func addSMBSource(
        name: String,
        server: String,
        port: Int,
        share: String,
        username: String,
        password: String,
        basePath: String = ""
    ) async -> SMBSource? {
        let source = SMBSource(
            name: name.isEmpty ? "\(server)/\(share)" : name,
            server: server,
            port: port,
            share: share,
            username: username,
            basePath: basePath
        )
        let client = SMBClient(source: source, password: password)
        do {
            _ = try client.list(path: source.rootPath)
            try smbStore.upsert(source)
            sessionSMBPasswords[source.id] = password
            try? CredentialStore.save(password: password, account: source.id, service: "com.openfuse.smb")
            smbSources = smbStore.sources
            statusMessage = "已添加 \(source.name)"
            await scanSMBSource(source)
            return source
        } catch {
            statusMessage = "SMB 添加失败：\(error.localizedDescription)"
            return nil
        }
    }

    func scanSMBSource(_ source: SMBSource) async {
        guard let password = smbPassword(for: source) else {
            libraryStatus = "缺少 \(source.name) 的 SMB 密码"
            return
        }
        isScanningLibrary = true
        libraryStatus = "正在扫描 SMB：\(source.name)…"
        let client = SMBClient(source: source, password: password)
        do {
            let cache = supportDirectory.appendingPathComponent("SMBPosterCache", isDirectory: true)
            let scanned = try await Task.detached(priority: .userInitiated) {
                try SMBLibraryScanner.scan(
                    source: source,
                    client: client,
                    posterCacheDirectory: cache
                )
            }.value
            try libraryStore.replace(source: scanned)
            reloadLibrary()
            let counts = (try? libraryStore.counts()) ?? (works: 0, episodes: 0)
            libraryStatus = "SMB \(source.name)：\(counts.works) 个作品"
        } catch {
            libraryStatus = "SMB 扫描失败：\(error.localizedDescription)"
        }
        isScanningLibrary = false
    }

    func removeSMBSource(_ source: SMBSource) {
        try? smbStore.remove(id: source.id)
        sessionSMBPasswords.removeValue(forKey: source.id)
        CredentialStore.delete(account: source.id, service: "com.openfuse.smb")
        try? libraryStore.removeSource(kind: "smb", sourceID: source.id)
        smbSources = smbStore.sources
        reloadLibrary()
    }

    private func openSMBItem(source: SMBSource, path: String, title: String) async {
        guard let password = smbPassword(for: source) else {
            statusMessage = "缺少 SMB 密码"
            return
        }
        let client = SMBClient(source: source, password: password)
        do {
            let size = try await Task.detached(priority: .userInitiated) {
                try client.size(path: path)
            }.value
            smbStreamServer?.stop()
            smbStreamServer = nil
            var subtitles: [SubtitleTrack] = []
            let directory = (path as NSString).deletingLastPathComponent
            let videoBase = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            if let siblings = try? client.list(path: directory.isEmpty ? "/" : directory) {
                let cache = supportDirectory.appendingPathComponent("SMBSubtitleCache", isDirectory: true)
                try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
                for entry in siblings where !entry.isDirectory {
                    let ext = (entry.name as NSString).pathExtension.lowercased()
                    guard SubtitleCatalog.subtitleExtensions.contains(ext) else { continue }
                    let base = (entry.name as NSString).deletingPathExtension
                    guard let match = SubtitleCatalog.matchSubtitleName(base, videoBase: videoBase) else { continue }
                    guard let data = try? client.fetch(path: entry.path), !data.isEmpty else { continue }
                    let target = cache.appendingPathComponent(
                        LibraryID.hash("\(source.id)|\(entry.path)") + "." + ext
                    )
                    guard (try? data.write(to: target, options: .atomic)) != nil else { continue }
                    let language = match.language ?? LanguageTag.infer(from: base)
                    let format = SubtitleFormat(fileExtension: ext)
                    subtitles.append(
                        SubtitleTrack(
                            id: "smb:\(source.id):\(entry.path)",
                            displayName: SubtitleLabel.make(
                                language: language,
                                format: format,
                                forced: match.forced,
                                includeFormat: true
                            ),
                            language: language,
                            format: format,
                            source: .downloaded,
                            url: target,
                            isForced: match.forced
                        )
                    )
                }
            }
            let server = try await SMBStreamServer.start(client: client, path: path, size: size)
            let media = MediaItem.smb(
                source: source,
                path: path,
                title: title,
                size: size,
                playbackURL: server.url,
                subtitles: subtitles
            )
            startPlayer(with: media)
            smbStreamServer = server
        } catch {
            statusMessage = "SMB 流读取失败：\(error.localizedDescription)"
        }
    }

    func plexToken(for source: PlexSource) -> String? {
        if let token = sessionPlexTokens[source.id] { return token }
        if let token = ProcessInfo.processInfo.environment["OPENFUSE_PLEX_TOKEN"], !token.isEmpty {
            return token
        }
        return credential(account: source.id, service: "com.openfuse.plex")
    }

    func plexPosterURL(sourceID: String, itemID: String) -> URL? {
        guard let source = plexSources.first(where: { $0.id == sourceID }),
              let token = plexToken(for: source) else { return nil }
        return PlexClient(source: source, token: token).imageURL(
            thumb: "/library/metadata/\(itemID)/thumb/1"
        )
    }

    func syncTraktHistory() async -> Int {
        let history = await TraktService.shared.history()
        guard !history.isEmpty else {
            statusMessage = "Trakt 历史为空或未配置"
            return 0
        }
        var marked = 0
        for item in history {
            let target = libraryWorks.first {
                normalizedTraktTitle($0.title) == normalizedTraktTitle(item.title)
            }
            guard let work = target else { continue }
            let episodes: [LibraryEpisode]
            if item.kind == .movie {
                episodes = libraryEpisodes(workID: work.id).filter { $0.seasonNumber == 0 }
            } else {
                episodes = libraryEpisodes(workID: work.id).filter {
                    $0.seasonNumber == (item.season ?? 1) && $0.episodeNumber == (item.episode ?? 1)
                }
            }
            for episode in episodes {
                var didMark = false
                for key in playbackKeys(work: work, episode: episode) {
                    store.update(
                        fingerprint: MediaFingerprint(path: key, fileSize: 0, modifiedAt: nil),
                        duration: max(episode.runtime, 1),
                        position: 0,
                        displayTitle: episode.title,
                        finished: true,
                        sourceKind: work.sourceKind,
                        sourceID: work.sourceID,
                        remotePath: episode.remotePath
                    )
                    didMark = true
                }
                if didMark { marked += 1 }
            }
        }
        refreshRecent()
        statusMessage = "Trakt 历史：匹配 \(marked) 集"
        return marked
    }

    private func playbackKeys(work: LibraryWork, episode: LibraryEpisode) -> [String] {
        if let fileURL = episode.fileURL, !fileURL.isEmpty {
            let path = URL(string: fileURL)?.path ?? fileURL
            return [path]
        }
        let versions = libraryVersions(itemID: episode.id)
        if versions.isEmpty {
            return []
        }
        return versions.compactMap { version in
            switch work.sourceKind {
            case "jellyfin", "emby":
                let itemID = episode.serverID ?? version.remotePath ?? episode.remotePath ?? episode.id
                return "\(version.sourceKind)://\(work.sourceID)/\(itemID)/\(version.mediaSourceID ?? "")"
            case "webdav":
                guard let path = version.remotePath ?? episode.remotePath else { return nil }
                return "webdav://\(work.sourceID)/\(path)"
            case "smb":
                guard let path = version.remotePath ?? episode.remotePath else { return nil }
                return "smb://\(work.sourceID)/\(path)"
            case "plex":
                guard let path = version.remotePath else { return nil }
                return "plex://\(work.sourceID)/\(path)"
            default:
                return nil
            }
        }
    }

    private func normalizedTraktTitle(_ title: String) -> String {
        var value = title
        value = value.replacingOccurrences(of: #"\(\d{4}\)"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\[\d{4}\]"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"[^0-9A-Za-z\p{Han}]"#, with: "", options: .regularExpression)
        return value.lowercased()
    }

    @discardableResult
    func addPlexSource(name: String, urlText: String, token: String) async -> Bool {
        guard let url = URL(string: urlText) else {
            statusMessage = "Plex 地址无效"
            return false
        }
        let source = PlexSource(name: name.isEmpty ? url.host ?? "Plex" : name, baseURL: url)
        let client = PlexClient(source: source, token: token)
        do {
            _ = try await client.sections()
            try plexStore.upsert(source)
            sessionPlexTokens[source.id] = token
            try? CredentialStore.save(password: token, account: source.id, service: "com.openfuse.plex")
            plexSources = plexStore.sources
            statusMessage = "已添加 \(source.name)"
            await scanPlexSource(source)
            return true
        } catch {
            statusMessage = "Plex 添加失败：\(error.localizedDescription)"
            return false
        }
    }

    func scanPlexSource(_ source: PlexSource) async {
        guard let token = plexToken(for: source) else {
            statusMessage = "缺少 \(source.name) 的 Plex token"
            return
        }
        isScanningLibrary = true
        scanProgress = 0
        libraryStatus = "正在扫描 Plex：\(source.name)…"
        do {
            let scanned = try await PlexLibraryScanner.scan(
                source: source,
                client: PlexClient(source: source, token: token)
            )
            try libraryStore.replace(source: scanned)
            reloadLibrary()
            let counts = (try? libraryStore.counts()) ?? (works: 0, episodes: 0)
            libraryStatus = "Plex \(source.name)：\(counts.works) 个作品"
        } catch {
            libraryStatus = "Plex 扫描失败：\(error.localizedDescription)"
        }
        isScanningLibrary = false
    }

    func removePlexSource(_ source: PlexSource) {
        try? plexStore.remove(id: source.id)
        sessionPlexTokens.removeValue(forKey: source.id)
        CredentialStore.delete(account: source.id, service: "com.openfuse.plex")
        try? libraryStore.removeSource(kind: "plex", sourceID: source.id)
        plexSources = plexStore.sources
        reloadLibrary()
    }

    func addJellyfinSource(
        name: String,
        urlText: String,
        username: String,
        password: String,
        serverKind: String = "jellyfin",
        rememberInKeychain: Bool = true
    ) async -> JellyfinSource? {
        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else {
            statusMessage = "服务器地址需要是 http:// 或 https://"
            return nil
        }
        let fallbackName = serverKind == "emby" ? "Emby" : "Jellyfin"
        var source = JellyfinSource(
            name: name.isEmpty ? url.host ?? fallbackName : name,
            baseURL: url,
            username: username,
            serverKind: serverKind
        )
        do {
            let session = try await JellyfinClient.authenticate(source: source, password: password)
            source.userID = session.userID
            source.serverID = session.serverID
            let client = JellyfinClient(source: source, token: session.accessToken)
            let views = try await client.views()
            sessionJellyfinTokens[source.id] = session.accessToken
            let environment = ProcessInfo.processInfo.environment
            let prefix = source.kind == "emby" ? "OPENFUSE_EMBY" : "OPENFUSE_JELLYFIN"
            let usesEnvironment = environment[prefix + "_PASSWORD"] != nil
                || environment[prefix + "_TOKEN"] != nil
                || environment["OPENFUSE_JELLYFIN_PASSWORD"] != nil
                || environment["OPENFUSE_JELLYFIN_TOKEN"] != nil
            if !usesEnvironment {
                try? CredentialStore.save(
                    password: session.accessToken,
                    account: source.id,
                    service: "com.openfuse.jellyfin",
                    mode: rememberInKeychain ? .keychain : .session
                )
            }
            try jellyfinStore.upsert(source)
            jellyfinSources = jellyfinStore.sources
            let storage = rememberInKeychain ? "登录令牌已存入 Keychain" : "登录令牌仅用于本次会话"
            statusMessage = "已添加 \(source.name)（\(serverKind == "emby" ? "Emby" : "Jellyfin")），共 \(views.count) 个媒体库，\(storage)"
            return source
        } catch {
            statusMessage = error.localizedDescription
            return nil
        }
    }

    func switchJellyfinUser(
        _ source: JellyfinSource,
        username: String,
        password: String,
        rememberInKeychain: Bool = true
    ) async -> JellyfinSource? {
        var candidate = JellyfinSource(
            name: source.name,
            baseURL: source.baseURL,
            username: username,
            serverKind: source.serverKind
        )
        do {
            let session = try await JellyfinClient.authenticate(source: candidate, password: password)
            candidate.userID = session.userID
            candidate.serverID = session.serverID
            let environment = ProcessInfo.processInfo.environment
            let prefix = candidate.kind == "emby" ? "OPENFUSE_EMBY" : "OPENFUSE_JELLYFIN"
            let usesEnvironment = environment[prefix + "_PASSWORD"] != nil
                || environment[prefix + "_TOKEN"] != nil
                || environment["OPENFUSE_JELLYFIN_PASSWORD"] != nil
                || environment["OPENFUSE_JELLYFIN_TOKEN"] != nil
            if candidate.id != source.id {
                removeJellyfinSource(source)
            }
            try jellyfinStore.upsert(candidate)
            jellyfinSources = jellyfinStore.sources
            sessionJellyfinTokens[candidate.id] = session.accessToken
            if !usesEnvironment {
                try? CredentialStore.save(
                    password: session.accessToken,
                    account: candidate.id,
                    service: "com.openfuse.jellyfin",
                    mode: rememberInKeychain ? .keychain : .session
                )
            }
            statusMessage = "已切换 \(candidate.name) 用户：\(candidate.username)"
            await scanJellyfinSource(candidate)
            return candidate
        } catch {
            statusMessage = "切换用户失败：\(error.localizedDescription)"
            return nil
        }
    }

    func removeJellyfinSource(_ source: JellyfinSource) {
        try? jellyfinStore.remove(id: source.id)
        try? libraryStore.removeSource(kind: source.kind, sourceID: source.id)
        try? libraryStore.removeSource(kind: "jellyfin", sourceID: source.id)
        try? libraryStore.removeSource(kind: "emby", sourceID: source.id)
        CredentialStore.delete(account: source.id, service: "com.openfuse.jellyfin")
        sessionJellyfinTokens.removeValue(forKey: source.id)
        jellyfinSources = jellyfinStore.sources
        reloadLibrary()
        if case .jellyfinBrowser(let browsing) = route, browsing.id == source.id {
            route = .home
        }
    }

    func browseJellyfin(_ source: JellyfinSource) {
        route = .jellyfinBrowser(source)
    }

    func browsePlex(_ source: PlexSource) {
        route = .plexBrowser(source)
    }

    func plexClient(for source: PlexSource) -> PlexClient? {
        guard let token = plexToken(for: source) else { return nil }
        return PlexClient(source: source, token: token)
    }

    func openPlexMetadata(_ metadata: PlexMetadata, source: PlexSource) async {
        await openPlexMedia(metadata, source: source, mediaIndex: 0)
    }

    func openPlexMedia(_ metadata: PlexMetadata, source: PlexSource, mediaIndex: Int) async {
        guard let media = metadata.media, media.indices.contains(mediaIndex),
              let part = media[mediaIndex].parts?.first else {
            libraryStatus = "Plex 条目没有可播放文件"
            return
        }
        await openPlexItem(
            source: source,
            token: plexToken(for: source) ?? "",
            ratingKey: metadata.ratingKey,
            partKey: part.key,
            title: metadata.title,
            duration: Double(metadata.duration ?? 0) / 1000
        )
    }

    func playPlexMetadata(source: PlexSource, ratingKey: String) async {
        guard let client = plexClient(for: source) else {
            statusMessage = "缺少 Plex token"
            return
        }
        do {
            guard let metadata = try await client.metadata(ratingKey: ratingKey) else {
                statusMessage = "Plex 找不到条目 \(ratingKey)"
                return
            }
            await openPlexMetadata(metadata, source: source)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func jellyfinImageURL(source: JellyfinSource, item: JellyfinItem, maxWidth: Int = 480) -> URL? {
        guard let client = jellyfinClient(for: source) else { return nil }
        return client.imageURL(itemID: item.id, tag: item.primaryImageTag, maxWidth: maxWidth)
    }

    func jellyfinClient(for source: JellyfinSource) -> JellyfinClient? {
        guard let token = jellyfinToken(for: source) else { return nil }
        return JellyfinClient(source: source, token: token)
    }

    func loadJellyfinViews(source: JellyfinSource) async throws -> [JellyfinItem] {
        guard let client = jellyfinClient(for: source) else { throw JellyfinError.unauthorized }
        return try await client.views()
    }

    func loadJellyfinItems(source: JellyfinSource, parentID: String) async throws -> [JellyfinItem] {
        guard let client = jellyfinClient(for: source) else { throw JellyfinError.unauthorized }
        return try await client.items(parentID: parentID)
    }

    func loadJellyfinItem(source: JellyfinSource, itemID: String) async throws -> JellyfinItem {
        guard let client = jellyfinClient(for: source) else { throw JellyfinError.unauthorized }
        return try await client.item(id: itemID)
    }

    func loadJellyfinPlaybackInfo(source: JellyfinSource, itemID: String) async throws -> JellyfinPlaybackInfo {
        guard let client = jellyfinClient(for: source) else { throw JellyfinError.unauthorized }
        return try await client.playbackInfo(itemID: itemID)
    }

    func openJellyfinItem(
        source: JellyfinSource,
        itemID: String,
        preferredMediaSourceID: String? = nil
    ) async {
        guard let client = jellyfinClient(for: source), let token = jellyfinToken(for: source) else {
            statusMessage = "缺少 \(source.name) 的登录令牌，请重新添加来源"
            return
        }
        do {
            let item = try await client.item(id: itemID)
            let playback = try await client.playbackInfo(itemID: itemID)
            guard !playback.mediaSources.isEmpty else {
                statusMessage = "服务器没有返回可播放版本"
                return
            }
            let mediaSource: JellyfinMediaSource
            if let preferredMediaSourceID,
               let match = playback.mediaSources.first(where: { $0.id == preferredMediaSourceID || $0.name == preferredMediaSourceID }) {
                mediaSource = match
            } else if let direct = playback.mediaSources.first(where: { $0.supportsDirectPlay == true }) {
                mediaSource = direct
            } else {
                mediaSource = playback.mediaSources[0]
            }
            let subtitles = MediaItem.serverSubtitles(
                source: source,
                mediaSource: mediaSource,
                itemID: item.id,
                token: token
            )
            guard let mediaItem = MediaItem.jellyfin(
                source: source,
                item: item,
                mediaSource: mediaSource,
                playbackInfo: playback,
                token: token,
                subtitles: subtitles
            ) else {
                statusMessage = "无法构造 Jellyfin 播放地址"
                return
            }
            startPlayer(
                with: mediaItem,
                serverStart: JellyfinTicks.seconds(item.userData?.playbackPositionTicks),
                serverLastPlayedAt: item.userData?.lastPlayedAt
            )
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    // MARK: - Media library

    func reloadLibrary() {
        do {
            let stored = try libraryStore.works()
            libraryWorks = stored.map { work in
                if let override = libraryOverrides[work.id] {
                    return override.apply(to: work)
                }
                return work
            }
            rebuildLibraryGroups()
            let counts = try libraryStore.counts()
            libraryWorkCount = libraryGroups.count
            libraryEpisodeCount = libraryGroups.reduce(0) { $0 + $1.primary.episodeCount }
        } catch {
            libraryStatus = error.localizedDescription
        }
    }

    func scanLocalFolder(_ url: URL) async {
        registerLocalRoot(url)
        let token = ScanCancellationToken()
        activeScanToken = token
        await performLocalScan(url, token: token)
    }

    func startLocalScan(_ url: URL) {
        registerLocalRoot(url)
        cancelScan()
        let token = ScanCancellationToken()
        activeScanToken = token
        activeScanTask = Task { await performLocalScan(url, token: token) }
    }

    func scanAllLocalRoots() {
        cancelScan()
        let roots = localRoots
        guard !roots.isEmpty else {
            libraryStatus = "还没有本地根目录"
            return
        }
        let token = ScanCancellationToken()
        activeScanToken = token
        activeScanTask = Task {
            for root in roots {
                if token.isCancelled { break }
                await performLocalScan(URL(fileURLWithPath: root.path), token: token)
            }
            if !token.isCancelled {
                let counts = (try? libraryStore.counts()) ?? (works: 0, episodes: 0)
                libraryStatus = "已扫描 \(roots.count) 个本地根目录：\(counts.works) 个作品"
            }
        }
    }

    func addLocalRoot(_ url: URL) {
        registerLocalRoot(url)
    }

    func removeLocalRoot(_ root: LocalRoot) {
        try? localRootStore.remove(id: root.id)
        try? libraryStore.removeSource(kind: "local", sourceID: root.id)
        localRoots = localRootStore.roots
        reloadLibrary()
        libraryStatus = "已移除本地根目录 \(root.name)"
    }

    private func registerLocalRoot(_ url: URL) {
        let standardized = url.standardizedFileURL
        let name = standardized.lastPathComponent.isEmpty ? "本地文件夹" : standardized.lastPathComponent
        try? localRootStore.upsert(path: standardized.path, name: name)
        localRoots = localRootStore.roots
    }

    func cancelScan() {
        guard isScanningLibrary else { return }
        activeScanToken?.cancel()
        activeScanTask?.cancel()
        activeScanToken = nil
        activeScanTask = nil
        isScanningLibrary = false
        libraryStatus = "扫描已取消，媒体库保持原样"
    }

    private func performLocalScan(_ url: URL, token: ScanCancellationToken) async {
        isScanningLibrary = true
        scanProgress = 0
        libraryStatus = "正在扫描 \(url.lastPathComponent)…"
        do {
            let scanned = try await Task.detached(priority: .userInitiated) {
                try LibraryScanner.scanLocal(
                    directory: url,
                    token: token,
                    progress: { value in
                        Task { @MainActor in self.scanProgress = value }
                    }
                )
            }.value
            guard !token.isCancelled else { throw LibraryScanError.cancelled }
            let probed = MediaProbe.enrichLocalResolutions(scanned)
            let enriched = await enrichWithTMDB(probed)
            guard !token.isCancelled else { throw LibraryScanError.cancelled }
            try libraryStore.replace(source: enriched.library)
            reloadLibrary()
            let counts = (try? libraryStore.counts()) ?? (works: 0, episodes: 0)
            let tmdbMatched = tmdbAvailable
                ? ((try? libraryStore.works())?.filter { $0.poster?.hasPrefix("remote:") == true }.count ?? 0)
                : 0
            libraryStatus = "已扫描 \(scanned.sourceName)：\(counts.works) 个作品" +
                (tmdbMatched > 0 ? "，TMDB 匹配 \(tmdbMatched)" : "")
        } catch LibraryScanError.cancelled {
            libraryStatus = "扫描已取消，媒体库保持原样"
        } catch {
            libraryStatus = "扫描失败：\(error.localizedDescription)"
        }
        if activeScanToken === token { isScanningLibrary = false }
    }

    var tmdbAvailable: Bool {
        !(ProcessInfo.processInfo.environment["OPENFUSE_TMDB_API_KEY"] ?? "").isEmpty
    }

    func tmdbImageURL(path: String?) -> URL? {
        tmdbClient()?.imageURL(path: path)
    }

    func searchTMDBCandidates(title: String, year: Int?, kind: LibraryKind) async -> [TMDBMatch] {
        guard let client = tmdbClient() else { return [] }
        return await client.candidates(title: title, year: year, kind: kind)
    }

    private func tmdbClient() -> TMDBClient? {
        guard let key = ProcessInfo.processInfo.environment["OPENFUSE_TMDB_API_KEY"], !key.isEmpty else {
            return nil
        }
        let base = ProcessInfo.processInfo.environment["OPENFUSE_TMDB_BASE_URL"].flatMap(URL.init(string:))
            ?? URL(string: "https://api.themoviedb.org/3")!
        let image = ProcessInfo.processInfo.environment["OPENFUSE_TMDB_IMAGE_BASE"].flatMap(URL.init(string:))
            ?? URL(string: "https://image.tmdb.org/t/p/w500")!
        return TMDBClient(apiKey: key, baseURL: base, imageBaseURL: image)
    }

    private func enrichWithTMDB(_ library: ScannedLibrary) async -> (library: ScannedLibrary, matched: Int) {
        guard let client = tmdbClient() else { return (library, 0) }
        return await LibraryMetadata.enrich(library, client: client)
    }

    func startJellyfinScan(_ source: JellyfinSource) {
        cancelScan()
        let token = ScanCancellationToken()
        activeScanToken = token
        activeScanTask = Task { await performJellyfinScan(source, token: token) }
    }

    func scanJellyfinSource(_ source: JellyfinSource) async {
        cancelScan()
        let token = ScanCancellationToken()
        activeScanToken = token
        await performJellyfinScan(source, token: token)
    }

    private func performJellyfinScan(_ source: JellyfinSource, token: ScanCancellationToken) async {
        guard let client = jellyfinClient(for: source) else {
            libraryStatus = "缺少 \(source.name) 的登录令牌"
            return
        }
        guard activeScanToken === token else { return }
        isScanningLibrary = true
        scanProgress = 0
        libraryStatus = "正在扫描 Jellyfin：\(source.name)…"
        do {
            let result = try await LibraryScanner.scanJellyfin(
                source: source,
                client: client,
                token: token,
                progress: { value in
                    Task { @MainActor in self.scanProgress = value }
                }
            )
            guard activeScanToken === token, !token.isCancelled else {
                throw LibraryScanError.cancelled
            }
            if result.hasTransientFailure {
                let names = result.transientFailures.map(\.libraryName).joined(separator: "、")
                libraryStatus = "Jellyfin \(source.name)：\(names) 读取不完整，已保留上次完整索引，可重试"
            } else {
                try libraryStore.replace(source: result.library)
                reloadLibrary()
                let counts = (try? libraryStore.counts()) ?? (works: 0, episodes: 0)
                var status = "Jellyfin \(source.name)：\(counts.works) 个作品"
                if !result.revokedLibraryNames.isEmpty {
                    status += "，已移除无权访问的 \(result.revokedLibraryNames.joined(separator: "、"))"
                }
                libraryStatus = status
            }
        } catch LibraryScanError.cancelled {
            libraryStatus = "Jellyfin 扫描已取消，媒体库保持原样"
        } catch JellyfinError.unauthorized {
            try? libraryStore.removeSource(kind: source.kind, sourceID: source.id)
            reloadLibrary()
            libraryStatus = "Jellyfin \(source.name)：服务器撤回了访问权限，请重新登录该来源"
        } catch {
            libraryStatus = "Jellyfin 扫描失败：\(error.localizedDescription)，媒体库保持原样"
        }
        if activeScanToken === token {
            isScanningLibrary = false
            activeScanToken = nil
            activeScanTask = nil
        }
    }

    func startWebDAVScan(_ source: WebDAVSource) {
        cancelScan()
        let token = ScanCancellationToken()
        activeScanToken = token
        activeScanTask = Task { await performWebDAVScan(source, token: token) }
    }

    func scanWebDAVSource(_ source: WebDAVSource) async {
        let token = ScanCancellationToken()
        activeScanToken = token
        await performWebDAVScan(source, token: token)
    }

    private func performWebDAVScan(_ source: WebDAVSource, token: ScanCancellationToken) async {
        guard let client = webdavClient(for: source) else {
            libraryStatus = "缺少 \(source.name) 的密码"
            return
        }
        isScanningLibrary = true
        scanProgress = 0
        libraryStatus = "正在扫描 WebDAV：\(source.name)…"
        do {
            let scanned = try await LibraryScanner.scanWebDAV(
                source: source,
                client: client,
                posterCacheDirectory: supportDirectory.appendingPathComponent("PosterCache", isDirectory: true),
                token: token,
                progress: { value in
                    Task { @MainActor in self.scanProgress = value }
                }
            )
            guard !token.isCancelled else { throw LibraryScanError.cancelled }
            let enriched = await enrichWithTMDB(scanned)
            try libraryStore.replace(
                source: enriched.library,
                preservingRemotePrefixes: scanned.failedPaths
            )
            reloadLibrary()
            let counts = (try? libraryStore.counts()) ?? (works: 0, episodes: 0)
            let tmdbMatched = tmdbAvailable
                ? ((try? libraryStore.works())?.filter { $0.poster?.hasPrefix("remote:") == true }.count ?? 0)
                : 0
            libraryStatus = "WebDAV \(source.name)：\(counts.works) 个作品" +
                (scanned.failedPaths.isEmpty ? "" : "，\(scanned.failedPaths.count) 个目录失败，已保留旧条目") +
                (tmdbMatched > 0 ? "，TMDB 匹配 \(tmdbMatched)" : "")
        } catch LibraryScanError.cancelled {
            libraryStatus = "扫描已取消，媒体库保持原样"
        } catch {
            libraryStatus = "WebDAV 扫描失败：\(error.localizedDescription)"
        }
        if activeScanToken === token { isScanningLibrary = false }
    }

    func librarySeasons(workID: String) -> [LibrarySeason] {
        (try? libraryStore.seasons(workID: workID)) ?? []
    }

    func libraryEpisodes(workID: String, seasonID: String? = nil) -> [LibraryEpisode] {
        (try? libraryStore.episodes(workID: workID, seasonID: seasonID)) ?? []
    }

    func libraryVersions(itemID: String) -> [LibraryVersion] {
        (try? libraryStore.versions(itemID: itemID)) ?? []
    }

    func work(id: String) -> LibraryWork? {
        libraryWorks.first { $0.id == id }
    }

    func rebuildLibraryGroups() {
        let groups = Dictionary(grouping: libraryWorks) { work in
            libraryOverrides[work.id]?.mergeGroupID ?? work.mergeKey
        }
        libraryGroups = groups.map { key, works in
            let sorted = works.sorted { lhs, rhs in
                let left = preference(lhs), right = preference(rhs)
                if left != right { return left > right }
                if lhs.episodeCount != rhs.episodeCount { return lhs.episodeCount > rhs.episodeCount }
                return lhs.id < rhs.id
            }
            return LibraryGroup(id: sorted[0].id, key: key, primary: sorted[0], works: sorted)
        }.sorted { $0.primary.sortTitle.localizedStandardCompare($1.primary.sortTitle) == .orderedAscending }
    }

    private func preference(_ work: LibraryWork) -> Int {
        switch work.sourceKind {
        case "jellyfin", "emby": return 3
        case "local": return 2
        case "webdav": return 1
        case "smb": return 2
        default: return 0
        }
    }

    var visibleLibraryGroups: [LibraryGroup] {
        var groups = libraryGroups
        if let libraryKindFilter {
            groups = groups.filter { $0.primary.kind == libraryKindFilter }
        }
        if libraryWatchFilter != .all {
            groups = groups.filter { group in
                switch libraryWatchFilter {
                case .all: return true
                case .unwatched: return watchState(for: group) == .unwatched
                case .inProgress: return watchState(for: group) == .inProgress
                case .watched: return watchState(for: group) == .watched
                }
            }
        }
        if libraryResolutionFilter != .all {
            groups = groups.filter { group in
                guard let resolution = resolutionHeight(for: group) else { return false }
                switch libraryResolutionFilter {
                case .all: return true
                case .uhd: return resolution >= 2000
                case .hd1080: return resolution >= 1000 && resolution < 2000
                case .hd720: return resolution >= 700 && resolution < 1000
                }
            }
        }
        let query = librarySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            groups = groups.filter { group in
                group.works.contains {
                    $0.title.localizedCaseInsensitiveContains(query)
                        || ($0.overview ?? "").localizedCaseInsensitiveContains(query)
                }
            }
        }
        switch librarySort {
        case .title:
            groups.sort { $0.primary.sortTitle.localizedStandardCompare($1.primary.sortTitle) == .orderedAscending }
        case .year:
            groups.sort { ($0.primary.year ?? 0) > ($1.primary.year ?? 0) }
        case .added:
            groups.sort { $0.primary.addedAt > $1.primary.addedAt }
        case .episodes:
            groups.sort { $0.primary.episodeCount > $1.primary.episodeCount }
        case .recentlyPlayed:
            groups.sort {
                let left = lastPlayedAt(for: $0) ?? .distantPast
                let right = lastPlayedAt(for: $1) ?? .distantPast
                if left == right {
                    return $0.primary.sortTitle.localizedStandardCompare($1.primary.sortTitle) == .orderedAscending
                }
                return left > right
            }
        }
        return groups
    }

    func watchState(for group: LibraryGroup) -> LibraryWatchState {
        let records = Dictionary(uniqueKeysWithValues: store.allRecords().map { ($0.mediaPath, $0) })
        var episodes: [String: [LibraryEpisode]] = [:]
        for work in group.works {
            for episode in libraryEpisodes(workID: work.id) {
                let key = "\(episode.seasonNumber)|\(episode.episodeNumber)"
                episodes[key, default: []].append(episode)
            }
        }
        guard !episodes.isEmpty else { return .unwatched }
        var watched = 0
        var inProgress = 0
        for variants in episodes.values {
            var best: PlaybackRecord?
            for episode in variants {
                if let record = playbackRecord(for: episode, records: records) {
                    if best == nil || record.lastPlayedAt > best!.lastPlayedAt { best = record }
                }
            }
            if let best {
                if best.isFinished { watched += 1 }
                else if best.position > 0 { inProgress += 1 }
            }
        }
        if inProgress > 0 { return .inProgress }
        if watched == episodes.count { return .watched }
        if watched > 0 { return .inProgress }
        return .unwatched
    }

    func lastPlayedAt(for group: LibraryGroup) -> Date? {
        let records = store.allRecords()
        var latest: Date?
        for work in group.works {
            for episode in libraryEpisodes(workID: work.id) {
                if let record = playbackRecord(for: episode, records: Dictionary(uniqueKeysWithValues: records.map { ($0.mediaPath, $0) })),
                   latest == nil || record.lastPlayedAt > latest! {
                    latest = record.lastPlayedAt
                }
            }
        }
        return latest
    }

    func resolutionHeight(for group: LibraryGroup) -> Int? {
        var heights: [Int] = []
        for work in group.works {
            for episode in libraryEpisodes(workID: work.id) {
                for version in libraryVersions(itemID: episode.id) {
                    if let height = resolutionHeight(version) { heights.append(height) }
                }
            }
        }
        return heights.max()
    }

    private func resolutionHeight(_ version: LibraryVersion) -> Int? {
        let text = [version.resolution, version.name, version.container].compactMap { $0 }.joined(separator: " ")
        let upper = text.uppercased()
        if upper.contains("4K") || upper.contains("2160") { return 2160 }
        if upper.contains("1080") { return 1080 }
        if upper.contains("720") { return 720 }
        if upper.contains("480") || upper.contains("SD") { return 480 }
        if let match = text.range(of: #"(\d{3,4})[pP]"#, options: .regularExpression) {
            return Int(text[match].dropLast())
        }
        return nil
    }

    private func playbackRecord(for episode: LibraryEpisode, records: [String: PlaybackRecord]) -> PlaybackRecord? {
        if let fileURL = episode.fileURL {
            let path = URL(string: fileURL)?.path ?? fileURL
            if let record = records[path] { return record }
        }
        for version in libraryVersions(itemID: episode.id) {
            if version.sourceKind == "webdav", let path = version.remotePath ?? episode.remotePath {
                let key = "webdav://\(version.sourceID)/\(path)"
                if let record = records[key] { return record }
            }
            if version.sourceKind == "jellyfin" || version.sourceKind == "emby" {
                let itemID = episode.serverID ?? version.remotePath ?? episode.remotePath ?? ""
                let prefix = "\(version.sourceKind)://\(version.sourceID)/\(itemID)/"
                if let record = records.first(where: { $0.key.hasPrefix(prefix) })?.value {
                    return record
                }
            }
        }
        return nil
    }

    func group(for work: LibraryWork) -> LibraryGroup? {
        if let direct = libraryGroups.first(where: { $0.works.contains { $0.id == work.id } }) {
            return direct
        }
        return libraryGroups.first { $0.key == work.mergeKey }
    }

    func currentWork(id: String) -> LibraryWork? {
        libraryWorks.first { $0.id == id }
    }

    func override(for workID: String) -> LibraryOverride? {
        libraryOverrides[workID]
    }

    func setOverride(
        workID: String,
        title: String?,
        year: Int?,
        overview: String?,
        poster: String?
    ) {
        let existing = libraryOverrides[workID]
        let override = LibraryOverride(
            workID: workID,
            title: title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            year: year,
            overview: overview?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            poster: normalizePoster(poster),
            mergeGroupID: existing?.mergeGroupID
        )
        if override.title == nil, override.year == nil, override.overview == nil,
           override.poster == nil, override.mergeGroupID == nil {
            clearOverride(workID: workID)
            return
        }
        do {
            try libraryOverrideStore.upsert(override)
            libraryOverrides[workID] = override
            reloadLibrary()
            if let updated = currentWork(id: workID) {
                route = .library(updated)
            }
        } catch {
            libraryStatus = "保存纠错失败：\(error.localizedDescription)"
        }
    }

    private func normalizePoster(_ input: String?) -> String? {
        guard let value = input?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if value.hasPrefix("jellyfin:") || value.hasPrefix("file:") || value.hasPrefix("remote:") {
            return value
        }
        if value.hasPrefix("http://") || value.hasPrefix("https://") {
            return PosterRef.remote(value)
        }
        if FileManager.default.fileExists(atPath: value) {
            return PosterRef.file(value)
        }
        return nil
    }

    func groupKey(for work: LibraryWork) -> String {
        libraryOverrides[work.id]?.mergeGroupID ?? work.mergeKey
    }

    func mergeWork(_ work: LibraryWork, into target: LibraryWork) {
        guard work.kind == target.kind else {
            libraryStatus = "只能合并同类型作品（电影合并电影、剧集合并剧集）"
            return
        }
        let key = groupKey(for: target)
        guard key != groupKey(for: work) else { return }
        upsertGrouping(workID: work.id, mergeGroupID: key)
    }

    func splitWork(_ work: LibraryWork) {
        upsertGrouping(workID: work.id, mergeGroupID: "split:\(work.id)")
    }

    func clearGrouping(workID: String) {
        upsertGrouping(workID: workID, mergeGroupID: nil)
    }

    private func upsertGrouping(workID: String, mergeGroupID: String?) {
        let existing = libraryOverrides[workID]
        let override = LibraryOverride(
            workID: workID,
            title: existing?.title,
            year: existing?.year,
            overview: existing?.overview,
            poster: existing?.poster,
            mergeGroupID: mergeGroupID
        )
        do {
            if override.title == nil, override.year == nil, override.overview == nil,
               override.poster == nil, override.mergeGroupID == nil {
                try libraryOverrideStore.remove(workID: workID)
                libraryOverrides.removeValue(forKey: workID)
            } else {
                try libraryOverrideStore.upsert(override)
                libraryOverrides[workID] = override
            }
            reloadLibrary()
            if let updated = currentWork(id: workID) {
                route = .library(updated)
            }
        } catch {
            libraryStatus = "保存分组失败：\(error.localizedDescription)"
        }
    }

    func clearOverride(workID: String) {
        do {
            try libraryOverrideStore.remove(workID: workID)
            libraryOverrides.removeValue(forKey: workID)
            reloadLibrary()
            if let updated = currentWork(id: workID) {
                route = .library(updated)
            }
        } catch {
            libraryStatus = "清除纠错失败：\(error.localizedDescription)"
        }
    }

    func findWork(matching query: String) -> LibraryWork? {
        if let direct = libraryWorks.first(where: { $0.id == query }) { return direct }
        return libraryGroups.first {
            $0.primary.title.localizedCaseInsensitiveContains(query)
                || $0.works.contains { $0.title.localizedCaseInsensitiveContains(query) }
        }?.primary
    }

    @discardableResult
    func playLibraryEpisode(id: String, versionIndex: Int? = nil) -> Bool {
        for work in libraryWorks {
            let seasons = librarySeasons(workID: work.id)
            let episode: LibraryEpisode?
            if seasons.isEmpty {
                episode = libraryEpisodes(workID: work.id).first(where: { $0.id == id })
            } else {
                episode = seasons.lazy
                    .compactMap { self.libraryEpisodes(workID: work.id, seasonID: $0.id).first(where: { $0.id == id }) }
                    .first
            }
            guard let episode else { continue }
            let versions = libraryVersions(itemID: episode.id)
            let version = versionIndex.flatMap { versions.indices.contains($0) ? versions[$0] : nil }
            playLibrary(work: work, episode: episode, version: version)
            return true
        }
        return false
    }

    func writeLibraryReport(to url: URL) {
        let raw = (try? libraryStore.counts()) ?? (works: 0, episodes: 0)
        var payload: [String: Any] = [
            "works": libraryWorkCount,
            "episodes": libraryEpisodeCount,
            "rawWorks": raw.works,
            "rawEpisodes": raw.episodes,
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "status": libraryStatus ?? "",
        ]
        payload["visible"] = visibleLibraryGroups.map { $0.primary.title }
        payload["groups"] = libraryGroups.map { group -> [String: Any] in
            [
                "key": group.key,
                "primary": group.primary.title,
                "sources": group.sourceKinds,
                "workIDs": group.works.map(\.id),
            ]
        }
        payload["merged"] = libraryGroups.map { group -> [String: Any] in
            let episodes = mergedEpisodes(for: group)
            return [
                "key": group.key,
                "title": group.primary.title,
                "sources": group.sourceKinds,
                "episodes": episodes.map { episode -> [String: Any] in
                    [
                        "season": episode.seasonNumber,
                        "episode": episode.episodeNumber,
                        "title": episode.title,
                        "versions": episode.versions.map { $0.label },
                    ]
                },
            ]
        }
        payload["items"] = libraryWorks.map { work -> [String: Any] in
            let seasons = librarySeasons(workID: work.id)
            let episodes = libraryEpisodes(workID: work.id)
            return [
                "id": work.id,
                "kind": work.kind.rawValue,
                "title": work.title,
                "year": work.year ?? 0,
                "overview": work.overview ?? "",
                "sourceKind": work.sourceKind,
                "sourceID": work.sourceID,
                "poster": work.poster ?? "",
                "overridden": libraryOverrides[work.id] != nil,
                "seasons": seasons.map { ["id": $0.id, "number": $0.number, "title": $0.title] },
                "episodes": episodes.map { episode -> [String: Any] in
                    [
                        "id": episode.id,
                        "season": episode.seasonNumber,
                        "episode": episode.episodeNumber,
                        "title": episode.title,
                        "sourceKind": episode.sourceKind,
                        "fileURL": episode.fileURL ?? "",
                        "remotePath": episode.remotePath ?? "",
                        "versions": libraryVersions(itemID: episode.id).map { version in
                            [
                                "id": version.id,
                                "name": version.name,
                                "resolution": version.resolution ?? "",
                                "dynamicRange": version.dynamicRange ?? "",
                                "contentKey": version.contentKey ?? "",
                                "fileURL": version.fileURL ?? "",
                                "mediaSourceID": version.mediaSourceID ?? "",
                            ]
                        },
                    ]
                },
            ]
        }
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
            print("[OpenFuse] wrote library report to \(url.path)")
        }
    }

    func jellyfinPosterURL(sourceID: String, itemID: String, tag: String?, maxWidth: Int = 360) -> URL? {
        guard let source = jellyfinSources.first(where: { $0.id == sourceID }),
              let client = jellyfinClient(for: source)
        else { return nil }
        return client.imageURL(itemID: itemID, tag: tag, maxWidth: maxWidth)
    }

    func mergedEpisodes(for group: LibraryGroup) -> [MergedLibraryEpisode] {
        (try? LibraryAggregation.mergedEpisodes(group: group, store: libraryStore)) ?? []
    }

    func playMergedVersion(_ version: MergedLibraryVersion) {
        playLibrary(work: version.work, episode: version.episode, version: version.version)
    }

    private func openPlexItem(
        source: PlexSource,
        token: String,
        ratingKey: String,
        partKey: String,
        title: String,
        duration: Double
    ) async {
        guard !ratingKey.isEmpty,
              let url = PlexClient(source: source, token: token).streamURL(partKey: partKey) else {
            libraryStatus = "Plex 条目地址无效"
            return
        }
        let client = PlexClient(source: source, token: token)
        let metadata = try? await client.metadata(ratingKey: ratingKey)
        let cache = supportDirectory.appendingPathComponent("SubtitleCache", isDirectory: true)
        let subtitles: [SubtitleTrack]
        if let metadata {
            subtitles = await PlexSubtitle.tracks(
                for: metadata,
                partKey: partKey,
                client: client,
                cacheDirectory: cache
            )
        } else {
            subtitles = []
        }
        let media = MediaItem.plex(
            source: source,
            title: title,
            ratingKey: ratingKey,
            partKey: partKey,
            size: 0,
            duration: duration,
            token: token,
            url: url,
            subtitles: subtitles
        )
        startPlayer(with: media)
    }

    func playLibrary(work: LibraryWork, episode: LibraryEpisode, version: LibraryVersion? = nil) {
        let version = version ?? libraryVersions(itemID: episode.id).first
        if work.kind == .series {
            TraktService.shared.prepare(
                TraktQuery(
                    title: work.title,
                    year: work.year,
                    kind: .show,
                    season: episode.seasonNumber,
                    episode: episode.episodeNumber
                )
            )
        } else {
            TraktService.shared.prepare(
                TraktQuery(title: work.title, year: work.year, kind: .movie)
            )
        }
        switch work.sourceKind {
        case "jellyfin", "emby":
            guard let source = jellyfinSources.first(where: { $0.id == work.sourceID }) else {
                libraryStatus = "Jellyfin 来源已被移除"
                return
            }
            let itemID = episode.serverID ?? episode.remotePath ?? ""
            Task {
                await openJellyfinItem(
                    source: source,
                    itemID: itemID,
                    preferredMediaSourceID: version?.mediaSourceID
                )
            }
        case "smb":
            guard let source = smbSources.first(where: { $0.id == work.sourceID }),
                  let path = version?.remotePath ?? episode.remotePath else {
                libraryStatus = "SMB 来源已被移除"
                return
            }
            Task { await openSMBItem(source: source, path: path, title: episode.title) }
        case "plex":
            guard let source = plexSources.first(where: { $0.id == work.sourceID }),
                  let token = plexToken(for: source),
                  let partKey = version?.remotePath ?? episode.remotePath,
                  let url = PlexClient(source: source, token: token).streamURL(partKey: partKey)
            else {
                libraryStatus = "Plex 来源或 token 已失效"
                return
            }
            Task {
                await openPlexItem(
                    source: source,
                    token: token,
                    ratingKey: episode.serverID ?? "",
                    partKey: partKey,
                    title: episode.title,
                    duration: episode.runtime
                )
            }
        case "webdav":
            guard let source = sources.first(where: { $0.id == work.sourceID }),
                  let path = episode.remotePath ?? version?.remotePath
            else {
                libraryStatus = "WebDAV 来源已被移除"
                return
            }
            Task { await openRemote(source: source, path: path) }
        default:
            if let fileURL = episode.fileURL ?? version?.fileURL, let url = URL(string: fileURL) {
                open(url: url)
            } else {
                libraryStatus = "找不到本地文件"
            }
        }
    }

    /// Manual acceptance helpers: write evidence into
    /// `<support>/Acceptance/` so the screenshots and JSON never carry secrets
    /// and never land in the repository.
    private static func acceptanceStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    func acceptanceDirectory() -> URL {
        let dir = supportDirectory.appendingPathComponent("Acceptance", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    /// Jump to a user-typed time (`mm:ss`, `h:mm:ss` or plain seconds). The
    /// player's in-window scrubber is hard to hit with an accessibility click,
    /// so the menu bar offers the same action with a text field.
    func performSeekPrompt() {
        let raw = seekPromptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let seconds = Self.parseTimecode(raw), let player else { return }
        player.seek(to: seconds)
        seekPromptText = ""
        showSeekPrompt = false
    }

    static func parseTimecode(_ text: String) -> Double? {
        let parts = text.split(separator: ":").map(String.init)
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        var total: Double = 0
        for part in parts {
            guard let value = Double(part.replacingOccurrences(of: ",", with: ".")) else { return nil }
            total = total * 60 + value
        }
        return total >= 0 ? total : nil
    }

    func savePlayerEvidence(label: String = "player") -> URL? {
        guard let player else { return nil }
        let dir = acceptanceDirectory()
        let stamp = Self.acceptanceStamp()
        let frame = dir.appendingPathComponent("\(label)-\(stamp)-frame.png")
        player.captureScreenshot(to: frame)
        let report = dir.appendingPathComponent("\(label)-\(stamp)-report.json")
        writeTestReport(to: report)
        player.statusMessage = "已保存画面与报告"
        return frame
    }

    @discardableResult
    func saveUIEvidence(label: String = "ui") -> URL? {
        let url = acceptanceDirectory().appendingPathComponent("\(label)-\(Self.acceptanceStamp()).png")
        captureUI(to: url)
        statusMessage = "已保存界面截图"
        return url
    }

    func captureUI(to url: URL) {
        let visible = NSApp.windows.filter { $0.isVisible && $0.frame.width > 200 && $0.frame.height > 200 }
        let window = visible.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
            ?? NSApp.keyWindow ?? NSApp.windows.first
        guard let window, let view = window.contentView else { return }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
            print("[OpenFuse] wrote UI capture to \(url.path)")
        }
    }

    func writeTestReport(to url: URL) {
        guard let player else { return }
        var report: [String: Any] = [
            "app": "OpenFuse",
            "engine": "libmpv",
            "mpv": player.engine.getPropertyString("mpv-version") ?? "unknown",
            "file": player.url.absoluteString,
            "title": player.title,
            "sourceKind": player.item.sourceKind ?? "local",
            "sourceName": player.item.sourceName ?? "本地文件",
            "sourceID": player.item.sourceID ?? "",
            "remotePath": player.item.remotePath ?? "",
            "duration": player.duration,
            "position": player.position,
            "paused": player.isPaused,
            "videoCodec": player.engine.snapshot.tracks.first(where: { $0.type == "video" }).map { track in
                [track.codec, track.profile].compactMap { $0 }.joined(separator: " / ")
            } ?? "",
            "videoDescription": player.engine.snapshot.tracks.first(where: { $0.type == "video" })?.codecDescription ?? "",
            "audioCodec": player.engine.getPropertyString("audio-codec-name") ?? "",
            "audioChannels": player.engine.getPropertyString("audio-params/channel-count") ?? "",
            "hwdecCurrent": player.engine.getPropertyString("hwdec-current") ?? "",
            "audioParams": player.engine.getPropertyString("audio-params") ?? "",
            "audioOutParams": player.engine.getPropertyString("audio-out-params") ?? "",
            "currentAO": player.engine.getPropertyString("current-ao") ?? "",
            "currentVO": player.engine.getPropertyString("current-vo") ?? "",
            "isFullScreen": NSApp.keyWindow?.styleMask.contains(.fullScreen) ?? false,
            "windowFrame": NSStringFromRect(NSApp.keyWindow?.frame ?? .zero),
            "videoOutParams": player.engine.getPropertyString("video-out-params") ?? "",
            "toneMapping": player.engine.getPropertyString("tone-mapping") ?? "",
            "hdrComputePeak": player.engine.getPropertyString("hdr-compute-peak") ?? "",
            "videoPrimaries": player.engine.getPropertyString("video-params/primaries") ?? "",
            "videoGamma": player.engine.getPropertyString("video-params/gamma") ?? "",
            "videoSigPeak": player.engine.getPropertyString("video-params/sig-peak") ?? "",
            "targetColorspaceHint": player.engine.getPropertyString("target-colorspace-hint") ?? "",
            "audioDevice": player.selectedAudioDeviceID,
            "audioDeviceActive": player.engine.getPropertyString("audio-device") ?? "",
            "screenEDR": NSScreen.main?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1,
            "selectedSubtitle": player.selectedSubtitleID ?? "off",
            "selectedAudio": player.selectedAudioID ?? "default",
            "libraryStatus": libraryStatus ?? "",
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "arguments": CommandLine.arguments,
            "logs": Array(player.logs.suffix(40)),
        ]
        report["subtitles"] = player.subtitleTracks.map { track -> [String: Any] in
            [
                "id": track.id,
                "name": track.displayName,
                "language": track.language ?? "und",
                "format": track.format.rawValue,
                "source": track.source.rawValue,
                "engineID": track.engineID ?? -1,
            ]
        }
        report["audio"] = player.audioTracks.map { track -> [String: Any] in
            [
                "id": track.id,
                "name": track.displayName,
                "codec": track.codec ?? "",
                "channels": track.channels ?? 0,
                "label": track.technicalLabel,
                "engineID": track.engineID ?? -1,
            ]
        }
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
            print("[OpenFuse] wrote report to \(url.path)")
        }
    }
}

@MainActor
final class PlayerModel: ObservableObject {
    let item: MediaItem
    var url: URL { item.playbackURL }
    var fingerprint: MediaFingerprint { item.fingerprint }
    let engine: MPVEngine
    private let store: PlaybackStore
    private let initialPosition: Double

    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var isPaused = true
    @Published var subtitleTracks: [SubtitleTrack] = []
    @Published var audioTracks: [AudioTrack] = []
    @Published var selectedSubtitleID: String?
    @Published var selectedAudioID: String?
    @Published var audioDevices: [AudioDeviceInfo] = []
    @Published var selectedAudioDeviceID = "auto"
    @Published var speed: Double = 1.0
    @Published var showControls = true
    @Published var isScrubbing = false
    @Published var statusMessage: String?
    @Published var logs: [String] = []

    var onClose: (() -> Void)?
    var onFinished: (() -> Void)?

    private var catalog: [SubtitleTrack]
    private var didAddExternalSubtitles = false
    private var didApplyInitialSelection = false
    private var fileLoaded = false
    private var pendingSeek: Double?
    private var queuedSeek: Double?
    private var seekTarget: Double?
    private var seekIssuedAt: Date?
    private var seekRetryCount = 0

    /// The user's seek target wins over delayed mpv time-pos callbacks until
    /// mpv confirms it. Persisting this also fixes exits right after a seek.
    private var currentPosition: Double { seekTarget ?? position }
    private var progressTimer: Timer?
    private var controlsTimer: Timer?
    private var hasFinished = false
    private var hasStarted = false
    private var lastMouseNote: TimeInterval = 0
    private var savedSubtitleID: String?
    private var savedAudioID: String?
    private var selectionWorkItem: DispatchWorkItem?
    private var selectionAttempts = 0
    private var jellyfinClient: JellyfinClient?
    private var jellyfinContext: JellyfinPlaybackContext?
    private let plexClient: PlexClient?
    private var plexContext: PlexPlaybackContext?
    private var hasReportedPlexStart = false
    private var hasReportedPlexStop = false
    private var hasReportedStop = false
    private var hasReportedStart = false

    init(item: MediaItem, startAt: Double, store: PlaybackStore) {
        self.item = item
        self.initialPosition = startAt
        self.store = store
        self.catalog = item.subtitles
        self.engine = MPVEngine(httpHeaders: item.httpHeaders)
        self.audioDevices = AudioDevices.outputDevices()
        if let device = ProcessInfo.processInfo.environment["OPENFUSE_AUDIO_DEVICE"], !device.isEmpty {
            self.engine.setProperty("audio-device", device)
            self.selectedAudioDeviceID = device
        } else {
            self.selectedAudioDeviceID = self.engine.getPropertyString("audio-device") ?? "auto"
        }
        if let context = item.plexContext {
            let source = PlexSource(
                id: context.sourceID,
                name: item.sourceName ?? "Plex",
                baseURL: context.baseURL
            )
            self.plexClient = PlexClient(source: source, token: context.token)
            self.plexContext = context
        } else {
            self.plexClient = nil
        }
        if let context = item.jellyfinContext {
            let source = JellyfinSource(
                id: context.sourceID,
                name: item.sourceName ?? "Jellyfin",
                baseURL: context.baseURL,
                username: "",
                userID: context.userID
            )
            self.jellyfinClient = JellyfinClient(source: source, token: context.token)
            self.jellyfinContext = context
        }
        wireEngine()
        if let record = store.record(forPath: item.fingerprint.resumeKey) {
            savedAudioID = record.preferredAudioTrackID
            savedSubtitleID = record.preferredSubtitleTrackID
        }
    }

    var title: String { item.title }

    var displayPosition: Double {
        min(max(position, 0), duration > 0 ? duration : position)
    }

    func start() {
        engine.onRenderContextReady = { [weak self] in
            self?.beginPlaybackIfReady()
        }
        if engine.hasRenderContext {
            beginPlaybackIfReady()
        }
    }

    private func beginPlaybackIfReady() {
        guard !hasStarted, engine.hasRenderContext else { return }
        hasStarted = true
        engine.onRenderContextReady = nil
        engine.load(url: item.playbackURL, startAt: initialPosition)
        engine.play()
        scheduleControlsHide()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.saveProgress() }
        }
    }

    private func wireEngine() {
        engine.onTimeChanged = { [weak self] value in
            guard let self, !self.isScrubbing else { return }
            // mpv can deliver a stale time-pos after a seek (the event was
            // already queued). Keep the user's target authoritative until mpv
            // agrees, and re-issue the seek if playback resumed elsewhere.
            if let target = self.seekTarget {
                if abs(value - target) <= 1.5 {
                    self.seekTarget = nil
                    self.seekIssuedAt = nil
                    self.seekRetryCount = 0
                    self.position = value
                    return
                }
                if !self.isPaused,
                   let issued = self.seekIssuedAt,
                   Date().timeIntervalSince(issued) > 2.0,
                   self.seekRetryCount < 2 {
                    self.seekRetryCount += 1
                    self.seekIssuedAt = Date()
                    self.engine.seek(to: target)
                }
                return
            }
            self.position = value
        }
        engine.onDurationChanged = { [weak self] value in
            guard let self else { return }
            self.duration = value
            if let pending = self.pendingSeek, value > 0 {
                self.pendingSeek = nil
                self.engine.seek(to: pending)
            }
            if let queued = self.queuedSeek, value > 0 {
                self.queuedSeek = nil
                self.engine.seek(to: queued)
                self.position = queued
            }
        }
        engine.onPauseChanged = { [weak self] paused in
            self?.isPaused = paused
        }
        engine.onTracksChanged = { [weak self] tracks in
            self?.applyTracks(tracks)
        }
        engine.onFileLoaded = { [weak self] in
            self?.handleFileLoaded()
        }
        engine.onEndFile = { [weak self] reason in
            guard let self else { return }
            if reason == "eof" {
                self.finishPlayback()
            }
        }
        engine.onLog = { [weak self] message in
            guard let self else { return }
            FileHandle.standardError.write("[mpv] \(message)\n".data(using: .utf8)!)
            self.logs.append(message)
            if self.logs.count > 400 { self.logs.removeFirst(self.logs.count - 400) }
        }
    }

    private func debugSelection(_ message: String) {
        if ProcessInfo.processInfo.environment["OPENFUSE_DEBUG_SELECTION"] != nil {
            FileHandle.standardError.write("[selection] \(message)\n".data(using: .utf8)!)
        }
    }

    private func handleFileLoaded() {
        debugSelection("file loaded, catalog=\(catalog.count)")
        fileLoaded = true
        reportJellyfinStart()
        reportPlexStart()
        TraktService.shared.start(
            title: title,
            progress: duration > 0 ? position / duration * 100 : 0
        )
        guard !didAddExternalSubtitles else { return }
        didAddExternalSubtitles = true
        for track in catalog where track.url != nil {
            if let url = track.url {
                engine.addSubtitle(url: url, select: false)
            }
        }
        engine.refreshTracks()
        if initialPosition > 0.2 {
            pendingSeek = initialPosition
            engine.seek(to: initialPosition)
        }
        if !didApplyInitialSelection {
            scheduleInitialSelection(after: 0.6)
        }
    }

    private func applyTracks(_ mpvTracks: [MPVTrackInfo]) {
        var subtitleResult: [SubtitleTrack] = []
        var usedMPVIDs = Set<Int64>()

        for var track in catalog {
            guard let trackURL = track.url else { continue }
            let mpv = mpvTracks.first {
                $0.type == "sub" && matchesExternal(filename: $0.externalFilename, url: trackURL)
            }
            if let mpv {
                var updated = track
                updated.engineID = mpv.id
                updated.language = LanguageTag.normalizeISO(mpv.language) ?? track.language
                updated.displayName = SubtitleLabel.make(
                    language: updated.language,
                    format: updated.format,
                    forced: updated.isForced,
                    includeFormat: true
                )
                usedMPVIDs.insert(mpv.id)
                subtitleResult.append(updated)
                if mpv.isSelected { selectedSubtitleID = updated.id }
            } else {
                subtitleResult.append(track)
            }
        }

        var embeddedSubtitleIndex = 0
        let embeddedServerLabels = serverEmbeddedSubtitleLabels()
        for mpv in mpvTracks where mpv.type == "sub" {
            guard !usedMPVIDs.contains(mpv.id) else { continue }
            let format = SubtitleFormat(fileExtension: mpv.codec ?? "")
            let language = LanguageTag.normalizeISO(mpv.language)
            let serverLabel = embeddedSubtitleIndex < embeddedServerLabels.count ? embeddedServerLabels[embeddedSubtitleIndex] : nil
            embeddedSubtitleIndex += 1
            let label: String
            if let serverLabel, !serverLabel.isEmpty {
                label = serverLabel
            } else if let title = mpv.title, !title.isEmpty {
                label = title
            } else {
                label = SubtitleLabel.make(language: language, format: format, forced: false, includeFormat: true)
            }
            let track = SubtitleTrack(
                id: "mpv:\(mpv.id)",
                displayName: label,
                language: language,
                format: format,
                source: .embedded,
                engineID: mpv.id
            )
            subtitleResult.append(track)
            if mpv.isSelected { selectedSubtitleID = track.id }
        }
        subtitleTracks = subtitleResult
        debugSelection("tracks: subs=\(subtitleResult.map { "\($0.id)#\($0.engineID ?? -1)" }) applied=\(didApplyInitialSelection) attempts=\(selectionAttempts)")

        var audioResult: [AudioTrack] = []
        for mpv in mpvTracks where mpv.type == "audio" {
            let track = AudioTrack(
                id: "mpv-audio:\(mpv.id)",
                displayName: audioLabel(mpv),
                language: LanguageTag.normalizeISO(mpv.language),
                codec: mpv.codec,
                channels: mpv.channels,
                isDefault: mpv.isDefault,
                engineID: mpv.id
            )
            audioResult.append(track)
            if mpv.isSelected { selectedAudioID = track.id }
        }
        applyServerAudioLabels(&audioResult)
        audioTracks = audioResult

        if fileLoaded, !didApplyInitialSelection {
            scheduleInitialSelection(after: 0.35)
        }
    }

    private func scheduleInitialSelection(after delay: Double) {
        guard !didApplyInitialSelection else { return }
        selectionWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.applyInitialSelectionIfReady()
        }
        selectionWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func applyInitialSelectionIfReady() {
        debugSelection("ready check attempts=\(selectionAttempts) loaded=\(subtitleTracks.filter { $0.source == .external && $0.engineID != nil }.count)/\(catalog.filter { $0.source == .external }.count) fileLoaded=\(fileLoaded)")
        guard !didApplyInitialSelection, fileLoaded else { return }
        // WebDAV sidecars and Jellyfin external streams are both loaded by
        // URL after file-load; wait for them before applying the saved track.
        let sidecarCatalog = catalog.filter { $0.source != .embedded && $0.url != nil }
        let loadedExternal = subtitleTracks.filter { $0.source != .embedded && $0.engineID != nil }
        let hasSelectable = subtitleTracks.contains { $0.engineID != nil }
        if !hasSelectable, selectionAttempts < 20 {
            selectionAttempts += 1
            scheduleInitialSelection(after: 0.4)
            return
        }
        if !sidecarCatalog.isEmpty, loadedExternal.count < sidecarCatalog.count, selectionAttempts < 20 {
            selectionAttempts += 1
            scheduleInitialSelection(after: 0.4)
            return
        }
        applyInitialSelection()
        debugSelection("applied selected=\(selectedSubtitleID ?? "nil")")
        didApplyInitialSelection = true
        selectionWorkItem?.cancel()
        selectionWorkItem = nil
    }

    private func applyInitialSelection() {
        if let savedAudio = savedAudioID,
           let match = audioTracks.first(where: { $0.id == savedAudio }), let engineID = match.engineID {
            engine.setAudioTrack(id: engineID)
            selectedAudioID = match.id
        }
        let selectable = subtitleTracks.filter { $0.engineID != nil }
        guard !selectable.isEmpty else { return }
        if let saved = savedSubtitleID, let match = selectable.first(where: { $0.id == saved }) {
            selectSubtitle(match)
            return
        }
        if let simplified = selectable.first(where: { $0.language == "zh-Hans" }) {
            selectSubtitle(simplified)
            return
        }
        if let anyChinese = selectable.first(where: { ($0.language ?? "").hasPrefix("zh") }) {
            selectSubtitle(anyChinese)
            return
        }
        if let embedded = selectable.first(where: { $0.source == .embedded }) {
            selectSubtitle(embedded)
        }
    }

    private func matchesExternal(filename: String?, url: URL) -> Bool {
        guard let filename else { return false }
        let decoded = filename.removingPercentEncoding ?? filename
        let candidates = [
            url.absoluteString,
            url.path,
            url.standardizedFileURL.path,
            url.absoluteString.removingPercentEncoding ?? url.absoluteString,
        ]
        return candidates.contains(filename) || candidates.contains(decoded)
    }

    private func serverEmbeddedSubtitleLabels() -> [String] {
        guard let streams = item.jellyfinContext?.mediaStreams else { return [] }
        return streams
            .filter { $0.type == "Subtitle" && $0.isExternal != true }
            .sorted { $0.index < $1.index }
            .map { $0.displayTitle ?? "" }
    }

    private func applyServerAudioLabels(_ tracks: inout [AudioTrack]) {
        guard let streams = item.jellyfinContext?.mediaStreams else { return }
        let serverAudio = streams.filter { $0.type == "Audio" }.sorted { $0.index < $1.index }
        guard !serverAudio.isEmpty else { return }
        for index in tracks.indices where index < serverAudio.count {
            let stream = serverAudio[index]
            if let title = stream.displayTitle, !title.isEmpty {
                tracks[index].displayName = title
            }
        }
    }

    private func audioLabel(_ mpv: MPVTrackInfo) -> String {
        var pieces: [String] = []
        if let language = LanguageTag.normalizeISO(mpv.language) {
            pieces.append(LanguageTag.displayName(language))
        }
        if let title = mpv.title, !title.isEmpty {
            pieces.append(title)
        }
        if pieces.isEmpty {
            pieces.append("音轨 \(mpv.id)")
        }
        return pieces.joined(separator: " · ")
    }

    func togglePlayPause() {
        engine.togglePause()
        showControlsTemporarily()
    }

    func pause() {
        engine.pause()
    }

    func play() {
        engine.play()
    }

    func skip(_ delta: Double) {
        seek(to: displayPosition + delta)
    }

    func seek(to target: Double) {
        guard duration > 0 else {
            // Remote files (especially on a slow WebDAV server) may still be
            // opening when the user drags. Queue the target instead of sending
            // a command mpv will reject.
            queuedSeek = target
            position = target
            showControlsTemporarily()
            return
        }
        let clamped = max(0, min(duration - 0.25, target))
        position = clamped
        seekTarget = clamped
        seekIssuedAt = Date()
        seekRetryCount = 0
        engine.seek(to: clamped)
        hasFinished = false
        showControlsTemporarily()
    }

    func beginScrub() {
        isScrubbing = true
        showControlsTemporarily()
    }

    func endScrub(at target: Double) {
        isScrubbing = false
        seek(to: target)
    }

    func selectSubtitle(_ track: SubtitleTrack?) {
        guard let track else {
            selectedSubtitleID = nil
            savedSubtitleID = nil
            engine.setSubtitleTrack(id: nil)
            showControlsTemporarily()
            return
        }
        selectedSubtitleID = track.id
        savedSubtitleID = track.id
        if let engineID = track.engineID {
            engine.setSubtitleTrack(id: engineID)
        }
        showControlsTemporarily()
    }

    func selectAudio(_ track: AudioTrack) {
        selectedAudioID = track.id
        savedAudioID = track.id
        if let engineID = track.engineID {
            engine.setAudioTrack(id: engineID)
        }
        showControlsTemporarily()
    }

    func selectAudioDevice(_ id: String) {
        engine.setProperty("audio-device", id)
        selectedAudioDeviceID = id
    }

    func setAudioLayout(_ layout: String) {
        engine.setAudioChannels(layout)
    }

    func setSpeed(_ speed: Double) {
        self.speed = speed
        engine.setSpeed(speed)
        showControlsTemporarily()
    }

    func saveProgress(finished: Bool? = nil) {
        guard duration > 0 else { return }
        let savedPosition = currentPosition
        reportJellyfinProgress()
        reportPlexProgress()
        let resolvedFinished = finished ?? (hasFinished || ResumePolicy.isFinished(position: savedPosition, duration: duration))
        store.update(
            fingerprint: fingerprint,
            duration: duration,
            position: savedPosition,
            displayTitle: title,
            audioTrackID: selectedAudioID,
            subtitleTrackID: selectedSubtitleID,
            finished: resolvedFinished,
            sourceKind: item.sourceKind,
            sourceID: item.sourceID,
            remotePath: item.remotePath,
            remoteURL: item.isRemote ? item.playbackURL.absoluteString : nil
        )
        if resolvedFinished {
            reportPlexStop()
            TraktService.shared.stop(
                title: title,
                progress: duration > 0 ? min(100, position / duration * 100) : 0
            )
        } else {
            TraktService.shared.update(
                title: title,
                progress: duration > 0 ? min(100, position / duration * 100) : 0,
                isPaused: isPaused
            )
        }
    }

    private func finishPlayback() {
        hasFinished = true
        saveProgress(finished: true)
        reportJellyfinStop(wait: false)
        reportPlexStop()
        TraktService.shared.stop(
            title: title,
            progress: duration > 0 ? min(100, position / duration * 100) : 0
        )
        onFinished?()
        showControls = true
    }

    private func reportPlexStart() {
        guard let client = plexClient, let context = plexContext, !hasReportedPlexStart else { return }
        hasReportedPlexStart = true
        let time = initialPosition
        Task.detached {
            await client.reportTimeline(
                ratingKey: context.ratingKey,
                partKey: context.partKey,
                state: "playing",
                time: time,
                duration: context.duration
            )
        }
    }

    private func reportPlexProgress() {
        guard let client = plexClient, let context = plexContext, !hasReportedPlexStop else { return }
        let time = position
        let state = isPaused ? "paused" : "playing"
        let total = duration > 0 ? duration : context.duration
        Task.detached {
            await client.reportTimeline(
                ratingKey: context.ratingKey,
                partKey: context.partKey,
                state: state,
                time: time,
                duration: total
            )
        }
    }

    private func reportPlexStop() {
        guard let client = plexClient, let context = plexContext, !hasReportedPlexStop else { return }
        hasReportedPlexStop = true
        let time = position
        let total = duration > 0 ? duration : context.duration
        Task.detached {
            await client.reportTimeline(
                ratingKey: context.ratingKey,
                partKey: context.partKey,
                state: "stopped",
                time: time,
                duration: total
            )
            await client.scrobble(ratingKey: context.ratingKey)
        }
    }

    private func reportJellyfinStart() {
        guard let client = jellyfinClient, let context = jellyfinContext, !hasReportedStart else { return }
        hasReportedStart = true
        let position = initialPosition
        let paused = isPaused
        Task.detached {
            await client.reportStart(
                itemID: context.itemID,
                mediaSourceID: context.mediaSourceID,
                playSessionID: context.playSessionID,
                position: position,
                isPaused: paused
            )
        }
    }

    private func reportJellyfinProgress() {
        guard let client = jellyfinClient, let context = jellyfinContext, !hasReportedStop else { return }
        let current = currentPosition
        let paused = isPaused
        Task.detached {
            await client.reportProgress(
                itemID: context.itemID,
                mediaSourceID: context.mediaSourceID,
                playSessionID: context.playSessionID,
                position: current,
                isPaused: paused
            )
        }
    }

    private func reportJellyfinStop(wait: Bool) {
        guard let client = jellyfinClient, let context = jellyfinContext, !hasReportedStop else { return }
        hasReportedStop = true
        let current = currentPosition
        if wait {
            let semaphore = DispatchSemaphore(value: 0)
            Task.detached {
                await client.reportStopped(
                    itemID: context.itemID,
                    mediaSourceID: context.mediaSourceID,
                    playSessionID: context.playSessionID,
                    position: current
                )
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 0.8)
        } else {
            Task.detached {
                await client.reportStopped(
                    itemID: context.itemID,
                    mediaSourceID: context.mediaSourceID,
                    playSessionID: context.playSessionID,
                    position: current
                )
            }
        }
    }

    func finishSession() {
        saveProgress()
        reportJellyfinStop(wait: true)
    }

    func stopAndClose() {
        saveProgress()
        reportJellyfinStop(wait: true)
        progressTimer?.invalidate()
        progressTimer = nil
        controlsTimer?.invalidate()
        controlsTimer = nil
        engine.pause()
        engine.shutdown()
        onClose?()
    }

    func freeze(at target: Double) {
        let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                if self.position >= target {
                    self.pause()
                    timer.invalidate()
                    self.showControls = true
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    func selectSubtitle(language tag: String, attempts: Int) {
        guard attempts > 0 else {
            statusMessage = "未找到语言为 \(tag) 的字幕轨"
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            if self.subtitleTracks.isEmpty {
                self.selectSubtitle(language: tag, attempts: attempts - 1)
                return
            }
            let match = self.subtitleTracks.first { track in
                guard let language = track.language else { return false }
                return language == tag || language.hasPrefix(tag + "-") || language.hasPrefix(tag)
            }
            if let match {
                self.selectSubtitle(match)
            } else {
                self.selectSubtitle(language: tag, attempts: attempts - 1)
            }
        }
    }

    func captureScreenshot(to path: URL) {
        engine.screenshot(to: path)
    }

    func showControlsTemporarily() {
        showControls = true
        scheduleControlsHide()
    }

    func noteMouseActivity() {
        let now = Date().timeIntervalSince1970
        guard now - lastMouseNote > 0.4 else { return }
        lastMouseNote = now
        if !showControls { showControls = true }
        scheduleControlsHide()
    }

    private func scheduleControlsHide() {
        controlsTimer?.invalidate()
        // Acceptance switch: keep the control bar on screen so UI hit-testing can
        // be exercised without a real mouse hover.
        guard ProcessInfo.processInfo.environment["OPENFUSE_FORCE_CONTROLS"] != "1" else { return }
        guard !isPaused else { return }
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 3.2, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isPaused, !self.isScrubbing else { return }
                self.showControls = false
            }
        }
    }

    func toggleFullScreen() {
        NSApp.keyWindow?.toggleFullScreen(nil)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
