import Foundation

/// One playable file in the current video's folder. `displayTitle` is the
/// episode/movie title when known; `subtitle` carries the show name, year,
/// resolution or version needed to tell two versions apart.
public struct FolderVideo: Identifiable, Hashable, Sendable {
    public var id: String
    public var displayTitle: String
    public var subtitle: String
    public var episodeLabel: String?
    public var seasonNumber: Int?
    public var episodeNumber: Int?
    public var year: Int?
    public var resolution: String?
    public var versionLabel: String?
    public var fileName: String
    public var path: String
    public var fileURL: URL?
    public var remoteEntry: RemoteEntry?
    public var sourceKind: String
    public var sourceID: String?
    public var jellyfinItemID: String?
    public var jellyfinMediaSourceID: String?
    public var thumbnailURL: String?
    public var overview: String?

    public var rowTitle: String {
        if let episodeLabel {
            return "\(episodeLabel) — \(displayTitle)"
        }
        return displayTitle
    }

    public init(
        id: String,
        displayTitle: String,
        subtitle: String,
        episodeLabel: String? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        year: Int? = nil,
        resolution: String? = nil,
        versionLabel: String? = nil,
        fileName: String,
        path: String,
        fileURL: URL? = nil,
        remoteEntry: RemoteEntry? = nil,
        sourceKind: String,
        sourceID: String? = nil,
        jellyfinItemID: String? = nil,
        jellyfinMediaSourceID: String? = nil,
        thumbnailURL: String? = nil,
        overview: String? = nil
    ) {
        self.id = id
        self.displayTitle = displayTitle
        self.subtitle = subtitle
        self.episodeLabel = episodeLabel
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.year = year
        self.resolution = resolution
        self.versionLabel = versionLabel
        self.fileName = fileName
        self.path = path
        self.fileURL = fileURL
        self.remoteEntry = remoteEntry
        self.sourceKind = sourceKind
        self.sourceID = sourceID
        self.jellyfinItemID = jellyfinItemID
        self.jellyfinMediaSourceID = jellyfinMediaSourceID
        self.thumbnailURL = thumbnailURL
        self.overview = overview
    }
}

/// Filename/folder parsing shared by local, WebDAV and Jellyfin lists.
public enum VideoNaming {
    public struct Parsed: Sendable {
        public var showTitle: String?
        public var episodeTitle: String?
        public var season: Int?
        public var episode: Int?
        public var year: Int?
        public var resolution: String?
        public var versionLabel: String?
        public var movieTitle: String?
    }

    public static let videoExtensions: Set<String> = [
        "mkv", "mp4", "m4v", "mov", "ts", "m2ts", "webm", "avi", "flv", "wmv", "iso", "mpg", "mpeg",
    ]

    public static func parse(fileName: String, parentFolder: String) -> Parsed {
        let base = (fileName as NSString).deletingPathExtension
        var parsed = Parsed()
        parsed.resolution = resolution(in: base)
        parsed.versionLabel = versionLabel(in: base)

        let episodePattern = #"(?i)(?:^|[^A-Za-z0-9])S(\d{1,2})[ ._-]?E(\d{1,3})(?:[^0-9]|$)"#
        let altPattern = #"(?i)(?:^|[^0-9])(\d{1,2})x(\d{2,3})(?:[^0-9]|$)"#
        if let match = firstMatch(episodePattern, in: base),
           let season = Int(match[1]), let episode = Int(match[2]) {
            parsed.season = season
            parsed.episode = episode
            parsed.episodeTitle = episodeTitle(in: base, after: match[0])
            parsed.showTitle = showName(parentFolder: parentFolder)
        } else if let match = firstMatch(altPattern, in: base),
                  let season = Int(match[1]), let episode = Int(match[2]) {
            parsed.season = season
            parsed.episode = episode
            parsed.episodeTitle = episodeTitle(in: base, after: match[0])
            parsed.showTitle = showName(parentFolder: parentFolder)
        }

        parsed.year = year(in: base) ?? year(in: parentFolder)
        if parsed.season == nil {
            parsed.movieTitle = cleanedTitle(base)
        }
        return parsed
    }

