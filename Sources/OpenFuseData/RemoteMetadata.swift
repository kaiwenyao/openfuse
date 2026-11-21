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
    /// Languages actually used for this field after per-field fallback.
    public var titleLanguage: String?
    public var overviewLanguage: String?

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
    /// Ratings from non-TMDB public sources, e.g. "TVmaze 8.4/10".
    public var ratingLabels: [String]?
    /// Languages actually used for this field after per-field fallback.
    public var titleLanguage: String?
    public var overviewLanguage: String?

    public var tmdbLabel: String? {
        guard let tmdbRating else { return nil }
        return "TMDB \(String(format: "%.1f", tmdbRating))/10"
    }

    public var allRatings: [String] {
        (ratingLabels ?? []) + ([tmdbLabel].compactMap { $0 }) + externalRatings
    }
}

public struct DirectoryMetadata: Codable, Hashable, Sendable {
    public var work: DirectoryWorkMetadata
    public var episodes: [DirectoryEpisodeMetadata]
    public var sourceLabel: String
    public var updatedAt: Date
    /// Per-file movie metadata so a folder with several movies does not reuse
    /// the first title for every row.
    public var movieWorks: [String: DirectoryWorkMetadata]?
    /// matched / noCandidates / networkFailure / localOnly / partial.
    public var matchState: String?
    public var matchNote: String?

    public func episode(season: Int, number: Int) -> DirectoryEpisodeMetadata? {
        episodes.first { $0.season == season && $0.number == number }
    }

    public func episode(forKey key: String) -> DirectoryEpisodeMetadata? {
        episodes.first { $0.key == key }
    }

