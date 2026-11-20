import Foundation
import CryptoKit

public enum LibraryKind: String, Codable, Sendable {
    case movie
    case series
}

public struct LibraryWork: Identifiable, Hashable, Sendable {
    public var id: String
    public var kind: LibraryKind
    public var title: String
    public var sortTitle: String
    public var year: Int?
    public var overview: String?
    public var poster: String?
    public var sourceKind: String
    public var sourceID: String
    public var serverID: String?
    public var seasonCount: Int
    public var episodeCount: Int
    public var addedAt: Date
}

public extension LibraryWork {
    var normalizedTitle: String {
        var value = title.replacingOccurrences(of: #"\s*\(\d{4}\)\s*$"#, with: "", options: .regularExpression)
        // TMDB titles often add a localized subtitle ("示例剧：TMDB 版"). Ignore
        // the suffix when grouping so the same work from Jellyfin still merges.
        value = value.replacingOccurrences(of: #"\s*[:：].*$"#, with: "", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var mergeKey: String {
        let folded = normalizedTitle.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return "\(kind.rawValue)|\(folded)"
    }
}

public struct LibraryGroup: Identifiable, Sendable {
    public var id: String
    public var key: String
    public var primary: LibraryWork
    public var works: [LibraryWork]

    public init(id: String, key: String, primary: LibraryWork, works: [LibraryWork]) {
        self.id = id
        self.key = key
        self.primary = primary
        self.works = works
    }

    public var sourceKinds: [String] {
        Array(Set(works.map(\.sourceKind))).sorted()
    }

    public var sourceLabel: String {
        sourceKinds.map { kind in
            switch kind {
            case "jellyfin": return "Jellyfin"
            case "webdav": return "WebDAV"
            default: return "本地"
            }
        }.joined(separator: " · ")
    }
}

public struct LibrarySeason: Identifiable, Hashable, Sendable {
    public var id: String
    public var workID: String
    public var number: Int
    public var title: String
    public var poster: String?
}

public struct LibraryEpisode: Identifiable, Hashable, Sendable {
    public var id: String
    public var workID: String
    public var seasonID: String?
    public var seasonNumber: Int
    public var episodeNumber: Int
    public var title: String
    public var overview: String?
    public var runtime: Double
    public var poster: String?
    public var sourceKind: String
    public var sourceID: String
    public var serverID: String?
    public var remotePath: String?
    public var remoteVariant: String?
    public var fileURL: String?

    public var episodeLabel: String? {
        guard seasonNumber > 0 else { return nil }
        return String(format: "S%02dE%02d", seasonNumber, episodeNumber)
    }
}

public struct LibraryVersion: Identifiable, Hashable, Sendable {
    public var id: String
    public var itemID: String
    public var workID: String
    public var name: String
    public var sourceKind: String
    public var sourceID: String
    public var remotePath: String?
    public var mediaSourceID: String?
    public var container: String?
    public var resolution: String?
    public var fileURL: String?
}

public struct ScannedLibrary: Sendable {
    public var sourceKind: String
    public var sourceID: String
    public var sourceName: String
    public var works: [ScannedWork]

    public init(sourceKind: String, sourceID: String, sourceName: String, works: [ScannedWork]) {
        self.sourceKind = sourceKind
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.works = works
    }
}

public struct ScannedWork: Sendable {
    public var id: String
    public var kind: LibraryKind
    public var title: String
    public var sortTitle: String
    public var year: Int?
    public var overview: String?
    public var poster: String?
    public var sourceKind: String
    public var sourceID: String
    public var serverID: String?
    public var addedAt: Date? = nil
    public var seasons: [ScannedSeason]
    public var movie: ScannedEpisode?
}

public struct ScannedSeason: Sendable {
    public var id: String
    public var number: Int
    public var title: String
    public var poster: String?
    public var episodes: [ScannedEpisode]
}

public struct ScannedEpisode: Sendable {
    public var id: String
    public var seasonNumber: Int
    public var episodeNumber: Int
    public var title: String
    public var overview: String?
    public var runtime: Double
    public var poster: String?
    public var serverID: String?
    public var remotePath: String?
    public var remoteVariant: String?
    public var fileURL: String?
    public var versions: [ScannedVersion]
}

public struct ScannedVersion: Sendable {
    public var id: String
    public var name: String
    public var mediaSourceID: String?
    public var container: String?
    public var resolution: String?
    public var remotePath: String?
    public var fileURL: String?
}

public enum LibraryID {
    public static func hash(_ value: String, prefix: String = "") -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return prefix + String(hex.prefix(16))
    }
}

public enum PosterRef {
    public static func jellyfin(itemID: String, tag: String?) -> String {
        "jellyfin:\(itemID)|\(tag ?? "")"
    }

    public static func file(_ path: String) -> String { "file:\(path)" }
    public static func remote(_ url: String) -> String { "remote:\(url)" }

