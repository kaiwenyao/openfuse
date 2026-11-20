import Foundation

/// Sidecar discovery rules modelled on Infuse's external-subtitle matching.
///
/// Accepted names for `Movie.mkv`:
///   Movie.ass
///   Movie.zh-Hans.ass
///   Movie.zh-Hant.forced.ass
///   Movie.ja.srt
///   Subs/Movie.zh-Hans.ass
///   Subs/Movie.ass
///
/// A file such as `Movie.Extended.zh-Hans.ass` counts as long as the video
/// base name is followed by a known tag. `OtherMovie.ass` never attaches.
public enum SubtitleCatalog {
    public static let subtitleExtensions: Set<String> = [
        "ass", "ssa", "srt", "vtt", "sup", "pgs",
    ]

    public static func discover(for videoURL: URL) -> [SubtitleTrack] {
        let directory = videoURL.deletingLastPathComponent()
        let videoBase = videoURL.deletingPathExtension().lastPathComponent

        var candidates: [URL] = []
        if let direct = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            candidates.append(contentsOf: direct)
        }
        let subsDirectory = directory.appendingPathComponent("Subs", isDirectory: true)
        if let nested = try? FileManager.default.contentsOfDirectory(
            at: subsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            candidates.append(contentsOf: nested)
        }

        var tracks: [SubtitleTrack] = []
        for url in candidates {
            guard subtitleExtensions.contains(url.pathExtension.lowercased()) else { continue }
            guard url.standardizedFileURL != videoURL.standardizedFileURL else { continue }
            let name = url.deletingPathExtension().lastPathComponent
            guard let match = matchSubtitleName(name, videoBase: videoBase) else { continue }

            let format = SubtitleFormat(fileExtension: url.pathExtension)
            let language = match.language ?? LanguageTag.infer(from: name)
            tracks.append(
                SubtitleTrack(
                    id: "ext:" + url.resolvingSymlinksInPath().path,
                    displayName: SubtitleLabel.make(
                        language: language,
                        format: format,
                        forced: match.forced,
                        includeFormat: true
                    ),
                    language: language,
                    format: format,
                    source: .external,
                    url: url,
                    isForced: match.forced
                )
            )
        }

        return tracks.sorted { lhs, rhs in
            let leftRank = LanguageTag.sortRank(lhs.language)
            let rightRank = LanguageTag.sortRank(rhs.language)
            if leftRank != rightRank { return leftRank < rightRank }
            if lhs.isForced != rhs.isForced { return !lhs.isForced && rhs.isForced }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    public struct NameMatch {
        public var language: String?
        public var forced: Bool
    }

    public static func matchSubtitleName(_ name: String, videoBase: String) -> NameMatch? {
        if name == videoBase { return NameMatch(language: nil, forced: false) }
        guard name.hasPrefix(videoBase + ".") else { return nil }

        let remainder = name.dropFirst(videoBase.count + 1)
        let tokens = remainder.split(separator: ".").map(String.init)
        guard !tokens.isEmpty else { return nil }

        var forced = false
        var language: String?
        var matchedMeaningfulTag = false

        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            let lower = token.lowercased()
            if lower == "forced" || lower == "foreign" {
                forced = true
                matchedMeaningfulTag = true
                index += 1
                continue
            }
            if let tag = LanguageTag.parse(token) {
                language = tag
                matchedMeaningfulTag = true
                // A combined token such as zh-Hans already carries the script.
                index += 1
                continue
            }
            // Descriptive tags Infuse tolerates on external subtitles.
            if ["sdh", "cc", "default", "full", "signs", "songs"].contains(lower) {
                matchedMeaningfulTag = true
                index += 1
                continue
            }
            // Unknown token: reject so that `Movie.Extended` trailers do not
            // masquerade as subtitles.
            index += 1
            matchedMeaningfulTag = false
        }

        guard matchedMeaningfulTag || tokens.isEmpty else { return nil }
        return NameMatch(language: language, forced: forced)
    }
}

