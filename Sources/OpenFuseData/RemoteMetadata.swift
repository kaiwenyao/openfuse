import Foundation

public struct DirectoryEpisodeMetadata: Codable, Hashable, Sendable {
    public var season: Int
    public var number: Int
    public var title: String
    public var overview: String?
    public var stillURL: String?
    public var runtime: Double
    /// TMDB episode vote average, 0–10. Only shown when present.
    public var rating: Double?

    public var label: String {
        String(format: "S%02dE%02d", season, number)
    }

    public var key: String {
        String(format: "S%02dE%02d", season, number)
    }
}

public struct DirectoryWorkMetadata: Codable, Hashable, Sendable {
    public var kind: LibraryKind
    public var title: String
    public var year: Int?
    public var overview: String?
    public var posterURL: String?
    public var backdropURL: String?
    /// TMDB vote average and its label.
    public var tmdbRating: Double?
    public var tmdbVotes: Int?
    public var imdbID: String?
    /// Pre-formatted third-party ratings, e.g. "IMDb 8.7/10".
    public var externalRatings: [String]
    public var seasonNumbers: [Int]

    public var tmdbLabel: String? {
        guard let tmdbRating else { return nil }
        return "TMDB \(String(format: "%.1f", tmdbRating))/10"
    }

    public var allRatings: [String] {
        ([tmdbLabel].compactMap { $0 }) + externalRatings
    }
}

public struct DirectoryMetadata: Codable, Hashable, Sendable {
    public var work: DirectoryWorkMetadata
    public var episodes: [DirectoryEpisodeMetadata]
    public var sourceLabel: String
    public var updatedAt: Date

    public func episode(season: Int, number: Int) -> DirectoryEpisodeMetadata? {
        episodes.first { $0.season == season && $0.number == number }
    }

    public func episode(forKey key: String) -> DirectoryEpisodeMetadata? {
        episodes.first { $0.key == key }
    }
}

private struct MetadataCacheEnvelope: Codable {
    var savedAt: Date
    var value: DirectoryMetadata
}

/// Resolves one WebDAV directory to TMDB work + season data. Only the title,
/// year and public IDs leave the machine; paths and credentials never do.
public actor RemoteMetadataService {
    private let tmdb: TMDBClient?
    private let omdb: OMDbClient?
    private let cacheDirectory: URL
    private let ttl: TimeInterval = 24 * 60 * 60

    public init(tmdb: TMDBClient?, omdb: OMDbClient?, cacheDirectory: URL) {
        self.tmdb = tmdb
        self.omdb = omdb
        self.cacheDirectory = cacheDirectory
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    public func metadata(
        sourceID: String,
        directoryPath: String,
        entries: [RemoteEntry],
        nfo: NFOMetadata? = nil,
        override: LibraryOverride? = nil
    ) async -> DirectoryMetadata? {
        let playable = entries.filter { !$0.isDirectory && $0.isPlayableVideo }
        guard !playable.isEmpty else { return nil }

        let parsed = playable.map {
            ($0, VideoNaming.parse(fileName: $0.name, parentFolder: directoryPath))
        }
        let episodic = parsed.filter { $0.1.season != nil && $0.1.episode != nil }
        let kind: LibraryKind = episodic.isEmpty ? .movie : .series
        let folder = (directoryPath as NSString).lastPathComponent
        let titleHint: String
        let yearHint: Int?
        let seasonHint: Int?
        if let first = episodic.first {
            titleHint = first.1.showTitle?.isEmpty == false
                ? (first.1.showTitle ?? "")
                : VideoNaming.showName(parentFolder: directoryPath)
            yearHint = first.1.year
            seasonHint = first.1.season ?? VideoNaming.seasonNumber(fromFolder: folder)
        } else {
            let first = parsed[0].1
            titleHint = first.movieTitle?.isEmpty == false ? (first.movieTitle ?? folder) : folder
            yearHint = first.year
            seasonHint = nil
        }
        let cacheKey = Self.cacheKey(sourceID: sourceID, kind: kind, title: titleHint, season: seasonHint)
        if let cached = readCache(cacheKey) { return cached }
        guard let tmdb else { return nil }

        // Prefer an exact year match when the same title has several works.
        var match: TMDBMatch?
        if let yearHint {
            let candidates = await tmdb.candidates(title: titleHint, year: yearHint, kind: kind, limit: 8)
            match = candidates.first(where: { $0.year == yearHint }) ?? candidates.first
        }
        if match == nil {
            match = await tmdb.match(title: titleHint, year: yearHint, kind: kind)
        }
        if match == nil, yearHint != nil {
            match = await tmdb.match(title: titleHint, year: nil, kind: kind)
        }
        guard let match, let details = await tmdb.details(kind: kind, id: match.id) else { return nil }

        var episodes: [DirectoryEpisodeMetadata] = []
        if kind == .series, let season = seasonHint {
            let seasonEpisodes = await tmdb.season(tvID: match.id, season: season)
            episodes = seasonEpisodes.map { ep in
                DirectoryEpisodeMetadata(
                    season: ep.season,
                    number: ep.number,
                    title: ep.title,
                    overview: ep.overview,
                    stillURL: tmdb.imageURL(path: ep.stillPath)?.absoluteString,
                    runtime: ep.runtime,
                    rating: ep.rating
                )
            }
        }

        var externalRatings: [String] = []
        if let imdbID = details.imdbID, let omdb {
            if let ratings = await omdb.ratings(imdbID: imdbID) {
                externalRatings = ratings.labels
            }
        }

        let work = DirectoryWorkMetadata(
            kind: kind,
            title: override?.title?.isEmpty == false ? (override?.title ?? details.title) : (nfo?.title ?? details.title),
            year: override?.year ?? nfo?.year ?? details.year,
            overview: override?.overview ?? nfo?.overview ?? details.overview,
            posterURL: (override?.poster.flatMap(URL.init(string:)) ?? nfo?.posterURL ?? tmdb.imageURL(path: details.posterPath))?.absoluteString,
            backdropURL: tmdb.imageURL(path: details.backdropPath)?.absoluteString,
            tmdbRating: details.rating,
            tmdbVotes: details.voteCount,
            imdbID: details.imdbID,
            externalRatings: externalRatings,
            seasonNumbers: details.seasons.map(\.seasonNumber)
        )
        let metadata = DirectoryMetadata(
            work: work,
            episodes: episodes,
            sourceLabel: "TMDB",
            updatedAt: Date()
        )
        writeCache(cacheKey, metadata)
        return metadata
    }

    public func clearCache(sourceID: String, directoryPath: String) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent.hasPrefix(sourceID + "-") {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func cacheKey(sourceID: String, kind: LibraryKind, title: String, season: Int?) -> String {
        let clean = title.replacingOccurrences(of: #"[^A-Za-z0-9\u4e00-\u9fa5]+"#, with: "-", options: .regularExpression)
        return "\(sourceID)-\(kind.rawValue)-\(clean)-\(season ?? 0)"
    }

    private func readCache(_ key: String) -> DirectoryMetadata? {
        let url = cacheDirectory.appendingPathComponent(key + ".json")
        guard let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder.openFuse.decode(MetadataCacheEnvelope.self, from: data),
              Date().timeIntervalSince(envelope.savedAt) < ttl else { return nil }
        return envelope.value
    }

    private func writeCache(_ key: String, _ value: DirectoryMetadata) {
        let url = cacheDirectory.appendingPathComponent(key + ".json")
        guard let data = try? JSONEncoder.openFuse.encode(MetadataCacheEnvelope(savedAt: Date(), value: value)) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
