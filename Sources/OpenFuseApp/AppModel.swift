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
    case library(LibraryWork)
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
    @Published var showAddJellyfin = false
    @Published var jellyfinSources: [JellyfinSource] = []
    @Published var libraryWorks: [LibraryWork] = []
    @Published var libraryGroups: [LibraryGroup] = []
    @Published var libraryWorkCount = 0
    @Published var libraryEpisodeCount = 0
    @Published var isScanningLibrary = false
    @Published var libraryStatus: String?
    @Published var librarySearch = ""

    let supportDirectory: URL
    let store: PlaybackStore
    let sourceStore: SourceStore
    let jellyfinStore: JellyfinSourceStore
    let libraryStore: LibraryStore
    private var sessionJellyfinTokens: [String: String] = [:]

    init(supportDirectory: URL? = nil) {
        let directory = supportDirectory ?? Self.defaultSupportDirectory()
        self.supportDirectory = directory
        do {
            self.store = try PlaybackStore(directory: directory)
            self.sourceStore = try SourceStore(directory: directory)
            self.jellyfinStore = try JellyfinSourceStore(directory: directory)
            self.libraryStore = try LibraryStore(directory: directory)
        } catch {
            fatalError("cannot open OpenFuse store: \(error)")
        }
        self.sources = sourceStore.sources
        self.jellyfinSources = jellyfinStore.sources
        refreshRecent()
        reloadLibrary()
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

    private func startPlayer(with item: MediaItem, serverStart: Double = 0) {
        if let current = player {
            current.stopAndClose()
        }
        let record = store.record(forPath: item.fingerprint.resumeKey)
        let localStart = record.flatMap { ResumePolicy.resumePosition(for: $0) } ?? 0
        let startAt = max(localStart, serverStart)
        let model = PlayerModel(item: item, startAt: startAt, store: store)
        model.onClose = { [weak self] in
            self?.player = nil
            self?.route = .home
            self?.browsingSource = nil
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
        return CredentialStore.load(account: source.id)
    }

    func webdavClient(for source: WebDAVSource) -> WebDAVClient? {
        guard let password = password(for: source) else { return nil }
        return WebDAVClient(source: source, password: password)
    }

    @discardableResult
    func addSource(name: String, urlText: String, username: String, password: String) async -> WebDAVSource? {
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
            if !usesEnvironmentPassword {
                do {
                    try CredentialStore.save(password: password, account: source.id)
                } catch {
                    keychainError = error
                }
            }
            try sourceStore.upsert(source)
            sources = sourceStore.sources
            if let keychainError {
                statusMessage = "来源已保存，但密码写入 Keychain 失败：\(keychainError.localizedDescription)"
            } else if usesEnvironmentPassword {
                statusMessage = "已添加 \(source.name)（密码来自环境变量，未写入 Keychain）"
            } else {
                statusMessage = "已添加 \(source.name)，根目录 \(entries.count) 项"
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
        player?.stopAndClose()
        player = nil
        route = .home
        refreshRecent()
    }

    func resume(_ record: PlaybackRecord) {
        if record.sourceKind == "jellyfin",
           let sourceID = record.sourceID,
           let source = jellyfinSources.first(where: { $0.id == sourceID }) {
            let parts = (record.remotePath ?? "").split(separator: "|", maxSplits: 1).map(String.init)
            guard let itemID = parts.first, !itemID.isEmpty else { return }
            let mediaID = parts.count > 1 ? parts[1] : nil
            Task { await openJellyfinItem(source: source, itemID: itemID, preferredMediaSourceID: mediaID) }
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
        if let override = ProcessInfo.processInfo.environment["OPENFUSE_JELLYFIN_TOKEN"], !override.isEmpty {
            return override
        }
        if let cached = sessionJellyfinTokens[source.id] { return cached }
        return CredentialStore.load(account: source.id, service: "com.openfuse.jellyfin")
    }

    func addJellyfinSource(name: String, urlText: String, username: String, password: String) async -> JellyfinSource? {
        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else {
            statusMessage = "服务器地址需要是 http:// 或 https://"
            return nil
        }
        var source = JellyfinSource(name: name.isEmpty ? url.host ?? "Jellyfin" : name, baseURL: url, username: username)
        do {
            let session = try await JellyfinClient.authenticate(source: source, password: password)
            source.userID = session.userID
            source.serverID = session.serverID
            let client = JellyfinClient(source: source, token: session.accessToken)
            let views = try await client.views()
            sessionJellyfinTokens[source.id] = session.accessToken
            let usesEnvironment = ProcessInfo.processInfo.environment["OPENFUSE_JELLYFIN_PASSWORD"] != nil
                || ProcessInfo.processInfo.environment["OPENFUSE_JELLYFIN_TOKEN"] != nil
            if !usesEnvironment {
                try? CredentialStore.save(password: session.accessToken, account: source.id, service: "com.openfuse.jellyfin")
            }
            try jellyfinStore.upsert(source)
            jellyfinSources = jellyfinStore.sources
            statusMessage = "已添加 \(source.name)，共 \(views.count) 个媒体库"
            return source
        } catch {
            statusMessage = error.localizedDescription
            return nil
        }
    }

    func removeJellyfinSource(_ source: JellyfinSource) {
        try? jellyfinStore.remove(id: source.id)
        CredentialStore.delete(account: source.id, service: "com.openfuse.jellyfin")
        sessionJellyfinTokens.removeValue(forKey: source.id)
        jellyfinSources = jellyfinStore.sources
        if case .jellyfinBrowser(let browsing) = route, browsing.id == source.id {
            route = .home
        }
    }

    func browseJellyfin(_ source: JellyfinSource) {
        route = .jellyfinBrowser(source)
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
            let subtitles = MediaItem.serverSubtitles(source: source, mediaSource: mediaSource, token: token)
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
            startPlayer(with: mediaItem, serverStart: JellyfinTicks.seconds(item.userData?.playbackPositionTicks))
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    // MARK: - Media library

    func reloadLibrary() {
        do {
            libraryWorks = try libraryStore.works()
            rebuildLibraryGroups()
            let counts = try libraryStore.counts()
            libraryWorkCount = libraryGroups.count
            libraryEpisodeCount = libraryGroups.reduce(0) { $0 + $1.primary.episodeCount }
        } catch {
            libraryStatus = error.localizedDescription
        }
    }

    func scanLocalFolder(_ url: URL) async {
        await performLocalScan(url)
    }

    private func performLocalScan(_ url: URL) async {
        isScanningLibrary = true
        libraryStatus = "正在扫描 \(url.lastPathComponent)…"
        do {
            let scanned = try await Task.detached(priority: .userInitiated) {
                try LibraryScanner.scanLocal(directory: url)
            }.value
            let enriched = await enrichWithTMDB(scanned)
            try libraryStore.replace(source: enriched.library)
            reloadLibrary()
            let counts = (try? libraryStore.counts()) ?? (works: 0, episodes: 0)
            let tmdbMatched = (try? libraryStore.works())?.filter { $0.poster?.hasPrefix("remote:") == true }.count ?? 0
            libraryStatus = "已扫描 \(scanned.sourceName)：\(counts.works) 个作品" +
                (tmdbMatched > 0 ? "，TMDB 匹配 \(tmdbMatched)" : "")
        } catch {
            libraryStatus = "扫描失败：\(error.localizedDescription)"
        }
        isScanningLibrary = false
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

    func scanJellyfinSource(_ source: JellyfinSource) async {
        guard let client = jellyfinClient(for: source) else {
            libraryStatus = "缺少 \(source.name) 的登录令牌"
            return
        }
        isScanningLibrary = true
        libraryStatus = "正在扫描 Jellyfin：\(source.name)…"
        do {
            let scanned = try await LibraryScanner.scanJellyfin(source: source, client: client)
            try libraryStore.replace(source: scanned)
            reloadLibrary()
            let counts = (try? libraryStore.counts()) ?? (works: 0, episodes: 0)
            libraryStatus = "Jellyfin \(source.name)：\(counts.works) 个作品"
        } catch {
            libraryStatus = "Jellyfin 扫描失败：\(error.localizedDescription)"
        }
        isScanningLibrary = false
    }

    func scanWebDAVSource(_ source: WebDAVSource) async {
        guard let client = webdavClient(for: source) else {
            libraryStatus = "缺少 \(source.name) 的密码"
            return
        }
        isScanningLibrary = true
        libraryStatus = "正在扫描 WebDAV：\(source.name)…"
        do {
            let scanned = try await LibraryScanner.scanWebDAV(source: source, client: client)
            let enriched = await enrichWithTMDB(scanned)
            try libraryStore.replace(source: enriched.library)
            reloadLibrary()
            let counts = (try? libraryStore.counts()) ?? (works: 0, episodes: 0)
            let tmdbMatched = (try? libraryStore.works())?.filter { $0.poster?.hasPrefix("remote:") == true }.count ?? 0
            libraryStatus = "WebDAV \(source.name)：\(counts.works) 个作品" +
                (tmdbMatched > 0 ? "，TMDB 匹配 \(tmdbMatched)" : "")
        } catch {
            libraryStatus = "WebDAV 扫描失败：\(error.localizedDescription)"
        }
        isScanningLibrary = false
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
        let groups = Dictionary(grouping: libraryWorks, by: \.mergeKey)
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
        case "jellyfin": return 3
        case "local": return 2
        case "webdav": return 1
        default: return 0
        }
    }

    func group(for work: LibraryWork) -> LibraryGroup? {
        libraryGroups.first { $0.key == work.mergeKey }
    }

    func findWork(matching query: String) -> LibraryWork? {
        if let direct = libraryWorks.first(where: { $0.id == query }) { return direct }
        return libraryGroups.first {
            $0.primary.title.localizedCaseInsensitiveContains(query)
                || $0.works.contains { $0.title.localizedCaseInsensitiveContains(query) }
        }?.primary
    }

    @discardableResult
    func playLibraryEpisode(id: String) -> Bool {
        for work in libraryWorks {
            let seasons = librarySeasons(workID: work.id)
            if seasons.isEmpty {
                if let episode = libraryEpisodes(workID: work.id).first(where: { $0.id == id }) {
                    playLibrary(work: work, episode: episode)
                    return true
                }
            } else {
                for season in seasons {
                    if let episode = libraryEpisodes(workID: work.id, seasonID: season.id).first(where: { $0.id == id }) {
                        playLibrary(work: work, episode: episode)
                        return true
                    }
                }
            }
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
        ]
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
                            ["id": version.id, "name": version.name, "fileURL": version.fileURL ?? "", "mediaSourceID": version.mediaSourceID ?? ""]
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

    func playLibrary(work: LibraryWork, episode: LibraryEpisode, version: LibraryVersion? = nil) {
        let version = version ?? libraryVersions(itemID: episode.id).first
        switch work.sourceKind {
        case "jellyfin":
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

    func captureUI(to url: URL) {
        guard let window = NSApp.windows.first, let view = window.contentView else { return }
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
            "audioDevice": player.engine.getPropertyString("audio-device") ?? "",
            "currentAO": player.engine.getPropertyString("current-ao") ?? "",
            "currentVO": player.engine.getPropertyString("current-vo") ?? "",
            "isFullScreen": NSApp.keyWindow?.styleMask.contains(.fullScreen) ?? false,
            "windowFrame": NSStringFromRect(NSApp.keyWindow?.frame ?? .zero),
            "videoOutParams": player.engine.getPropertyString("video-out-params") ?? "",
            "selectedSubtitle": player.selectedSubtitleID ?? "off",
            "selectedAudio": player.selectedAudioID ?? "default",
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
    private var hasReportedStop = false
    private var hasReportedStart = false

    init(item: MediaItem, startAt: Double, store: PlaybackStore) {
        self.item = item
        self.initialPosition = startAt
        self.store = store
        self.catalog = item.subtitles
        self.engine = MPVEngine(httpHeaders: item.httpHeaders)
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
        guard !didAddExternalSubtitles else { return }
        didAddExternalSubtitles = true
        for track in catalog where track.source == .external {
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
        let externalCatalog = catalog.filter { $0.source == .external }
        let loadedExternal = subtitleTracks.filter { $0.source == .external && $0.engineID != nil }
        let hasSelectable = subtitleTracks.contains { $0.engineID != nil }
        if !hasSelectable, selectionAttempts < 20 {
            selectionAttempts += 1
            scheduleInitialSelection(after: 0.4)
            return
        }
        if !externalCatalog.isEmpty, loadedExternal.count < externalCatalog.count, selectionAttempts < 20 {
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

    func setAudioLayout(_ layout: String) {
        engine.setAudioChannels(layout)
    }

    func setSpeed(_ speed: Double) {
        engine.setSpeed(speed)
    }

    func saveProgress(finished: Bool? = nil) {
        guard duration > 0 else { return }
        reportJellyfinProgress()
        let resolvedFinished = finished ?? (hasFinished || ResumePolicy.isFinished(position: position, duration: duration))
        store.update(
            fingerprint: fingerprint,
            duration: duration,
            position: position,
            displayTitle: title,
            audioTrackID: selectedAudioID,
            subtitleTrackID: selectedSubtitleID,
            finished: resolvedFinished,
            sourceKind: item.sourceKind,
            sourceID: item.sourceID,
            remotePath: item.remotePath,
            remoteURL: item.isRemote ? item.playbackURL.absoluteString : nil
        )
    }

    private func finishPlayback() {
        hasFinished = true
        saveProgress(finished: true)
        reportJellyfinStop(wait: false)
        onFinished?()
        showControls = true
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
        let current = position
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
        let current = position
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
