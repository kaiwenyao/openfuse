import Foundation

/// Everything a playback session needs. Local files and remote HTTP streams
/// differ only in the URL, credentials and how subtitles were discovered.
public struct MediaItem: Sendable {
    public enum Origin: Hashable, Sendable {
        case local(URL)
        case webdav(sourceID: String, path: String, url: URL)
        case jellyfin(sourceID: String, itemID: String, mediaSourceID: String)
        case plex(sourceID: String, partKey: String, url: URL)
        case smb(sourceID: String, path: String, cachedURL: URL)

        public var isRemote: Bool {
            switch self {
            case .local: return false
            case .webdav, .jellyfin, .plex, .smb: return true
            }
        }
    }

    public var title: String
    public var playbackURL: URL
    public var fingerprint: MediaFingerprint
    public var subtitles: [SubtitleTrack]
    public var httpHeaders: [String]
    public var origin: Origin
    public var sourceName: String?
    public var jellyfinContext: JellyfinPlaybackContext?
    public var plexContext: PlexPlaybackContext?

    public var isRemote: Bool { origin.isRemote }

    public var sourceKind: String? {
        switch origin {
        case .local: return "local"
        case .webdav: return "webdav"
        case .jellyfin:
            return jellyfinContext?.serverKind ?? "jellyfin"
        case .plex: return "plex"
        case .smb: return "smb"
        }
    }

    public var sourceID: String? {
        switch origin {
        case .webdav(let sourceID, _, _): return sourceID
        case .jellyfin(let sourceID, _, _): return sourceID
        case .plex(let sourceID, _, _): return sourceID
        case .smb(let sourceID, _, _): return sourceID
        case .local: return nil
        }
    }

    public var remotePath: String? {
        if case .webdav(_, let path, _) = origin { return path }
        if case .jellyfin(_, let itemID, let mediaSourceID) = origin {
            return "\(itemID)|\(mediaSourceID)"
        }
        if case .plex(_, let partKey, _) = origin { return partKey }
        if case .smb(_, let path, _) = origin { return path }
        return nil
    }

    public init(
        title: String,
        playbackURL: URL,
        fingerprint: MediaFingerprint,
        subtitles: [SubtitleTrack],
        httpHeaders: [String] = [],
        origin: Origin,
        sourceName: String? = nil,
        jellyfinContext: JellyfinPlaybackContext? = nil,
        plexContext: PlexPlaybackContext? = nil
    ) {
        self.title = title
        self.playbackURL = playbackURL
        self.fingerprint = fingerprint
        self.subtitles = subtitles
        self.httpHeaders = httpHeaders
        self.origin = origin
        self.sourceName = sourceName
        self.jellyfinContext = jellyfinContext
        self.plexContext = plexContext
    }

    public static func local(url: URL) throws -> MediaItem {
        let fingerprint = try MediaFingerprint(url: url)
        return MediaItem(
            title: DisplayTitle.make(from: url),
            playbackURL: url,
            fingerprint: fingerprint,
            subtitles: SubtitleCatalog.discover(for: url),
            origin: .local(url)
        )
    }

    #if os(macOS)
    public static func smb(
        source: SMBSource,
        path: String,
        title: String,
        size: Int64,
        playbackURL: URL
    ) -> MediaItem {
        MediaItem(
            title: title,
            playbackURL: playbackURL,
            fingerprint: MediaFingerprint(
                path: "smb://\(source.id)/\(path)",
                fileSize: size,
                modifiedAt: nil
            ),
            subtitles: [],
            httpHeaders: [],
            origin: .smb(sourceID: source.id, path: path, cachedURL: playbackURL),
            sourceName: source.name
        )
    }
    #endif

    public static func plex(
        source: PlexSource,
        title: String,
        ratingKey: String,
        partKey: String,
        size: Int64,
        duration: Double,
        token: String,
        url: URL,
        subtitles: [SubtitleTrack] = []
    ) -> MediaItem {
        let key = "plex://\(source.id)/\(partKey)"
        let context = PlexPlaybackContext(
            sourceID: source.id,
            baseURL: source.normalizedBaseURL,
            token: token,
            ratingKey: ratingKey,
            partKey: partKey,
            duration: duration
        )
        return MediaItem(
            title: title,
            playbackURL: url,
            fingerprint: MediaFingerprint(path: key, fileSize: size, modifiedAt: nil),
            subtitles: subtitles,
            httpHeaders: [],
            origin: .plex(sourceID: source.id, partKey: partKey, url: url),
            sourceName: source.name,
            plexContext: context
        )
    }

    public static func webdav(
        source: WebDAVSource,
        entry: RemoteEntry,
        subtitles: [SubtitleTrack],
        password: String
    ) -> MediaItem {
        let title = DisplayTitle.make(fromName: (entry.name as NSString).deletingPathExtension)
        let token = Data("\(source.username):\(password)".utf8).base64EncodedString()
        let key = "webdav://\(source.id)/\(entry.path)"
        let fingerprint = MediaFingerprint(
            path: key,
            fileSize: entry.size,
            modifiedAt: entry.modifiedAt
        )
        return MediaItem(
            title: title,
            playbackURL: entry.url,
            fingerprint: fingerprint,
            subtitles: subtitles,
            httpHeaders: source.username.isEmpty ? [] : ["Authorization: Basic \(token)"],
            origin: .webdav(sourceID: source.id, path: entry.path, url: entry.url),
            sourceName: source.name
        )
    }
}

