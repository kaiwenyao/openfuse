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
    func lastFailure() async -> Bool
}

public actor PublicMetadataService: PublicMetadataProviding {
    private let session: URLSession
    private var seriesCache: [String: (DirectoryWorkMetadata, [DirectoryEpisodeMetadata])] = [:]
    private var movieCache: [String: DirectoryWorkMetadata] = [:]
    private var wikiCache: [String: WikipediaSummary?] = [:]
    private var requestFailed = false
    private let language: MetadataLanguage

    public func lastFailure() async -> Bool { requestFailed }

    private func fetch(_ url: URL) async -> Data? {
        do {
            var request = URLRequest(url: url)
            request.setValue("OpenFuse/1.0 (https://github.com/kaiwenyao/openfuse)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 500 {
                requestFailed = true
                return nil
            }
            return data
        } catch {
            requestFailed = true
            return nil
        }
    }

    public init(language: MetadataLanguage = .current()) {
        self.language = language
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
        requestFailed = false
        let key = titleCandidates.joined(separator: "|") + "|\(year ?? 0)|\(season ?? 0)|\(language.identifier)"
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
            preferredLanguages: language.wikipedia
        )
        var episodes: [DirectoryEpisodeMetadata] = []
        if let season {
            episodes = await tvmazeEpisodes(showID: show.id, season: season)
        }
        var title = wiki.map { language.localizedTitle($0.title) } ?? show.name
        let wikiOverview = wiki?.extract
        let disambiguation = wikiOverview?.lowercased().contains("usually refers to") == true
            || wikiOverview?.lowercased().contains("may refer to") == true
            || wikiOverview?.contains("可以指") == true
        var overview = disambiguation ? Self.stripHTML(show.summary) : (wikiOverview ?? Self.stripHTML(show.summary))
        var titleLanguage = wiki?.language
        var overviewLanguage = wiki?.extract != nil ? wiki?.language : "en"
        if language.isChinese || language.identifier == "ja" {
            if let bangumi = await bangumiSubject(candidates: [show.name] + titleCandidates) {
                let localizedTitle = language.identifier == "ja"
                    ? bangumi.name
                    : language.convert(bangumi.nameCN ?? bangumi.name)
                if !localizedTitle.isEmpty {
                    title = localizedTitle
                    titleLanguage = language.identifier
                }
                if language.isChinese, let summary = bangumi.summary, Self.isChineseText(summary) {
                    overview = language.convert(summary)
                    overviewLanguage = language.identifier
                }
                if let season, season == 1, !episodes.isEmpty {
                    let bangumiEpisodes = await bangumiEpisodes(subjectID: bangumi.id)
                    for index in episodes.indices {
                        guard let match = bangumiEpisodes[episodes[index].number] else { continue }
                        let localized = language.identifier == "ja"
                            ? match.name
                            : language.convert(match.nameCN ?? match.name)
                        episodes[index].title = localized
                        episodes[index].titleLanguage = language.identifier
                        episodes[index].overviewLanguage = episodes[index].overview == nil ? nil : "en"
                    }
                }
            }
        }
        let work = DirectoryWorkMetadata(
            kind: .series,
            title: title,
            year: show.premiered.flatMap { Int($0.prefix(4)) } ?? year,
            overview: overview,
            posterURL: show.image?.original ?? wiki?.thumbnail,
            backdropURL: nil,
            tmdbRating: nil,
            tmdbVotes: nil,
            imdbID: show.externals?.imdb,
            externalRatings: [],
            seasonNumbers: Array(Set(episodes.map(\.season))).sorted(),
            ratingLabels: show.rating?.average.map { [String(format: "TVmaze %.1f/10", $0)] } ?? [],
            titleLanguage: titleLanguage,
            overviewLanguage: overviewLanguage
        )
        let result = (work, episodes)
        seriesCache[key] = result
        return result
    }

    // MARK: - Movies

    public func movie(titleCandidates: [String], year: Int?) async -> DirectoryWorkMetadata? {
        requestFailed = false
        let key = titleCandidates.joined(separator: "|") + "|\(year ?? 0)|\(language.identifier)"
        if let cached = movieCache[key] { return cached }
        let queries = titleCandidates.flatMap { candidate -> [String] in
            var values = [candidate]
            if let year {
                values.append("\(candidate) \(year) 电影")
                values.append("\(candidate) \(year) film")
            }
            return values
        }
        guard var summary = await wikipediaSummary(queries: queries, preferredLanguages: language.wikipedia) else {
            return nil
        }
        let verified = await wikidataVerifyMovie(summary.wikibaseItem, year: year)
        if !verified.isFilm, !Self.looksLikeFilm(summary) { return nil }
        if let verifiedYear = verified.year, summary.year == nil {
            summary.year = verifiedYear
        }
        let work = DirectoryWorkMetadata(
            kind: .movie,
            title: language.localizedTitle(summary.title),
            year: summary.year ?? verified.year ?? year,
            overview: summary.extract,
            posterURL: summary.thumbnail,
            backdropURL: nil,
            tmdbRating: nil,
            tmdbVotes: nil,
            imdbID: nil,
            externalRatings: [],
            seasonNumbers: [],
            ratingLabels: [],
            titleLanguage: summary.language,
            overviewLanguage: summary.language
        )
        movieCache[key] = work
        return work
    }

    // MARK: - Bangumi (public, zero key)

    private struct BangumiSubject {
        var id: Int
        var name: String
        var nameCN: String?
        var summary: String?
    }

    private struct BangumiEpisode {
        var sort: Int
        var name: String
        var nameCN: String?
        var desc: String?
    }

    private func bangumiSubject(candidates: [String]) async -> BangumiSubject? {
        for candidate in candidates where !candidate.isEmpty {
            guard let encoded = candidate.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "https://api.bgm.tv/search/subject/\(encoded)?type=2&responseGroup=large"),
                  let data = await fetch(url),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = root["list"] as? [[String: Any]],
                  let first = list.first,
                  let id = first["id"] as? Int,
                  let name = first["name"] as? String else {
                continue
            }
            return BangumiSubject(
                id: id,
                name: name,
                nameCN: first["name_cn"] as? String,
                summary: first["summary"] as? String
            )
        }
        return nil
    }

    private func bangumiEpisodes(subjectID: Int) async -> [Int: BangumiEpisode] {
        guard let url = URL(string: "https://api.bgm.tv/v0/episodes?subject_id=\(subjectID)&type=0&limit=200"),
              let data = await fetch(url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["data"] as? [[String: Any]] else {
            return [:]
        }
        var result: [Int: BangumiEpisode] = [:]
        for item in list {
            let sortValue = (item["sort"] as? Double) ?? (item["sort"] as? Int).map(Double.init)
            guard let sortValue, let name = item["name"] as? String else { continue }
            let number = Int(sortValue)
            guard number > 0 else { continue }
            result[number] = BangumiEpisode(
                sort: number,
                name: name,
                nameCN: item["name_cn"] as? String,
                desc: item["desc"] as? String
            )
        }
        return result
    }

    private static func isChineseText(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let scalars = text.unicodeScalars
        var han = 0
        var kana = 0
        for scalar in scalars {
            if (0x4E00...0x9FFF).contains(scalar.value) { han += 1 }
            if (0x3040...0x30FF).contains(scalar.value) { kana += 1 }
        }
        return han >= 12 && Double(kana) / Double(max(1, scalars.count)) < 0.18
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
              let data = await fetch(url),
              let results = try? JSONDecoder().decode([TVmazeSearchResult].self, from: data) else {
            return []
        }
        return results.map(\.show)
    }

    private func tvmazeEpisodes(showID: Int, season: Int) async -> [DirectoryEpisodeMetadata] {
        guard let url = URL(string: "https://api.tvmaze.com/shows/\(showID)/episodes?specials=1"),
              let data = await fetch(url),
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
                rating: nil,
                titleLanguage: "en",
                overviewLanguage: episode.summary == nil ? nil : "en"
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
              let data = await fetch(searchURL),
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
        var components = URLComponents(string: "https://\(language).wikipedia.org/w/api.php")!
        var items = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "prop", value: "extracts|pageimages|pageprops"),
            URLQueryItem(name: "exintro", value: "1"),
            URLQueryItem(name: "explaintext", value: "1"),
            URLQueryItem(name: "redirects", value: "1"),
            URLQueryItem(name: "pithumbsize", value: "600"),
            URLQueryItem(name: "titles", value: title),
            URLQueryItem(name: "format", value: "json"),
        ]
        if language == "zh" {
            items.append(URLQueryItem(name: "variant", value: languageVariant))
            items.append(URLQueryItem(name: "converttitles", value: "1"))
        }
        components.queryItems = items
        guard let url = components.url,
              let data = await fetch(url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let query = root["query"] as? [String: Any],
              let pages = query["pages"] as? [String: Any],
              let page = pages.values.first as? [String: Any],
              page["missing"] == nil else {
            return nil
        }
        let extract = page["extract"] as? String
        let pageTitle = page["title"] as? String ?? title
        let thumbnail = (page["thumbnail"] as? [String: Any])?["source"] as? String
        let pageprops = page["pageprops"] as? [String: Any]
        let wikibase = pageprops?["wikibase_item"] as? String
        let year = (extract ?? "").range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression)
            .flatMap { Int((extract ?? "")[$0]) }
        var resolvedTitle = self.language.localizedTitle(pageTitle)
        if self.language.isChinese, let extract,
           let range = extract.range(of: #"《[^》]+》"#, options: .regularExpression) {
            resolvedTitle = String(extract[range]).trimmingCharacters(in: CharacterSet(charactersIn: "《》"))
        }
        return WikipediaSummary(
            title: resolvedTitle,
            extract: extract,
            description: nil,
            thumbnail: thumbnail,
            wikibaseItem: wikibase,
            year: year,
            language: language
        )
    }

    private var languageVariant: String {
        language.isTraditionalChinese ? "zh-hant" : "zh-hans"
    }

    private func wikidataVerifyMovie(_ entityID: String?, year: Int?) async -> (isFilm: Bool, year: Int?) {
        guard let entityID,
              let url = URL(string: "https://www.wikidata.org/wiki/Special:EntityData/\(entityID).json"),
              let data = await fetch(url),
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