public enum LanguageTag {
    /// Parse one filename token into a normalised language tag.
    public static func parse(_ token: String) -> String? {
        let lower = token.lowercased().replacingOccurrences(of: "_", with: "-")
        switch lower {
        case "zh", "chi", "zho", "chinese", "中文", "中":
            return "zh"
        case "zh-hans", "zh-cn", "zh-sg", "chs", "sc", "gb", "简体", "简":
            return "zh-Hans"
        case "zh-hant", "zh-tw", "zh-hk", "zh-mo", "cht", "tc", "big5", "繁體", "繁体", "繁":
            return "zh-Hant"
        case "ja", "jp", "jpn", "japanese", "日本語", "日":
            return "ja"
        case "en", "eng", "english":
            return "en"
        case "ko", "kor", "korean":
            return "ko"
        case "fr", "fre", "fra":
            return "fr"
        case "de", "ger", "deu":
            return "de"
        case "es", "spa":
            return "es"
        case "ru", "rus":
            return "ru"
        default:
            // Accept well-formed tags like pt-BR / zh-Hans-CN.
            let pattern = #"^[a-z]{2,3}(-[a-z0-9]{2,8})*$"#
            if lower.range(of: pattern, options: .regularExpression) != nil,
               lower.count <= 12 {
                return canonical(lower)
            }
            return nil
        }
    }

    /// Best-effort language detection from a free-form file name.
    public static func infer(from name: String) -> String? {
        let tokens = name.split(whereSeparator: { $0 == "." || $0 == "_" || $0 == " " }).map(String.init)
        for token in tokens.reversed() {
            if let tag = parse(token) { return tag }
        }
        return nil
    }

    /// Map ISO 639-2 codes and mpv's tags onto the tags used by the UI.
    public static func normalizeISO(_ tag: String?) -> String? {
        guard let tag, !tag.isEmpty, tag != "und" else { return nil }
        switch tag.lowercased() {
        case "chi", "zho": return "zh"
        case "eng": return "en"
        case "jpn": return "ja"
        case "kor": return "ko"
        case "fre", "fra": return "fr"
        case "ger", "deu": return "de"
        case "spa": return "es"
        case "rus": return "ru"
        default: return canonical(tag)
        }
    }

    public static func canonical(_ tag: String) -> String {
        let parts = tag.split(separator: "-").map(String.init)
        guard let first = parts.first else { return tag }
        var result = [first.lowercased()]
        for part in parts.dropFirst() {
            if part.count == 4 {
                result.append(part.prefix(1).uppercased() + part.dropFirst().lowercased())
            } else if part.count == 2 {
                result.append(part.uppercased())
            } else {
                result.append(part.lowercased())
            }
        }
        return result.joined(separator: "-")
    }

    public static func displayName(_ tag: String?) -> String {
        guard let tag else { return "未知语言" }
        switch canonical(tag) {
        case "zh-Hans": return "中文（简体）"
        case "zh-Hant": return "中文（繁體）"
        case "zh": return "中文"
        case "ja": return "日本語"
        case "en": return "English"
        case "ko": return "한국어"
        case "fr": return "Français"
        case "de": return "Deutsch"
        case "es": return "Español"
        case "ru": return "Русский"
        default: return tag
        }
    }

    public static func sortRank(_ tag: String?) -> Int {
        switch canonical(tag ?? "") {
        case "zh-Hans": return 0
        case "zh-Hant": return 1
        case "zh": return 2
        case "ja": return 3
        case "en": return 4
        case "": return 99
        default: return 50
        }
    }
}

public enum SubtitleLabel {
    public static func make(
        language: String?,
        format: SubtitleFormat,
        forced: Bool,
        includeFormat: Bool
    ) -> String {
        var label = LanguageTag.displayName(language)
        if includeFormat { label += " (\(format.displayName))" }
        if forced { label += " · 强制" }
        return label
    }
}