public enum DisplayTitle {
    public static func make(from url: URL) -> String {
        make(fromName: url.deletingPathExtension().lastPathComponent)
    }

    public static func make(fromName base: String) -> String {
        var title = base.replacingOccurrences(of: ".", with: " ")
        title = title.replacingOccurrences(of: "_", with: " ")
        let noise = ["2160p", "1080p", "720p", "WEB-DL", "WEBRip", "BluRay", "HEVC", "x265", "H265", "DDP5.1", "HDR"]
        for token in noise {
            title = title.replacingOccurrences(of: token, with: "", options: .caseInsensitive)
        }
        title = title.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? base : title
    }
}


public struct JellyfinPlaybackContext: Sendable {
    public var sourceID: String
    public var serverKind: String
    public var baseURL: URL
    public var userID: String
    public var token: String
    public var itemID: String
    public var mediaSourceID: String
    public var mediaSourceName: String
    public var playSessionID: String?
    public var runtime: Double
    public var startPosition: Double
    public var mediaStreams: [JellyfinMediaStream]

    public init(
        sourceID: String,
        serverKind: String = "jellyfin",
        baseURL: URL,
        userID: String,
        token: String,
        itemID: String,
        mediaSourceID: String,
        mediaSourceName: String,
        playSessionID: String?,
        runtime: Double,
        startPosition: Double,
        mediaStreams: [JellyfinMediaStream] = []
    ) {
        self.sourceID = sourceID
        self.serverKind = serverKind
        self.baseURL = baseURL
        self.userID = userID
        self.token = token
        self.itemID = itemID
        self.mediaSourceID = mediaSourceID
        self.mediaSourceName = mediaSourceName
        self.playSessionID = playSessionID
        self.runtime = runtime
        self.startPosition = startPosition
        self.mediaStreams = mediaStreams
    }
}

public extension MediaItem {
    static func jellyfin(
        source: JellyfinSource,
        item: JellyfinItem,
        mediaSource: JellyfinMediaSource,
        playbackInfo: JellyfinPlaybackInfo,
        token: String,
        subtitles: [SubtitleTrack]
    ) -> MediaItem? {
        let client = JellyfinClient(source: source, token: token)
        guard let url = client.streamURL(itemID: item.id, mediaSource: mediaSource) else { return nil }
        let title = item.name
        let runtime = JellyfinTicks.seconds(mediaSource.runTimeTicks ?? item.runTimeTicks)
        let start = JellyfinTicks.seconds(item.userData?.playbackPositionTicks)
        let context = JellyfinPlaybackContext(
            sourceID: source.id,
            serverKind: source.kind,
            baseURL: source.normalizedBaseURL,
            userID: source.userID ?? "",
            token: token,
            itemID: item.id,
            mediaSourceID: mediaSource.id,
            mediaSourceName: mediaSource.name,
            playSessionID: playbackInfo.playSessionID,
            runtime: runtime,
            startPosition: start,
            mediaStreams: mediaSource.mediaStreams ?? []
        )
        let fingerprint = MediaFingerprint(
            path: "\(source.kind)://\(source.id)/\(item.id)/\(mediaSource.id)",
            fileSize: 0,
            modifiedAt: nil
        )
        return MediaItem(
            title: title,
            playbackURL: url,
            fingerprint: fingerprint,
            subtitles: subtitles,
            httpHeaders: ["X-Emby-Token: \(token)"],
            origin: .jellyfin(sourceID: source.id, itemID: item.id, mediaSourceID: mediaSource.id),
            sourceName: source.name,
            jellyfinContext: context
        )
    }

    static func serverSubtitles(
        source: JellyfinSource,
        mediaSource: JellyfinMediaSource,
        token: String
    ) -> [SubtitleTrack] {
        var tracks: [SubtitleTrack] = []
        for stream in mediaSource.mediaStreams ?? [] where stream.type == "Subtitle" && stream.isExternal == true {
            guard let delivery = stream.deliveryURL else { continue }
            guard let deliveryURL = URL(string: delivery, relativeTo: source.normalizedBaseURL),
                  var components = URLComponents(url: deliveryURL, resolvingAgainstBaseURL: false)
            else { continue }
            var query = components.queryItems ?? []
            query.append(URLQueryItem(name: "api_key", value: token))
            components.queryItems = query
            guard let url = components.url else { continue }
            let language = LanguageTag.normalizeISO(stream.language)
            let format = SubtitleFormat(fileExtension: (delivery as NSString).pathExtension)
            tracks.append(
                SubtitleTrack(
                    id: "jellyfin-sub:\(source.id):\(stream.index)",
                    displayName: stream.displayTitle ?? SubtitleLabel.make(language: language, format: format, forced: stream.isForced ?? false, includeFormat: true),
                    language: language,
                    format: format,
                    source: .server,
                    url: url,
                    isForced: stream.isForced ?? false
                )
            )
        }
        return tracks
    }
}


public struct PlexPlaybackContext: Sendable {
    public var sourceID: String
    public var baseURL: URL
    public var token: String
    public var ratingKey: String
    public var partKey: String
    public var duration: Double
}