    public static func parse(_ value: String?) -> (kind: String, value: String, extra: String?)? {
        guard let value, let colon = value.firstIndex(of: ":") else { return nil }
        let kind = String(value[..<colon])
        let remainder = String(value[value.index(after: colon)...])
        if kind == "jellyfin", let bar = remainder.firstIndex(of: "|") {
            let item = String(remainder[..<bar])
            let tag = String(remainder[remainder.index(after: bar)...])
            return (kind, item, tag.isEmpty ? nil : tag)
        }
        return (kind, remainder, nil)
    }
}

public struct ParsedMediaName: Equatable, Sendable {
    public var kind: LibraryKind
    public var showTitle: String
    public var episodeTitle: String?
    public var year: Int?
    public var season: Int?
    public var episode: Int?
}

public enum MediaNameParser {
    private static let episodePatterns: [NSRegularExpression] = {
        let patterns = [
            #"(?i)[\.\s_\-]s(\d{1,3})[\s\._-]*e(\d{1,4})"#,
            #"(?i)(\d{1,2})x(\d{1,4})"#,
            #"(?i)season[\s\._-]*(\d{1,3})[\s\._-]*episode[\s\._-]*(\d{1,4})"#,
            #"第\s*(\d{1,3})\s*季.*?第\s*(\d{1,4})\s*[集话話]"#,
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    private static let chineseEpisode = try! NSRegularExpression(pattern: #"第\s*(\d{1,4})\s*[集话話]"#)

    public static func parse(fileURL: URL, relativePath: String) -> ParsedMediaName {
        let base = fileURL.deletingPathExtension().lastPathComponent
        let components = relativePath.split(separator: "/").map(String.init)
        let parent = components.dropLast().last ?? ""
        let grandparent = components.dropLast(2).last ?? ""

        var season: Int?
        var episode: Int?
        var matchRange: Range<String.Index>?

        for regex in episodePatterns {
            let range = NSRange(base.startIndex..<base.endIndex, in: base)
            if let match = regex.firstMatch(in: base, range: range), match.numberOfRanges >= 3,
               let sRange = Range(match.range(at: 1), in: base),
               let eRange = Range(match.range(at: 2), in: base) {
                season = Int(base[sRange])
                episode = Int(base[eRange])
                if let full = Range(match.range(at: 0), in: base) { matchRange = full }
                break
            }
        }

        if episode == nil,
           let match = chineseEpisode.firstMatch(in: base, range: NSRange(base.startIndex..<base.endIndex, in: base)),
           let eRange = Range(match.range(at: 1), in: base) {
            episode = Int(base[eRange])
            if let seasonMatch = try? NSRegularExpression(pattern: #"第\s*(\d{1,3})\s*季"#),
               let seasonResult = seasonMatch.firstMatch(in: base, range: NSRange(base.startIndex..<base.endIndex, in: base)),
               let sRange = Range(seasonResult.range(at: 1), in: base) {
                season = Int(base[sRange])
            }
        }

        if let matchRange {
            let prefix = String(base[..<matchRange.lowerBound])
            var show = clean(prefix)
            if show.isEmpty { show = clean(parent) }
            if show.isEmpty { show = clean(grandparent) }
            let suffix = String(base[matchRange.upperBound...])
            let episodeTitle = cleanEpisodeTitle(suffix)
            if season == nil {
                if parent.range(of: #"(?i)season\s*(\d+)"#, options: .regularExpression) != nil,
                   let digits = parent.split(whereSeparator: { !$0.isNumber }).last {
                    season = Int(digits)
                }
            }
            return ParsedMediaName(
                kind: .series,
                showTitle: show.isEmpty ? clean(base) : show,
                episodeTitle: episodeTitle,
                year: year(in: base),
                season: season ?? 1,
                episode: episode
            )
        }

        return ParsedMediaName(
            kind: .movie,
            showTitle: clean(base),
            episodeTitle: nil,
            year: year(in: base),
            season: nil,
            episode: nil
        )
    }

    public static func year(in name: String) -> Int? {
        let patterns = [#"\((\d{4})\)"#, #"[\.\s_](\d{4})[\.\s_]"#]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..<name.endIndex, in: name)),
               let range = Range(match.range(at: 1), in: name),
               let year = Int(name[range]), (1900...2100).contains(year) {
                return year
            }
        }
        return nil
    }

    public static func clean(_ raw: String) -> String {
        var value = raw.replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.replacingOccurrences(of: #"\s*\(\d{4}\)\s*$"#, with: "", options: .regularExpression)
        let noise = [
            "2160p", "1080p", "720p", "WEB-DL", "WEBRip", "BluRay", "Blu-ray", "HEVC", "x265", "H265",
            "H264", "x264", "DDP5.1", "DDP", "HDR", "SDR", "REMUX", "AAC", "DTS", "ENG", "CHS", "CHT",
        ]
        for token in noise {
            value = value.replacingOccurrences(of: token, with: "", options: .caseInsensitive)
        }
        value = value.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " .-_[]"))
        return value
    }

    public static func cleanEpisodeTitle(_ raw: String) -> String? {
        let trimmed = clean(raw)
        return trimmed.isEmpty ? nil : trimmed
    }
}