    public func work(for path: String) -> DirectoryWorkMetadata {
        movieWorks?[path] ?? work
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
    private let publicResolver: any PublicMetadataProviding
    public let language: MetadataLanguage
    private let cacheDirectory: URL
    private let ttl: TimeInterval = 24 * 60 * 60

    public init(
        tmdb: TMDBClient?,
        omdb: OMDbClient?,
        cacheDirectory: URL,
        publicResolver: any PublicMetadataProviding = PublicMetadataService(),
        language: MetadataLanguage = .current()
    ) {
        self.tmdb = tmdb
        self.omdb = omdb
        self.publicResolver = publicResolver
        self.language = language
        self.cacheDirectory = cacheDirectory
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    public func metadata(
        sourceID: String,
        directoryPath: String,
        entries: [RemoteEntry],
        nfo: NFOMetadata? = nil,
        override: LibraryOverride? = nil,
        matchTitle: String? = nil,
        matchYear: Int? = nil
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
        var titleCandidates: [String] = []
        if let first = episodic.first {
            titleHint = first.1.showTitle?.isEmpty == false
                ? (first.1.showTitle ?? "")
                : VideoNaming.showName(parentFolder: directoryPath)
            yearHint = first.1.year
            seasonHint = first.1.season ?? VideoNaming.seasonNumber(fromFolder: folder)
            titleCandidates.append(titleHint)
            // "Shingeki no Kyojin - S01E01 - ..." supplies the romanized name.
            let base = (first.0.name as NSString).deletingPathExtension
            if let range = base.range(of: #"(?i)[\s._-]*S\d{1,2}[ ._-]?E\d{1,3}.*$"#, options: .regularExpression) {
                let prefix = String(base[..<range.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: " ._-"))
                if !prefix.isEmpty, !titleCandidates.contains(where: { $0.caseInsensitiveCompare(prefix) == .orderedSame }) {
                    titleCandidates.append(prefix)
                }
            }
        } else {
            let first = parsed[0].1
            titleHint = first.movieTitle?.isEmpty == false ? (first.movieTitle ?? folder) : folder
            yearHint = first.year
            seasonHint = nil
        }
        if let nfoTitle = nfo?.title, !nfoTitle.isEmpty {
            titleCandidates.insert(nfoTitle, at: 0)
        }
        if let overrideTitle = override?.title, !overrideTitle.isEmpty {
            titleCandidates.insert(overrideTitle, at: 0)
        }
        if let matchTitle, !matchTitle.isEmpty {
            titleCandidates.insert(matchTitle, at: 0)
        }
        let cacheKey = Self.cacheKey(sourceID: sourceID, kind: kind, title: titleHint, season: seasonHint, language: language.identifier)
        if let cached = readCache(cacheKey) { return cached }

        let fallbackTitle = matchTitle?.isEmpty == false
            ? (matchTitle ?? titleHint)
            : (override?.title?.isEmpty == false ? (override?.title ?? titleHint) : (nfo?.title ?? titleHint))
        let fallbackYear = matchYear ?? override?.year ?? nfo?.year ?? yearHint
        let fallbackOverview = override?.overview ?? nfo?.overview
        let fallbackPoster = (override?.poster.flatMap(URL.init(string:)) ?? nfo?.posterURL)?.absoluteString
        var episodes: [DirectoryEpisodeMetadata] = []
        var movieWorks: [String: DirectoryWorkMetadata] = [:]
        var primaryWork: DirectoryWorkMetadata?
        var sourceLabel = "本地资料"
        var usedPublic = false
        var resolvedRemote = false

        if kind == .series {
            var resolved: DirectoryWorkMetadata?
            if let tmdb, let match = await bestTMDBMatch(
                client: tmdb,
                candidates: titleCandidates,
                year: yearHint,
                kind: .series
            ), let details = await tmdb.details(kind: .series, id: match.id) {
                var seasonEpisodes: [TMDBEpisodeDetails] = []
                if let seasonHint {
                    seasonEpisodes = await tmdb.season(tvID: match.id, season: seasonHint)
                }
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
                var externalRatings: [String] = []
                if let imdbID = details.imdbID, let omdb, let ratings = await omdb.ratings(imdbID: imdbID) {
                    externalRatings = ratings.labels
                }
                resolved = DirectoryWorkMetadata(
                    kind: .series,
                    title: details.title,
                    year: details.year,
                    overview: details.overview,
                    posterURL: tmdb.imageURL(path: details.posterPath)?.absoluteString,
                    backdropURL: tmdb.imageURL(path: details.backdropPath)?.absoluteString,
                    tmdbRating: details.rating,
                    tmdbVotes: details.voteCount,
                    imdbID: details.imdbID,
                    externalRatings: externalRatings,
                    seasonNumbers: details.seasons.map(\.seasonNumber),
                    ratingLabels: [],
                    titleLanguage: language.identifier,
                    overviewLanguage: language.identifier
                )
                sourceLabel = "TMDB"
            } else {
                usedPublic = true
                if let publicResult = await publicResolver.series(
                    titleCandidates: titleCandidates,
                    year: yearHint,
                    season: seasonHint
                ) {
                    resolved = publicResult.work
                    episodes = publicResult.episodes
                    sourceLabel = "TVmaze / Wikipedia"
                }
            }
            resolvedRemote = resolved != nil
            primaryWork = resolved ?? DirectoryWorkMetadata(
                kind: .series,
                title: fallbackTitle,
                year: fallbackYear,
                overview: fallbackOverview,
                posterURL: fallbackPoster,
                backdropURL: nil,
                tmdbRating: nil,
                tmdbVotes: nil,
                imdbID: nil,
                externalRatings: [],
                seasonNumbers: [],
                ratingLabels: nil
            )
        } else {
            // Resolve every movie file separately so a folder with several
            // films never copies the first film's metadata onto all rows.
            for (entry, info) in parsed {
                let title = matchTitle ?? override?.title ?? nfo?.title ?? info.movieTitle ?? folder
                let year = matchYear ?? override?.year ?? nfo?.year ?? info.year
                var work: DirectoryWorkMetadata?
                if let tmdb, let match = await bestTMDBMatch(
                    client: tmdb,
                    candidates: [title],
                    year: year,
                    kind: .movie
                ), let details = await tmdb.details(kind: .movie, id: match.id) {
                    var externalRatings: [String] = []
                    if let imdbID = details.imdbID, let omdb, let ratings = await omdb.ratings(imdbID: imdbID) {
                        externalRatings = ratings.labels
                    }
                    work = DirectoryWorkMetadata(
                        kind: .movie,
                        title: details.title,
                        year: details.year,
                        overview: details.overview,
                        posterURL: tmdb.imageURL(path: details.posterPath)?.absoluteString,
                        backdropURL: tmdb.imageURL(path: details.backdropPath)?.absoluteString,
                        tmdbRating: details.rating,
                        tmdbVotes: details.voteCount,
                        imdbID: details.imdbID,
                        externalRatings: externalRatings,
                        seasonNumbers: [],
                        ratingLabels: [],
                        titleLanguage: language.identifier,
                        overviewLanguage: language.identifier
                    )
                    sourceLabel = "TMDB"
                } else {
                    usedPublic = true
                    if let publicWork = await publicResolver.movie(
                        titleCandidates: [title, info.movieTitle ?? ""],
                        year: year
                    ) {
                        work = publicWork
                        sourceLabel = "Wikipedia / Wikidata"
                    }
                }
                if work != nil { resolvedRemote = true }
                let finalWork = work ?? DirectoryWorkMetadata(
                    kind: .movie,
                    title: title,
                    year: year,
                    overview: fallbackOverview,
                    posterURL: fallbackPoster,
                    backdropURL: nil,
                    tmdbRating: nil,
                    tmdbVotes: nil,
                    imdbID: nil,
                    externalRatings: [],
                    seasonNumbers: [],
                    ratingLabels: nil
                )
                movieWorks[entry.path] = finalWork
                if primaryWork == nil { primaryWork = finalWork }
            }
        }

        guard var work = primaryWork else { return nil }
        // NFO and manual corrections win field by field; remote sources fill gaps.
        work.title = matchTitle?.isEmpty == false
            ? (matchTitle ?? work.title)
            : (override?.title?.isEmpty == false ? (override?.title ?? work.title) : (nfo?.title ?? work.title))
        work.year = matchYear ?? override?.year ?? nfo?.year ?? work.year
        work.overview = override?.overview ?? nfo?.overview ?? work.overview
        if let poster = override?.poster.flatMap(URL.init(string:)) ?? nfo?.posterURL {
            work.posterURL = poster.absoluteString
        }
        if !movieWorks.isEmpty {
            for key in movieWorks.keys {
                guard var item = movieWorks[key] else { continue }
                item.title = override?.title?.isEmpty == false ? (override?.title ?? item.title) : (nfo?.title ?? item.title)
                item.year = override?.year ?? nfo?.year ?? item.year
                item.overview = override?.overview ?? nfo?.overview ?? item.overview
                if let poster = override?.poster.flatMap(URL.init(string:)) ?? nfo?.posterURL {
                    item.posterURL = poster.absoluteString
                }
                movieWorks[key] = item
            }
        }
        var matchState = "matched"
        var matchNote: String?
        if usedPublic {
            let networkFailed = await publicResolver.lastFailure()
            if !resolvedRemote {
                matchState = networkFailed ? "networkFailure" : "noCandidates"
                matchNote = networkFailed ? "网络不可用，显示本地资料" : "未找到公开候选，显示本地资料"
            } else if work.overview == nil || work.posterURL == nil || work.year == nil {
                matchState = "partial"
                matchNote = "匹配成功，部分字段缺失"
            } else {
                matchState = "matched"
                matchNote = sourceLabel
            }
        } else if sourceLabel == "本地资料" {
            matchState = "localOnly"
            matchNote = "仅本地/NFO 资料"
        } else {
            matchNote = sourceLabel
        }
        let metadata = DirectoryMetadata(
            work: work,
            episodes: episodes,
            sourceLabel: sourceLabel,
            updatedAt: Date(),
            movieWorks: movieWorks.isEmpty ? nil : movieWorks,
            matchState: matchState,
            matchNote: matchNote
        )
        writeCache(cacheKey, metadata)
        return metadata
    }

    private func bestTMDBMatch(
        client: TMDBClient,
        candidates: [String],
        year: Int?,
        kind: LibraryKind
    ) async -> TMDBMatch? {
        for candidate in candidates where !candidate.isEmpty {
            if let year {
                let results = await client.candidates(title: candidate, year: year, kind: kind, limit: 8)
                if let exact = results.first(where: { $0.year == year }) { return exact }
                if let first = results.first { return first }
            }
            if let match = await client.match(title: candidate, year: year, kind: kind) {
                return match
            }
        }
        return nil
    }

    /// Reads the persisted enrichment for a directory without network access.
    /// Used by the home rail so old history can show stills after a restart.
    public func cachedMetadata(sourceID: String, directoryPath: String) -> DirectoryMetadata? {
        let folder = (directoryPath as NSString).lastPathComponent
        let files = (try? FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path)) ?? []
        let prefix = sourceID + "-"
        for file in files where file.hasPrefix(prefix) && file.hasSuffix(".json") {
            guard file.contains("-\(language.identifier)-") else { continue }
            let url = cacheDirectory.appendingPathComponent(file)
            guard let data = try? Data(contentsOf: url),
                  let envelope = try? JSONDecoder.openFuse.decode(MetadataCacheEnvelope.self, from: data),
                  Date().timeIntervalSince(envelope.savedAt) < ttl else { continue }
            if envelope.value.work.kind == .series {
                let season = VideoNaming.seasonNumber(fromFolder: folder)
                let key = Self.cacheKey(
                    sourceID: sourceID,
                    kind: .series,
                    title: VideoNaming.showName(parentFolder: directoryPath),
                    season: season,
                    language: language.identifier
                )
                if file == key + ".json" { return envelope.value }
            } else if file.contains("-movie-") {
                return envelope.value
            }
        }
        return nil
    }

    public func clearCache(sourceID: String, directoryPath: String) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent.hasPrefix(sourceID + "-") {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func cacheKey(sourceID: String, kind: LibraryKind, title: String, season: Int?, language: String = MetadataLanguage.current().identifier) -> String {
        let clean = title.replacingOccurrences(of: #"[^A-Za-z0-9\u4e00-\u9fa5]+"#, with: "-", options: .regularExpression)
        return "\(sourceID)-\(language)-\(kind.rawValue)-\(clean)-\(season ?? 0)"
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