    public static func showName(parentFolder: String) -> String {
        let path = parentFolder as NSString
        var name = path.lastPathComponent
        if name.range(of: #"(?i)^(?:season|s)[ ._-]?\d{1,2}$"#, options: .regularExpression) != nil {
            name = (parentFolder as NSString).deletingLastPathComponent
            name = (name as NSString).lastPathComponent
        }
        name = name.replacingOccurrences(of: #"\s*\((19|20)\d{2}\)\s*$"#, with: "", options: .regularExpression)
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func seasonNumber(fromFolder name: String) -> Int? {
        guard let match = firstMatch(#"(?i)^(?:season|s)[ ._-]?(\d{1,2})$"#, in: name) else { return nil }
        return Int(match[1])
    }

    static func resolution(in text: String) -> String? {
        let lowered = text.lowercased()
        for value in ["2160p", "1080p", "720p", "576p", "480p"] where lowered.contains(value) {
            return value
        }
        if lowered.contains("4k") || lowered.contains("uhd") { return "2160p" }
        return nil
    }

    static func versionLabel(in text: String) -> String? {
        let lowered = text.lowercased()
        let tags = [
            "director's cut": "导演剪辑版", "directors cut": "导演剪辑版",
            "extended": "加长版", "remastered": "重制版", "repack": "REPACK",
            "proper": "PROPER", "remux": "REMUX", "bluray": "BluRay",
            "web-dl": "WEB-DL", "webrip": "WEBRip",
        ]
        for (needle, label) in tags where lowered.contains(needle) {
            return label
        }
        return nil
    }

    static func year(in text: String) -> Int? {
        guard let match = firstMatch(#"(?<!\d)((?:19|20)\d{2})(?!\d)"#, in: text) else { return nil }
        return Int(match[1])
    }

    private static func episodeTitle(in base: String, after match: String) -> String? {
        guard let range = base.range(of: match, options: .regularExpression) else { return nil }
        var rest = String(base[range.upperBound...])
        rest = rest.replacingOccurrences(of: #"^[\s._\-–—:]+"#, with: "", options: .regularExpression)
        rest = rest.replacingOccurrences(of: #"(?i)[\s._\-]*(2160p|1080p|720p|480p|bluray|web-?dl|webrip|remux|x26[45]|h\.?26[45]|hevc|av1|aac|dts|truehd|atmos).*$"#, with: "", options: .regularExpression)
        rest = rest.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
        rest = rest.replacingOccurrences(of: #"[._]+"#, with: " ", options: .regularExpression)
        let trimmed = rest.trimmingCharacters(in: CharacterSet(charactersIn: " -–—:"))
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func cleanedTitle(_ base: String) -> String {
        var text = base
        text = text.replacingOccurrences(of: #"\s*[\(\[]?(?:19|20)\d{2}[\)\]]?"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[\[\(].*?[\]\)]"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)[\s._\-]*(2160p|1080p|720p|480p|4k|uhd|bluray|blu-ray|web-?dl|webrip|remux|x26[45]|h\.?26[45]|hevc|av1|aac|dts|truehd|atmos|repack|proper|extended).*$"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[\s._]+"#, with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: CharacterSet(charactersIn: " ._-–—:"))
    }

    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        var groups: [String] = []
        for index in 0..<match.numberOfRanges {
            if let range = Range(match.range(at: index), in: text) {
                groups.append(String(text[range]))
            } else {
                groups.append("")
            }
        }
        return groups
    }
}

public enum FolderVideoBuilder {
    public static func local(currentURL: URL) -> [FolderVideo] {
        let folder = currentURL.deletingLastPathComponent()
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )) ?? []
        var videos: [FolderVideo] = []
        for file in files {
            guard VideoNaming.videoExtensions.contains(file.pathExtension.lowercased()) else { continue }
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile != false else { continue }
            let parsed = VideoNaming.parse(fileName: file.lastPathComponent, parentFolder: folder.path)
            videos.append(make(
                path: file.standardizedFileURL.path,
                fileName: file.lastPathComponent,
                parentFolder: folder.path,
                parsed: parsed,
                fileURL: file,
                sourceKind: "local"
            ))
        }
        return finalize(videos)
    }

    public static func webdav(entries: [RemoteEntry], currentPath: String, sourceID: String? = nil) -> [FolderVideo] {
        let parent = (currentPath as NSString).deletingLastPathComponent
        var videos: [FolderVideo] = []
        for entry in entries {
            guard !entry.isDirectory, entry.isPlayableVideo else { continue }
            guard (entry.path as NSString).deletingLastPathComponent == parent else { continue }
            let parsed = VideoNaming.parse(
                fileName: entry.name,
                parentFolder: parent
            )
            videos.append(make(
                path: entry.path,
                fileName: entry.name,
                parentFolder: (parent as NSString).lastPathComponent,
                parsed: parsed,
                remoteEntry: entry,
                sourceKind: "webdav",
                sourceID: sourceID
            ))
        }
        return finalize(videos)
    }

    public static func jellyfin(episodes: [LibraryEpisode], currentID: String) -> [FolderVideo] {
        var videos: [FolderVideo] = []
        for episode in episodes {
            let title = episode.title
            let label = episode.episodeLabel
            videos.append(FolderVideo(
                id: episode.id,
                displayTitle: title,
                subtitle: episode.overview?.isEmpty == false ? (episode.overview ?? "") : "Jellyfin",
                episodeLabel: label,
                seasonNumber: episode.seasonNumber > 0 ? episode.seasonNumber : nil,
                episodeNumber: episode.episodeNumber > 0 ? episode.episodeNumber : nil,
                fileName: (episode.remotePath as NSString?)?.lastPathComponent ?? title,
                path: episode.remotePath ?? episode.serverID ?? episode.id,
                sourceKind: episode.sourceKind,
                sourceID: episode.sourceID,
                jellyfinItemID: episode.serverID ?? episode.remotePath,
                jellyfinMediaSourceID: nil
            ))
        }
        return finalize(videos)
    }

    private static func make(
        path: String,
        fileName: String,
        parentFolder: String,
        parsed: VideoNaming.Parsed,
        fileURL: URL? = nil,
        remoteEntry: RemoteEntry? = nil,
        sourceKind: String,
        sourceID: String? = nil
    ) -> FolderVideo {
        let episodeLabel = parsed.season.flatMap { season in
            parsed.episode.map { String(format: "S%d · E%d", season, $0) }
        }
        let title: String
        if let episodeTitle = parsed.episodeTitle {
            title = episodeTitle
        } else if parsed.episode != nil {
            title = "第 \(parsed.episode ?? 0) 集"
        } else if let movieTitle = parsed.movieTitle, !movieTitle.isEmpty {
            title = movieTitle
        } else {
            title = (fileName as NSString).deletingPathExtension
        }
        var subtitleParts: [String] = []
        if let show = parsed.showTitle, !show.isEmpty {
            subtitleParts.append(show)
        }
        if let year = parsed.year {
            subtitleParts.append(String(year))
        }
        if let resolution = parsed.resolution {
            subtitleParts.append(resolution)
        }
        if let version = parsed.versionLabel {
            subtitleParts.append(version)
        }
        return FolderVideo(
            id: path,
            displayTitle: title,
            subtitle: subtitleParts.isEmpty ? fileName : subtitleParts.joined(separator: " · "),
            episodeLabel: episodeLabel,
            seasonNumber: parsed.season,
            episodeNumber: parsed.episode,
            year: parsed.year,
            resolution: parsed.resolution,
            versionLabel: parsed.versionLabel,
            fileName: fileName,
            path: path,
            fileURL: fileURL,
            remoteEntry: remoteEntry,
            sourceKind: sourceKind,
            sourceID: sourceID
        )
    }

    private static func finalize(_ input: [FolderVideo]) -> [FolderVideo] {
        var seen = Set<String>()
        var videos = input.filter { seen.insert($0.id).inserted }
        // Two files for the same episode (different cuts/qualities) must both
        // stay visible; append the distinguishing tag to the primary label.
        let groups = Dictionary(grouping: videos) { "\($0.episodeLabel ?? $0.displayTitle)" }
        for (_, group) in groups where group.count > 1 {
            for video in group {
                guard let index = videos.firstIndex(where: { $0.id == video.id }) else { continue }
                let tag = video.versionLabel ?? video.resolution ?? (video.fileName as NSString).deletingPathExtension
                videos[index].displayTitle += " · \(tag)"
            }
        }
        return videos.sorted { lhs, rhs in
            let ls = lhs.seasonNumber ?? 0, rs = rhs.seasonNumber ?? 0
            if ls != rs { return ls < rs }
            let le = lhs.episodeNumber ?? 0, re = rhs.episodeNumber ?? 0
            if le != re { return le < re }
            return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
        }
    }
}
