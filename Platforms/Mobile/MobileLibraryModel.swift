import AVFoundation
import Foundation
import OpenFuseData

struct MobilePlaybackItem: Identifiable, Hashable {
    var id: String { url.absoluteString }
    var url: URL
    var title: String
    var subtitle: String?
    var fingerprint: MediaFingerprint
    var resumePosition: TimeInterval?
    var sourceKind: String
    var sourceID: String
    var remotePath: String?
    var remoteURL: String?
    var httpHeaders: [String: String] = [:]
    var sidecarSubtitles: [SubtitleTrack] = []
    var serverAudioLabel: String?
    var serverSubtitleLabel: String?
}

@MainActor
final class MobileLibraryModel: ObservableObject {
    @Published var works: [LibraryWork] = []
    @Published var groups: [LibraryGroup] = []
    @Published var recent: [PlaybackRecord] = []
    @Published var status: String?
    @Published var syncStatus: String?
    @Published var syncURLText = ""
    @Published var syncTokenInput = ""
    @Published var syncCAPath: String?
    @Published var syncBusy = false
    @Published var isWorking = false
    @Published var webdavSources: [WebDAVSource] = []
    @Published var jellyfinSources: [JellyfinSource] = []

    let supportDirectory: URL
    let autoplaySample = ProcessInfo.processInfo.arguments.contains("--autoplay-sample")
        || ProcessInfo.processInfo.environment["OPENFUSE_AUTOPLAY"] == "1"
    private let libraryStore: LibraryStore
    private let playbackStore: PlaybackStore
    private let sourceStore: SourceStore
    private let jellyfinStore: JellyfinSourceStore
    private var ephemeralPasswords: [String: String] = [:]
    private var ephemeralTokens: [String: String] = [:]
    private var lastSyncAt = Date.distantPast
    private var syncURL: URL? {
        if let raw = ProcessInfo.processInfo.environment["OPENFUSE_SYNC_URL"],
           let url = URL(string: raw) { return url }
        return URL(string: UserDefaults.standard.string(forKey: "openfuse.sync.url") ?? "")
    }
    private var syncToken: String? {
        if let token = ProcessInfo.processInfo.environment["OPENFUSE_SYNC_TOKEN"], !token.isEmpty {
            return token
        }
        return CredentialStore.load(account: "sync-token", service: "com.openfuse.sync")
    }
    private var effectiveSyncCAPath: String? {
        ProcessInfo.processInfo.environment["OPENFUSE_SYNC_CA"] ?? syncCAPath
    }

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        supportDirectory = base.appendingPathComponent("OpenFuse", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            libraryStore = try LibraryStore(directory: supportDirectory)
            playbackStore = try PlaybackStore(directory: supportDirectory)
            sourceStore = try SourceStore(directory: supportDirectory)
            jellyfinStore = try JellyfinSourceStore(directory: supportDirectory)
        } catch {
            fatalError("OpenFuse mobile store init failed: \(error)")
        }
        webdavSources = sourceStore.sources
        jellyfinSources = jellyfinStore.sources
        syncURLText = ProcessInfo.processInfo.environment["OPENFUSE_SYNC_URL"]
            ?? UserDefaults.standard.string(forKey: "openfuse.sync.url")
            ?? ""
        syncCAPath = UserDefaults.standard.string(forKey: "openfuse.sync.ca")
        seedBundledSampleIfNeeded()
        reload()
        Task { await syncProgress(force: true) }
    }

    var countsText: String {
        "\(works.count) 个作品 · \(works.reduce(0) { $0 + $1.episodeCount }) 集"
    }

    func reload() {
        do {
            works = try libraryStore.works()
            let grouped = Dictionary(grouping: works, by: \.mergeKey)
            groups = grouped.map { key, values in
                let sorted = values.sorted {
                    sourceRank($0.sourceKind) == sourceRank($1.sourceKind)
                        ? $0.episodeCount > $1.episodeCount
                        : sourceRank($0.sourceKind) < sourceRank($1.sourceKind)
                }
                return LibraryGroup(id: sorted[0].id, key: key, primary: sorted[0], works: sorted)
            }
            .sorted { $0.primary.sortTitle.localizedStandardCompare($1.primary.sortTitle) == .orderedAscending }
            recent = playbackStore.recentlyPlayed(limit: 12)
        } catch {
            status = "读取媒体库失败：\(error.localizedDescription)"
        }
    }

    func resumePosition(for work: LibraryWork) -> TimeInterval? {
        guard let item = playbackItem(for: work) else { return nil }
        guard let record = playbackStore.record(forPath: item.fingerprint.resumeKey) else { return nil }
        return ResumePolicy.resumePosition(for: record)
    }

    func progress(for work: LibraryWork) -> Double? {
        guard let item = playbackItem(for: work),
              let record = playbackStore.record(forPath: item.fingerprint.resumeKey),
              record.duration > 0 else { return nil }
        guard !record.isFinished else { return 1 }
        return min(max(record.position / record.duration, 0), 1)
    }

    func remotePlaybackItem(for work: LibraryWork, episode: LibraryEpisode? = nil) async -> MobilePlaybackItem? {
        guard let episode = episode ?? episodes(for: work.id).first,
              let source = jellyfinSources.first(where: { $0.id == work.sourceID }),
              let token = jellyfinToken(for: source) else { return nil }
        guard let itemID = episode.serverID ?? episode.remotePath else { return nil }
        let client = JellyfinClient(source: source, token: token)
        guard let info = try? await client.playbackInfo(itemID: itemID),
              !info.mediaSources.isEmpty else { return nil }
        let versions = (try? libraryStore.versions(itemID: episode.id)) ?? []
        let preferredID = versions.first?.mediaSourceID
        let media = info.mediaSources.first(where: { $0.id == preferredID }) ?? info.mediaSources[0]
        let container = (media.container ?? "").lowercased()
        let containers = Set(container.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        let directContainer = !containers.isDisjoint(with: ["mp4", "m4v", "mov"])
        let url: URL?
        var headers: [String: String] = [:]
        if directContainer,
           let stream = client.streamURL(itemID: itemID, mediaSource: media),
           var components = URLComponents(url: stream, resolvingAgainstBaseURL: false) {
            var query = components.queryItems ?? []
            query.append(URLQueryItem(name: "api_key", value: token))
            components.queryItems = query
            url = components.url
            headers = [
                "X-Emby-Token": token,
                "Authorization": "MediaBrowser Token=\"\(token)\"",
            ]
        } else {
            url = client.hlsURL(itemID: itemID, mediaSourceID: media.id, token: token)
                ?? client.streamURL(itemID: itemID, mediaSource: media)
            headers = [
                "X-Emby-Token": token,
                "Authorization": "MediaBrowser Token=\"\(token)\"",
            ]
        }
        guard let url else { return nil }
        var sidecars: [SubtitleTrack] = []
        let cache = supportDirectory.appendingPathComponent("SubtitleCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        for stream in media.mediaStreams ?? [] where stream.type == "Subtitle" && stream.isExternal == true {
            // Jellyfin 12 omits DeliveryUrl for sidecar subtitles; the stream
            // endpoint still serves them (same fallback the Mac app uses), and
            // it is what makes 简体/繁體 selectable in the mobile player.
            let codec = stream.codec ?? "ass"
            let delivery = stream.deliveryURL
                ?? "/Videos/\(itemID)/\(media.id)/Subtitles/\(stream.index)/Stream.\(codec)"
            guard var components = URLComponents(
                url: URL(string: delivery, relativeTo: source.normalizedBaseURL)?.absoluteURL ?? source.normalizedBaseURL,
                resolvingAgainstBaseURL: false
            ) else { continue }
            var query = components.queryItems ?? []
            query.append(URLQueryItem(name: "api_key", value: token))
            components.queryItems = query
            guard let remote = components.url else { continue }
            var request = URLRequest(url: remote)
            request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
            request.setValue("MediaBrowser Token=\"\(token)\"", forHTTPHeaderField: "Authorization")
            guard let (data, _) = try? await URLSession.shared.data(for: request), !data.isEmpty else { continue }
            let suffix = codec.isEmpty ? "srt" : codec.lowercased()
            let target = cache.appendingPathComponent(
                LibraryID.hash("\(itemID)|subtitle|\(stream.index)") + "." + suffix
            )
            try? data.write(to: target, options: .atomic)
            sidecars.append(
                SubtitleTrack(
                    id: "jellyfin-ext:\(itemID):\(stream.index)",
                    displayName: SubtitleLabel.make(
                        language: LanguageTag.normalizeISO(stream.language),
                        format: SubtitleFormat(fileExtension: suffix),
                        forced: stream.isForced ?? false,
                        includeFormat: true
                    ),
                    language: LanguageTag.normalizeISO(stream.language),
                    format: SubtitleFormat(fileExtension: suffix),
                    source: .downloaded,
                    url: target
                )
            )
        }
        let key = "jellyfin://\(source.id)/\(itemID)/\(media.id)"
        let fingerprint = MediaFingerprint(path: key, fileSize: 0, modifiedAt: nil)
        if playbackStore.record(forPath: key) == nil, syncURL != nil {
            await syncProgress(force: true)
        }
        let record = playbackStore.record(forPath: key)
        if ProcessInfo.processInfo.environment["OPENFUSE_REPORT_RESUME"] == "1" {
            let report: [String: Any] = [
                "key": key,
                "position": record?.position ?? 0,
                "duration": record?.duration ?? 0,
                "resume": record.flatMap(ResumePolicy.resumePosition(for:)) ?? 0,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: report) {
                try? data.write(to: supportDirectory.appendingPathComponent("autoplay-resume.json"))
            }
        }
        let audioStream = media.mediaStreams?.first(where: { $0.type == "Audio" && $0.isDefault == true })
            ?? media.mediaStreams?.first(where: { $0.type == "Audio" })
        let audioLabel = audioStream.map { stream in
            let base = stream.displayTitle ?? "\(stream.codec?.uppercased() ?? "AUDIO") \(stream.channels ?? 2)ch"
            return directContainer ? base : base + "（转码 AAC）"
        }
        let subtitleStream = media.mediaStreams?.first(where: { $0.type == "Subtitle" && $0.isDefault == true })
            ?? media.mediaStreams?.first(where: { $0.type == "Subtitle" })
        let subtitleLabel = subtitleStream.flatMap { stream in
            (stream.displayTitle ?? "服务器字幕") + "（服务器）"
        }
        return MobilePlaybackItem(
            url: url,
            title: work.title,
            subtitle: episode.episodeLabel,
            fingerprint: fingerprint,
            resumePosition: record.flatMap(ResumePolicy.resumePosition(for:)),
            sourceKind: "jellyfin",
            sourceID: source.id,
            remotePath: "\(itemID)|\(media.id)",
            remoteURL: url.absoluteString,
            httpHeaders: headers,
            sidecarSubtitles: sidecars,
            serverAudioLabel: audioLabel,
            serverSubtitleLabel: subtitleLabel
        )
    }

    func playbackItemAsync(for work: LibraryWork, episode: LibraryEpisode? = nil) async -> MobilePlaybackItem? {
        guard work.sourceKind == "webdav",
              let episode = episode ?? episodes(for: work.id).first,
              let remotePath = episode.remotePath,
              let source = webdavSources.first(where: { $0.id == work.sourceID }),
              let password = ephemeralPasswords[source.id] ?? CredentialStore.load(account: source.id) else {
            if work.sourceKind == "jellyfin" {
                return await remotePlaybackItem(for: work, episode: episode)
            }
            return playbackItem(for: work)
        }
        let client = WebDAVClient(source: source, password: password)
        var localTracks: [SubtitleTrack] = []
        let directory = (remotePath as NSString).deletingLastPathComponent
        if let siblings = try? await client.list(path: directory) {
            let video = RemoteEntry(
                path: remotePath,
                name: (remotePath as NSString).lastPathComponent,
                url: client.url(for: remotePath),
                isDirectory: false
            )
            let tracks = WebDAVClient.subtitleTracks(for: video, siblings: siblings)
            let cache = supportDirectory.appendingPathComponent("SubtitleCache", isDirectory: true)
            try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            for track in tracks {
                let remoteSubtitle = String(track.id.dropFirst("remote:".count))
                guard let (data, _) = try? await client.fetch(path: remoteSubtitle), !data.isEmpty else { continue }
                let ext = (remoteSubtitle as NSString).pathExtension.lowercased()
                let target = cache.appendingPathComponent(LibraryID.hash(remoteSubtitle) + "." + (ext.isEmpty ? "srt" : ext))
                try? data.write(to: target, options: .atomic)
                var local = track
                local.id = "remote:" + remoteSubtitle
                local.url = target
                local.source = .downloaded
                localTracks.append(local)
            }
        }
        var item = playbackItem(work: work, episode: episode)
        item?.sidecarSubtitles = localTracks
        return item
    }

    func episodes(for workID: String) -> [LibraryEpisode] {
        (try? libraryStore.episodes(workID: workID)) ?? []
    }

    func playbackItem(for work: LibraryWork) -> MobilePlaybackItem? {
        guard let episode = (try? libraryStore.episodes(workID: work.id))?.first else { return nil }
        return playbackItem(work: work, episode: episode)
    }

    func playbackItem(work: LibraryWork, episode: LibraryEpisode) -> MobilePlaybackItem? {
        let versions = (try? libraryStore.versions(itemID: episode.id)) ?? []
        if let file = versions.first?.fileURL ?? episode.fileURL {
            let url = URL(string: file) ?? URL(fileURLWithPath: file)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let fingerprint = (try? MediaFingerprint(url: url))
                ?? MediaFingerprint(path: url.path, fileSize: 0, modifiedAt: nil)
            let record = playbackStore.record(forPath: fingerprint.resumeKey)
            return MobilePlaybackItem(
                url: url,
                title: work.title,
                subtitle: episode.episodeLabel,
                fingerprint: fingerprint,
                resumePosition: record.flatMap(ResumePolicy.resumePosition(for:)),
                sourceKind: work.sourceKind,
                sourceID: work.sourceID,
                remotePath: episode.remotePath,
                remoteURL: nil,
                sidecarSubtitles: SubtitleCatalog.discover(for: url)
            )
        }

        if episode.sourceKind == "webdav",
           let path = episode.remotePath,
           let source = webdavSources.first(where: { $0.id == work.sourceID }),
           let password = ephemeralPasswords[source.id] ?? CredentialStore.load(account: source.id) {
            let client = WebDAVClient(source: source, password: password)
            let url = client.url(for: path)
            let key = "webdav://\(source.id)/\(path)"
            let fingerprint = MediaFingerprint(path: key, fileSize: 0, modifiedAt: nil)
            let record = playbackStore.record(forPath: key)
            let credential = Data("\(source.username):\(password)".utf8).base64EncodedString()
            return MobilePlaybackItem(
                url: url,
                title: work.title,
                subtitle: episode.episodeLabel,
                fingerprint: fingerprint,
                resumePosition: record.flatMap(ResumePolicy.resumePosition(for:)),
                sourceKind: "webdav",
                sourceID: source.id,
                remotePath: path,
                remoteURL: url.absoluteString,
                httpHeaders: ["Authorization": "Basic \(credential)"]
            )
        }
        return nil
    }

    func recordProgress(item: MobilePlaybackItem, duration: TimeInterval, position: TimeInterval, finished: Bool? = nil) {
        guard duration > 0 else { return }
        playbackStore.update(
            fingerprint: item.fingerprint,
            duration: duration,
            position: position,
            displayTitle: item.title,
            finished: finished,
            sourceKind: item.sourceKind,
            sourceID: item.sourceID,
            remotePath: item.remotePath,
            remoteURL: item.remoteURL
        )
        recent = playbackStore.recentlyPlayed(limit: 12)
        Task { await syncProgress(force: true) }
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
            let accessing = caURL.startAccessingSecurityScopedResource()
            defer { if accessing { caURL.stopAccessingSecurityScopedResource() } }
            let target = supportDirectory.appendingPathComponent("sync-ca.pem")
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
        }
        syncTokenInput = ""
        syncStatus = "同步设置已保存"
        return true
    }

    func syncWithSettings() async {
        syncBusy = true
        defer { syncBusy = false }
        guard let syncURL else {
            syncStatus = "未配置同步地址"
            return
        }
        await runSync(transport: HTTPProgressTransport(
            url: syncURL,
            token: syncToken,
            caPath: effectiveSyncCAPath
        ))
    }

    private func runSync(transport: ProgressSyncTransport) async {
        do {
            let result = try await ProgressSyncService(store: playbackStore, transport: transport).sync()
            syncStatus = "同步：远端 \(result.remoteCount)，本地 \(result.localCount)，更新 \(result.changed)"
            recent = playbackStore.recentlyPlayed(limit: 12)
        } catch {
            syncStatus = "同步失败：\(error.localizedDescription)"
        }
    }

    func syncProgress(force: Bool = false) async {
        guard let syncURL else { return }
        if !force, Date().timeIntervalSince(lastSyncAt) < 5 { return }
        lastSyncAt = Date()
        await runSync(transport: HTTPProgressTransport(
            url: syncURL,
            token: syncToken,
            caPath: syncCAPath
        ))
    }

    func bootstrapTestSourcesIfRequested() async {
        let env = ProcessInfo.processInfo.environment
        if let urlText = env["OPENFUSE_TEST_WEBDAV_URL"],
           let user = env["OPENFUSE_TEST_WEBDAV_USER"],
           let password = env["OPENFUSE_TEST_WEBDAV_PASSWORD"],
           let url = URL(string: urlText) {
            let source = WebDAVSource(name: "测试 WebDAV", baseURL: url, username: user)
            ephemeralPasswords[source.id] = password
            try? sourceStore.upsert(source)
            webdavSources = sourceStore.sources
            try? await scanWebDAV(source)
        }
        if let urlText = env["OPENFUSE_TEST_JELLYFIN_URL"],
           let user = env["OPENFUSE_TEST_JELLYFIN_USER"],
           let password = env["OPENFUSE_TEST_JELLYFIN_PASSWORD"],
           let url = URL(string: urlText) {
            var source = JellyfinSource(name: "测试 Jellyfin", baseURL: url, username: user)
            if let session = try? await JellyfinClient.authenticate(source: source, password: password) {
                source.userID = session.userID
                source.serverID = session.serverID
                ephemeralTokens[source.id] = session.accessToken
                try? jellyfinStore.upsert(source)
                jellyfinSources = jellyfinStore.sources
                try? await scanJellyfin(source)
            }
        }
    }

    func posterURL(for work: LibraryWork) -> URL? {
        guard let parsed = PosterRef.parse(work.poster), parsed.kind == "jellyfin" else { return nil }
        let parts = parsed.value.split(separator: "|", maxSplits: 1).map(String.init)
        guard let itemID = parts.first else { return nil }
        for source in jellyfinSources {
            if let token = jellyfinToken(for: source),
               let url = JellyfinClient(source: source, token: token).imageURL(
                    itemID: itemID,
                    tag: parts.count > 1 ? parts[1] : nil
               ) {
                return url
            }
        }
        return nil
    }

    func addWebDAV(name: String, urlText: String, username: String, password: String) async {
        guard let url = URL(string: urlText) else {
            status = "WebDAV 地址无效"
            return
        }
        isWorking = true
        defer { isWorking = false }
        let source = WebDAVSource(name: name.isEmpty ? url.host ?? "WebDAV" : name, baseURL: url, username: username)
        do {
            try sourceStore.upsert(source)
            try CredentialStore.save(password: password, account: source.id)
            webdavSources = sourceStore.sources
            try await scanWebDAV(source)
        } catch {
            status = "添加 WebDAV 失败：\(error.localizedDescription)"
        }
    }

    func scanWebDAV(_ source: WebDAVSource) async throws {
        guard let password = ephemeralPasswords[source.id] ?? CredentialStore.load(account: source.id) else {
            status = "WebDAV 缺少 Keychain 密码"
            return
        }
        isWorking = true
        defer { isWorking = false }
        let client = WebDAVClient(source: source, password: password)
        let scanned = try await LibraryScanner.scanWebDAV(
            source: source,
            client: client,
            posterCacheDirectory: supportDirectory.appendingPathComponent("PosterCache", isDirectory: true)
        )
        try libraryStore.replace(source: scanned)
        reload()
        status = "WebDAV \(source.name)：\(scanned.works.count) 个作品"
    }

    func addJellyfin(name: String, urlText: String, username: String, password: String) async {
        guard let url = URL(string: urlText) else {
            status = "Jellyfin 地址无效"
            return
        }
        isWorking = true
        defer { isWorking = false }
        var source = JellyfinSource(name: name.isEmpty ? url.host ?? "Jellyfin" : name, baseURL: url, username: username)
        do {
            let session = try await JellyfinClient.authenticate(source: source, password: password)
            source.userID = session.userID
            source.serverID = session.serverID
            try jellyfinStore.upsert(source)
            try CredentialStore.save(password: session.accessToken, account: source.id, service: "com.openfuse.jellyfin")
            jellyfinSources = jellyfinStore.sources
            try await scanJellyfin(source)
        } catch {
            status = "添加 Jellyfin 失败：\(error.localizedDescription)"
        }
    }

    /// Mirrors the Mac scan policy: a transient failure (timeout / HTTP 5xx)
    /// keeps the last complete index instead of replacing it with a partial
    /// one, cancellation leaves the library untouched, and an explicit 401/403
    /// removes the source.
    func scanJellyfin(_ source: JellyfinSource) async throws {
        guard let token = jellyfinToken(for: source) else {
            status = "Jellyfin 缺少 Keychain token"
            return
        }
        isWorking = true
        defer { isWorking = false }
        let client = JellyfinClient(source: source, token: token)
        do {
            let result = try await LibraryScanner.scanJellyfin(source: source, client: client)
            if result.hasTransientFailure {
                let names = result.transientFailures.map(\.libraryName).joined(separator: "、")
                status = "Jellyfin \(source.name)：\(names) 读取不完整，已保留上次完整索引，可重试"
                return
            }
            try libraryStore.replace(source: result.library)
            reload()
            var text = "Jellyfin \(source.name)：\(result.library.works.count) 个作品"
            if !result.revokedLibraryNames.isEmpty {
                text += "，已移除无权访问的 \(result.revokedLibraryNames.joined(separator: "、"))"
            }
            status = text
        } catch LibraryScanError.cancelled {
            status = "Jellyfin 扫描已取消，媒体库保持原样"
        } catch JellyfinError.unauthorized {
            try? libraryStore.removeSource(kind: source.kind, sourceID: source.id)
            reload()
            status = "Jellyfin \(source.name)：服务器撤回了访问权限，请重新登录该来源"
        } catch {
            status = "Jellyfin 扫描失败：\(error.localizedDescription)，媒体库保持原样"
        }
    }

    func removeWebDAV(_ source: WebDAVSource) {
        try? sourceStore.remove(id: source.id)
        CredentialStore.delete(account: source.id)
        try? libraryStore.removeSource(kind: "webdav", sourceID: source.id)
        webdavSources = sourceStore.sources
        reload()
    }

    func removeJellyfin(_ source: JellyfinSource) {
        try? jellyfinStore.remove(id: source.id)
        CredentialStore.delete(account: source.id, service: "com.openfuse.jellyfin")
        try? libraryStore.removeSource(kind: "jellyfin", sourceID: source.id)
        jellyfinSources = jellyfinStore.sources
        reload()
    }

    func jellyfinToken(for source: JellyfinSource) -> String? {
        ephemeralTokens[source.id] ?? CredentialStore.load(account: source.id, service: "com.openfuse.jellyfin")
    }

    func importVideo(from url: URL) {
        isWorking = true
        defer { isWorking = false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let ext = url.pathExtension.lowercased()
        guard ["mp4", "m4v", "mov"].contains(ext) else {
            status = "移动端首版使用 AVPlayer，只支持 MP4/MOV；MKV 由 Mac 端 libmpv 播放。"
            return
        }
        let imports = documentsDirectory.appendingPathComponent("Imports", isDirectory: true)
        let folder = imports.appendingPathComponent(url.deletingPathExtension().lastPathComponent, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            let scanned = try LibraryScanner.scanLocal(directory: imports)
            try libraryStore.replace(source: scanned)
            reload()
            status = "已导入 \(url.lastPathComponent)"
        } catch {
            status = "导入失败：\(error.localizedDescription)"
        }
    }

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    private func seedBundledSampleIfNeeded() {
        guard (try? libraryStore.counts().works) == 0,
              let video = Bundle.main.url(forResource: "openfuse-mobile", withExtension: "mp4") else { return }
        let sample = documentsDirectory
            .appendingPathComponent("OpenFuse Mobile Sample (2026)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: sample, withIntermediateDirectories: true)
            let target = sample.appendingPathComponent("OpenFuse Mobile Sample.mp4")
            if !FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.copyItem(at: video, to: target)
            }
            if let poster = Bundle.main.url(forResource: "openfuse-mobile", withExtension: "jpg") {
                let posterTarget = sample.appendingPathComponent("poster.jpg")
                if !FileManager.default.fileExists(atPath: posterTarget.path) {
                    try FileManager.default.copyItem(at: poster, to: posterTarget)
                }
            }
            for suffix in ["zh-Hans", "zh-Hant"] {
                if let subtitle = Bundle.main.url(
                    forResource: "openfuse-mobile.\(suffix)",
                    withExtension: "srt"
                ) {
                    let target = sample.appendingPathComponent("OpenFuse Mobile Sample.\(suffix).srt")
                    if !FileManager.default.fileExists(atPath: target.path) {
                        try FileManager.default.copyItem(at: subtitle, to: target)
                    }
                }
            }
            let scanned = try LibraryScanner.scanLocal(directory: documentsDirectory.appendingPathComponent("OpenFuse Mobile Sample (2026)"))
            try libraryStore.replace(source: ScannedLibrary(
                sourceKind: "local", sourceID: "bundled", sourceName: "示例", works: scanned.works
            ))
        } catch {
            status = "示例入库失败：\(error.localizedDescription)"
        }
    }

    func makePlayer(for item: MobilePlaybackItem) -> (AVPlayer, AuthenticatedAssetLoader?) {
        if item.httpHeaders.isEmpty {
            return (AVPlayer(url: item.url), nil)
        }
        if item.url.scheme == "http" || item.url.scheme == "https" {
            let asset = AVURLAsset(
                url: item.url,
                options: ["AVURLAssetHTTPHeaderFieldsKey": item.httpHeaders]
            )
            return (AVPlayer(playerItem: AVPlayerItem(asset: asset)), nil)
        }
        let loader = AuthenticatedAssetLoader(url: item.url, headers: item.httpHeaders)
        let asset = loader.makeAsset()
        return (AVPlayer(playerItem: AVPlayerItem(asset: asset)), loader)
    }

    private func sourceRank(_ kind: String) -> Int {
        switch kind {
        case "jellyfin": return 0
        case "local": return 1
        default: return 2
        }
    }
}
