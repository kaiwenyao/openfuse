import Foundation

/// Home rail rules: only unfinished, non-zero progress, one latest episode per
/// series, newest first, limited to four by default. The full history remains in
/// PlaybackStore and is exposed separately.
public enum ContinueWatching {
    public static let defaultLimit = 4

    public static func visible(_ records: [PlaybackRecord], limit: Int = defaultLimit) -> [PlaybackRecord] {
        var seenPaths = Set<String>()
        let candidates = records.filter { record in
            guard !record.isFinished, record.position > 0, record.duration > 0 else { return false }
            return seenPaths.insert(record.mediaPath).inserted
        }
        var newestByGroup: [String: PlaybackRecord] = [:]
        for record in candidates {
            let key = groupKey(record)
            if let existing = newestByGroup[key], existing.lastPlayedAt >= record.lastPlayedAt {
                continue
            }
            newestByGroup[key] = record
        }
        return newestByGroup.values
            .sorted { $0.lastPlayedAt > $1.lastPlayedAt }
            .prefix(max(0, limit))
            .map { $0 }
    }

    /// Full history for "查看全部": everything PlaybackStore knows, newest first.
    public static func history(_ records: [PlaybackRecord]) -> [PlaybackRecord] {
        var seen = Set<String>()
        return records
            .filter { seen.insert($0.mediaPath).inserted }
            .sorted { $0.lastPlayedAt > $1.lastPlayedAt }
    }

    public static func groupKey(_ record: PlaybackRecord) -> String {
        if let key = record.seriesKey, !key.isEmpty, !key.contains("/Users/"), !key.hasPrefix("/") {
            return key
        }
        if let derived = derivedSeriesKey(record) { return derived }
        return "path:\(record.mediaPath)"
    }

    static func derivedSeriesKey(_ record: PlaybackRecord) -> String? {
        let path = record.remotePath ?? record.url.path
        let nsPath = path as NSString
        var folder = nsPath.deletingLastPathComponent
        let parsed = VideoNaming.parse(
            fileName: nsPath.lastPathComponent,
            parentFolder: folder
        )
        guard parsed.season != nil, parsed.episode != nil else { return nil }
        if VideoNaming.seasonNumber(fromFolder: (folder as NSString).lastPathComponent) != nil {
            folder = (folder as NSString).deletingLastPathComponent
        }
        let normalized = record.remotePath == nil
            ? URL(fileURLWithPath: folder).standardizedFileURL.path
            : folder
        let prefix = record.sourceID ?? "unknown"
        return "\(prefix)|\(normalized)"
    }
}
