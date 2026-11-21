import Foundation

/// Zero-configuration public metadata: TVmaze for TV, Wikipedia + Wikidata for
/// movies and localized summaries. No API key is required; only titles, years
/// and public IDs are sent.
public protocol PublicMetadataProviding: Sendable {
    func series(
        titleCandidates: [String],
        year: Int?,
        season: Int?
    ) async -> (work: DirectoryWorkMetadata, episodes: [DirectoryEpisodeMetadata])?
    func movie(titleCandidates: [String], year: Int?) async -> DirectoryWorkMetadata?
}

public actor PublicMetadataService: PublicMetadataProviding {
    private let session: URLSession
    private var seriesCache: [String: (DirectoryWorkMetadata, [DirectoryEpisodeMetadata])] = [:]
    private var movieCache: [String: DirectoryWorkMetadata] = [:]
    private var wikiCache: [String: WikipediaSummary?] = [:]

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Series

    public func series(
        titleCandidates: [String],
        year: Int?,
        season: Int?
    ) async -> (work: DirectoryWorkMetadata, episodes: [DirectoryEpisodeMetadata])? {
        let key = titleCandidates.joined(separator: "|") + "|\(year ?? 0)|\(season ?? 0)"
        if let cached = seriesCache[key] { return cached }
        var best: TVmazeShow?
        var bestScore = -1
        for candidate in titleCandidates where !candidate.isEmpty {
            for show in await tvmazeSearch(candidate) {
                var score = 0
                if let year, let premiered = show.premiered, premiered.hasPrefix(String(year)) {
                    score += 100
                }
                if show.name.localizedCaseInsensitiveContains(candidate) { score += 20 }
                if show.type?.lowercased() == "animation" { score += 5 }
                if score > bestScore {
                    best = show
                    bestScore = score
                }
            }
        }
        guard let show = best else { return nil }

        let wiki = await wikipediaSummary(
            queries: [show.name] + titleCandidates + ["\(show.name) 动画", "\(show.name) TV series"],
            preferredLanguages: ["zh", "en"]
        )
        let episodes: [DirectoryEpisodeMetadata]
        if let season {
            episodes = await tvmazeEpisodes(showID: show.id, season: season)
        } else {
            episodes = []
        }
        let work = DirectoryWorkMetadata(
            kind: .series,
            title: wiki?.title ?? show.name,
            year: show.premiered.flatMap { Int($0.prefix(4)) } ?? year,
            overview: wiki?.extract ?? Self.stripHTML(show.summary),
            posterURL: show.image?.original ?? wiki?.thumbnail,
            backdropURL: nil,
            tmdbRating: nil,
            tmdbVotes: nil,
            imdbID: show.externals?.imdb,
            externalRatings: [],
            seasonNumbers: Array(Set(episodes.map(\.season))).sorted(),
            ratingLabels: show.rating?.average.map { [String(format: "TVmaze %.1f/10", $0)] } ?? []
        )
        let result = (work, episodes)
        seriesCache[key] = result
        return result
    }

    // MARK: - Movies

    public func movie(titleCandidates: [String], year: Int?) async -> DirectoryWorkMetadata? {
        let key = titleCandidates.joined(separator: "|") + "|\(year ?? 0)"
        if let cached = movieCache[key] { return cached }
        let queries = titleCandidates.flatMap { candidate -> [String] in
            var values = [candidate]
            if let year {
                values.append("\(candidate) \(year) 电影")
                values.append("\(candidate) \(year) film")
            }
            return values
        }
        guard var summary = await wikipediaSummary(queries: queries, preferredLanguages: ["zh", "en"]) else {
            return nil
        }
        let verified = await wikidataVerifyMovie(summary.wikibaseItem, year: year)
        if !verified.isFilm, !Self.looksLikeFilm(summary) { return nil }
        if let verifiedYear = verified.year, summary.year == nil {
            summary.year = verifiedYear
        }
        let work = DirectoryWorkMetadata(
            kind: .movie,
            title: summary.title,
            year: summary.year ?? verified.year ?? year,
            overview: summary.extract,
            posterURL: summary.thumbnail,
            backdropURL: nil,
            tmdbRating: nil,
            tmdbVotes: nil,
            imdbID: nil,
            externalRatings: [],
            seasonNumbers: [],
            ratingLabels: []
        )
        movieCache[key] = work
        return work
    }

    // MARK: - TVmaze

    private struct TVmazeShow: Decodable {
        var id: Int
        var name: String
        var type: String?
        var premiered: String?
        var summary: String?
        var image: Image?
        var rating: Rating?
        var externals: Externals?
        struct Image: Decodable { var original: String? }
        struct Rating: Decodable { var average: Double? }
        struct Externals: Decodable { var imdb: String? }
    }

    private struct TVmazeEpisode: Decodable {
        var name: String
        var season: Int
        var number: Int?
        var summary: String?
        var image: TVmazeShow.Image?
    }

    private struct TVmazeSearchResult: Decodable {
        var show: TVmazeShow
    }

    private func tvmazeSearch(_ query: String) async -> [TVmazeShow] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.tvmaze.com/search/shows?q=\(encoded)"),
              let data = try? await session.data(from: url).0,
              let results = try? JSONDecoder().decode([TVmazeSearchResult].self, from: data) else {
            return []
        }
        return results.map(\.show)
    }

    private func tvmazeEpisodes(showID: Int, season: Int) async -> [DirectoryEpisodeMetadata] {
        guard let url = URL(string: "https://api.tvmaze.com/shows/\(showID)/episodes?specials=1"),
              let data = try? await session.data(from: url).0,
              let episodes = try? JSONDecoder().decode([TVmazeEpisode].self, from: data) else {
            return []
        }
        return episodes.compactMap { episode in
            guard episode.season == season, let number = episode.number else { return nil }
            return DirectoryEpisodeMetadata(
                season: episode.season,
                number: number,
                title: episode.name,
                overview: Self.stripHTML(episode.summary),
                stillURL: episode.image?.original,
                runtime: 0,
                rating: nil
            )
        }.sorted { $0.number < $1.number }
    }

    // MARK: - Wikipedia / Wikidata

    private struct WikipediaSummary {
        var title: String
        var extract: String?
        var description: String?
        var thumbnail: String?
        var wikibaseItem: String?
        var year: Int?
        var language: String
    }

    private func wikipediaSummary(queries: [String], preferredLanguages: [String]) async -> WikipediaSummary? {
        for language in preferredLanguages {
            for query in queries {
                let key = "\(language)|\(query)"
                if let cached = wikiCache[key] { if let cached { return cached } else { continue } }
                if let summary = await searchWikipedia(query: query, language: language) {
                    wikiCache[key] = summary
                    return summary
                }
                wikiCache[key] = WikipediaSummary?.none
            }
        }
        return nil
    }

    private func searchWikipedia(query: String, language: String) async -> WikipediaSummary? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "https://\(language).wikipedia.org/w/api.php?action=query&list=search&srsearch=\(encoded)&format=json&srlimit=4"),
              let data = try? await session.data(from: searchURL).0,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let queryObject = object["query"] as? [String: Any],
              let results = queryObject["search"] as? [[String: Any]] else {
            return nil
        }
        for result in results {
            guard let title = result["title"] as? String else { continue }
            if let summary = await pageSummary(title: title, language: language) {
                return summary
            }
        }
        return nil
    }

    private func pageSummary(title: String, language: String) async -> WikipediaSummary? {
        let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
        guard let url = URL(string: "https://\(language).wikipedia.org/api/rest_v1/page/summary/\(encoded)"),
              let data = try? await session.data(from: url).0,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let extract = object["extract"] as? String
        let description = object["description"] as? String
        let thumbnail = (object["thumbnail"] as? [String: Any])?["source"] as? String
        let pageTitle = object["title"] as? String ?? title
        let wikibase = object["wikibase_item"] as? String
        let year = (extract ?? "").range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression)
            .flatMap { Int((extract ?? "")[$0]) }
        return WikipediaSummary(
            title: pageTitle,
            extract: extract,
            description: description,
            thumbnail: thumbnail,
            wikibaseItem: wikibase,
            year: year,
            language: language
        )
    }

    private func wikidataVerifyMovie(_ entityID: String?, year: Int?) async -> (isFilm: Bool, year: Int?) {
        guard let entityID,
              let url = URL(string: "https://www.wikidata.org/wiki/Special:EntityData/\(entityID).json"),
              let data = try? await session.data(from: url).0,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entities = root["entities"] as? [String: Any],
              let entity = entities[entityID] as? [String: Any],
              let claims = entity["claims"] as? [String: Any] else {
            return (false, nil)
        }
        let filmTypes: Set<String> = ["Q11424", "Q202866", "Q506240", "Q93204", "Q24869", "Q29168811"]
        var isFilm = false
        if let instances = claims["P31"] as? [[String: Any]] {
            for claim in instances {
                if let main = claim["mainsnak"] as? [String: Any],
                   let value = main["datavalue"] as? [String: Any],
                   let inner = value["value"] as? [String: Any],
                   let id = inner["id"] as? String, filmTypes.contains(id) {
                    isFilm = true
                }
            }
        }
        var publishedYear: Int?
        if let dates = claims["P577"] as? [[String: Any]] {
            for claim in dates {
                if let main = claim["mainsnak"] as? [String: Any],
                   let value = main["datavalue"] as? [String: Any],
                   let inner = value["value"] as? [String: Any],
                   let time = inner["time"] as? String {
                    publishedYear = Int(time.dropFirst().prefix(4))
                    break
                }
            }
        }
        return (isFilm, publishedYear)
    }

    private static func looksLikeFilm(_ summary: WikipediaSummary) -> Bool {
        let text = "\(summary.description ?? "") \(summary.extract ?? "")".lowercased()
        return text.contains("film") || text.contains("电影") || text.contains("影片")
    }

    private static func stripHTML(_ html: String?) -> String? {
        guard let html else { return nil }
        let text = html.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
