import Foundation

/// Short heading shown at the top of the player. The full file name, source and
/// technical details stay available in the playback info sheet.
public struct PlayerHeading: Equatable, Sendable {
    public var title: String
    public var detail: String?

    public init(title: String, detail: String?) {
        self.title = title
        self.detail = detail
    }
}

public enum PlayerHeadingFormatter {
    /// "Fargo (2014)" + "S01E01 · Pilot", instead of the previous full file name
    /// and source/audio/subtitle line.
    public static func heading(
        seriesTitle: String?,
        episodeLabel: String?,
        itemTitle: String
    ) -> PlayerHeading {
        let item = clean(itemTitle) ?? itemTitle
        let series = clean(seriesTitle)
        let episode = clean(episodeLabel)
        guard let series else {
            return PlayerHeading(title: item, detail: episode)
        }
        var pieces: [String] = []
        if let episode { pieces.append(episode) }
        if let name = episodeName(itemTitle: item, episode: episode, series: series) {
            pieces.append(name)
        }
        return PlayerHeading(
            title: series,
            detail: pieces.isEmpty ? nil : pieces.joined(separator: " · ")
        )
    }

    private static func episodeName(
        itemTitle: String,
        episode: String?,
        series: String
    ) -> String? {
        // Local files usually carry the whole file name as the title:
        // "Fargo (2014) - S01E01 - Pilot". Strip the show prefix and episode
        // label first so the heading shows only "S01E01 · Pilot".
        var rest = itemTitle
        if rest.hasPrefix(series) {
            rest = String(rest.dropFirst(series.count))
            rest = trimSeparators(rest)
        }
        if let episode, rest.hasPrefix(episode) {
            rest = String(rest.dropFirst(episode.count))
            rest = trimSeparators(rest)
        }
        if !rest.isEmpty, rest != series, rest != episode {
            return rest
                .replacingOccurrences(of: ".", with: " ")
                .replacingOccurrences(of: "  ", with: " ")
                .trimmingCharacters(in: .whitespaces)
        }
        if let range = itemTitle.range(of: " — ") {
            guard let name = clean(String(itemTitle[range.upperBound...])) else { return nil }
            return name == series ? nil : name
        }
        return nil
    }

    private static func trimSeparators(_ value: String) -> String {
        var rest = Substring(value)
        let separators: Set<Character> = [" ", "-", "_", "—", "–", "·", ":", "|", "."]
        while let first = rest.first, separators.contains(first) {
            rest = rest.dropFirst()
        }
        while let last = rest.last, separators.contains(last) {
            rest = rest.dropLast()
        }
        return String(rest)
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
