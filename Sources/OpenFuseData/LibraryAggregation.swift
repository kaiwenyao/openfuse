import Foundation

public struct MergedLibraryVersion: Identifiable, Sendable {
    public var id: String
    public var label: String
    public var work: LibraryWork
    public var episode: LibraryEpisode
    public var version: LibraryVersion?

    public init(id: String, label: String, work: LibraryWork, episode: LibraryEpisode, version: LibraryVersion?) {
        self.id = id
        self.label = label
        self.work = work
        self.episode = episode
        self.version = version
    }
}

public struct MergedLibraryEpisode: Identifiable, Sendable {
    public var id: String
    public var seasonNumber: Int
    public var episodeNumber: Int
    public var title: String
    public var overview: String?
    public var runtime: Double
    public var versions: [MergedLibraryVersion]

    public var episodeLabel: String? {
        guard seasonNumber > 0 else { return nil }
        return String(format: "S%02dE%02d", seasonNumber, episodeNumber)
    }

    public init(
        id: String,
        seasonNumber: Int,
        episodeNumber: Int,
        title: String,
        overview: String?,
        runtime: Double,
        versions: [MergedLibraryVersion]
    ) {
        self.id = id
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.title = title
        self.overview = overview
        self.runtime = runtime
        self.versions = versions
    }
}


public enum LibraryAggregation {
    public static func mergedEpisodes(group: LibraryGroup, store: LibraryStore) throws -> [MergedLibraryEpisode] {
        struct Bucket {
            var season: Int
            var episode: Int
            var title: String
            var overview: String?
            var runtime: Double
            var versions: [MergedLibraryVersion]
        }
        var buckets: [String: Bucket] = [:]
        for work in group.works {
            for episode in try store.episodes(workID: work.id) {
                let key = "\(episode.seasonNumber)|\(episode.episodeNumber)"
                var bucket = buckets[key] ?? Bucket(
                    season: episode.seasonNumber,
                    episode: episode.episodeNumber,
                    title: episode.title,
                    overview: episode.overview,
                    runtime: episode.runtime,
                    versions: []
                )
                if bucket.title.isEmpty { bucket.title = episode.title }
                if bucket.overview == nil { bucket.overview = episode.overview }
                if bucket.runtime == 0 { bucket.runtime = episode.runtime }
                for version in try store.versions(itemID: episode.id) {
                    bucket.versions.append(
                        MergedLibraryVersion(
                            id: version.id + "@" + work.id,
                            label: "\(sourceLabel(work.sourceKind)) · \(version.name)",
                            work: work,
                            episode: episode,
                            version: version
                        )
                    )
                }
                if bucket.versions.isEmpty {
                    bucket.versions.append(
                        MergedLibraryVersion(
                            id: episode.id + "@" + work.id,
                            label: "\(sourceLabel(work.sourceKind)) · 播放",
                            work: work,
                            episode: episode,
                            version: nil
                        )
                    )
                }
                buckets[key] = bucket
            }
        }
        return buckets.values
            .map { bucket in
                MergedLibraryEpisode(
                    id: "\(group.key)|\(bucket.season)|\(bucket.episode)",
                    seasonNumber: bucket.season,
                    episodeNumber: bucket.episode,
                    title: bucket.title,
                    overview: bucket.overview,
                    runtime: bucket.runtime,
                    versions: bucket.versions
                )
            }
            .sorted { ($0.seasonNumber, $0.episodeNumber) < ($1.seasonNumber, $1.episodeNumber) }
    }

    public static func sourceLabel(_ kind: String) -> String {
        switch kind {
        case "jellyfin": return "Jellyfin"
        case "emby": return "Emby"
        case "webdav": return "WebDAV"
        case "plex": return "Plex"
        default: return "本地"
        }
    }
}
