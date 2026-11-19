import Foundation

/// Everything a playback session needs. Local files and remote HTTP streams
/// differ only in the URL, credentials and how subtitles were discovered.
public struct MediaItem: Sendable {
    public enum Origin: Hashable, Sendable {
        case local(URL)
        case webdav(sourceID: String, path: String, url: URL)

        public var isRemote: Bool {
            if case .webdav = self { return true }
            return false
        }
    }

    public var title: String
    public var playbackURL: URL
    public var fingerprint: MediaFingerprint
    public var subtitles: [SubtitleTrack]
    public var httpHeaders: [String]
    public var origin: Origin
    public var sourceName: String?

    public var isRemote: Bool { origin.isRemote }

    public var sourceKind: String? {
        switch origin {
        case .local: return "local"
        case .webdav: return "webdav"
        }
    }

    public var sourceID: String? {
        if case .webdav(let sourceID, _, _) = origin { return sourceID }
        return nil
    }

    public var remotePath: String? {
        if case .webdav(_, let path, _) = origin { return path }
        return nil
    }

    public init(
        title: String,
        playbackURL: URL,
        fingerprint: MediaFingerprint,
        subtitles: [SubtitleTrack],
        httpHeaders: [String] = [],
        origin: Origin,
        sourceName: String? = nil
    ) {
        self.title = title
        self.playbackURL = playbackURL
        self.fingerprint = fingerprint
        self.subtitles = subtitles
        self.httpHeaders = httpHeaders
        self.origin = origin
        self.sourceName = sourceName
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
