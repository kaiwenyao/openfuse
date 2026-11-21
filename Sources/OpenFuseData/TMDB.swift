import Foundation

public struct TMDBMatch: Sendable {
    public var id: Int
    public var title: String
    public var year: Int?
    public var overview: String?
    public var posterPath: String?

    public init(id: Int, title: String, year: Int?, overview: String?, posterPath: String?) {
        self.id = id
        self.title = title
        self.year = year
        self.overview = overview
        self.posterPath = posterPath
    }
}

public enum TMDBError: LocalizedError, Sendable {
    case invalidURL
    case unauthorized
    case httpStatus(Int)
    case invalidResponse(String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "TMDB 地址无效"
        case .unauthorized: return "TMDB API key 无效"
        case .httpStatus(let code): return "TMDB 返回 HTTP \(code)"
        case .invalidResponse(let message): return "TMDB 响应无法解析：\(message)"
        case .network(let message): return "TMDB 网络错误：\(message)"
        }
    }
}

public actor TMDBClient {
    private let apiKey: String
    private let baseURL: URL
    private let imageBaseURL: URL
    private let language: String
    private var cache: [String: TMDBMatch?] = [:]
    private let session: URLSession
    private var detailsCache: [String: TMDBWorkDetails] = [:]
    private var seasonCache: [String: [TMDBEpisodeDetails]] = [:]

    public init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.themoviedb.org/3")!,
        imageBaseURL: URL = URL(string: "https://image.tmdb.org/t/p/w500")!,
        language: String = "zh-CN"
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.imageBaseURL = imageBaseURL
        self.language = language
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: configuration)
    }

    public nonisolated func imageURL(path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if let url = URL(string: path), url.scheme != nil { return url }
        let cleaned = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return imageBaseURL.appendingPathComponent(cleaned).absoluteURL
    }

    public func candidates(title: String, year: Int?, kind: LibraryKind, limit: Int = 5) async -> [TMDBMatch] {
        await searchResults(title: title, year: year, kind: kind, limit: limit)
    }

    public func match(title: String, year: Int?, kind: LibraryKind) async -> TMDBMatch? {
        let key = "\(kind.rawValue)|\(title.lowercased())|\(year ?? 0)"
        if let cached = cache[key] { return cached }
        let result = await searchResults(title: title, year: year, kind: kind, limit: 1).first
        cache[key] = result
        return result
    }

    private func searchResults(title: String, year: Int?, kind: LibraryKind, limit: Int) async -> [TMDBMatch] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(kind == .movie ? "search/movie" : "search/tv"),
            resolvingAgainstBaseURL: false
        )
        var query = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "query", value: title),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "include_adult", value: "false"),
        ]
        if let year {
            query.append(URLQueryItem(name: kind == .movie ? "year" : "first_air_date_year", value: String(year)))
        }
        components?.queryItems = query
        guard let url = components?.url else { return [] }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else { return [] }
            guard (200..<300).contains(http.statusCode) else { return [] }
            let decoded = try JSONDecoder().decode(TMDBSearchResponse.self, from: data)
            return decoded.results.prefix(limit).map { result in
                let name = (kind == .movie ? result.title : result.name) ?? title
                let date = (kind == .movie ? result.releaseDate : result.firstAirDate) ?? ""
                return TMDBMatch(
                    id: result.id,
                    title: name,
                    year: Int(date.prefix(4)),
                    overview: result.overview,
                    posterPath: result.posterPath
                )
            }
        } catch {
            FileHandle.standardError.write("TMDB error: \(error)\n".data(using: .utf8)!)
            return []
        }
    }
}

private struct TMDBSearchResponse: Codable {
    var results: [TMDBResult]
}

private struct TMDBResult: Codable {
    var id: Int
    var title: String?
    var name: String?
    var overview: String?
    var posterPath: String?
    var releaseDate: String?
    var firstAirDate: String?

    enum CodingKeys: String, CodingKey {
        case id, title, name, overview
        case posterPath = "poster_path"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
    }
}

public enum LibraryMetadata {
    public static func enrich(_ library: ScannedLibrary, client: TMDBClient) async -> (library: ScannedLibrary, matched: Int) {
        var works = library.works
        var matched = 0
        for index in works.indices {
            let work = works[index]
            guard work.sourceKind != "jellyfin" else { continue }
            // NFO-complete works keep their local metadata.
            if work.overview != nil, work.poster != nil { continue }
            guard let match = await client.match(title: work.title, year: work.year, kind: work.kind) else { continue }
            matched += 1
            works[index].title = match.title
            works[index].sortTitle = match.title
            works[index].year = match.year ?? work.year
            works[index].overview = match.overview ?? work.overview
            if let url = client.imageURL(path: match.posterPath) {
                works[index].poster = PosterRef.remote(url.absoluteString)
            }
        }
        works.sort { $0.sortTitle.localizedStandardCompare($1.sortTitle) == .orderedAscending }
        return (
            ScannedLibrary(sourceKind: library.sourceKind, sourceID: library.sourceID, sourceName: library.sourceName, works: works),
            matched
        )
    }
}

// MARK: - Details and season data for directory metadata

public struct TMDBWorkDetails: Sendable {
    public var id: Int
    public var kind: LibraryKind
    public var title: String
    public var year: Int?
    public var overview: String?
    public var posterPath: String?
    public var backdropPath: String?
    /// TMDB vote average, 0–10.
    public var rating: Double?
    public var voteCount: Int?
    public var imdbID: String?
    public var seasons: [TMDBSeasonSummary]

    public init(
        id: Int, kind: LibraryKind, title: String, year: Int?, overview: String?,
        posterPath: String?, backdropPath: String?, rating: Double?, voteCount: Int?,
        imdbID: String?, seasons: [TMDBSeasonSummary] = []
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.year = year
        self.overview = overview
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.rating = rating
        self.voteCount = voteCount
        self.imdbID = imdbID
        self.seasons = seasons
    }
}

public struct TMDBSeasonSummary: Sendable {
    public var seasonNumber: Int
    public var name: String
    public var episodeCount: Int
    public var posterPath: String?
}

public struct TMDBEpisodeDetails: Sendable {
    public var season: Int
    public var number: Int
    public var title: String
    public var overview: String?
    public var stillPath: String?
    public var runtime: Double
    public var airDate: String?
    public var rating: Double?
}

extension TMDBClient {
    public func details(kind: LibraryKind, id: Int) async -> TMDBWorkDetails? {
        let key = "details|\(kind.rawValue)|\(id)"
        if let cached = detailsCache[key] { return cached }
        var components = URLComponents(
            url: baseURL.appendingPathComponent(kind == .movie ? "movie/\(id)" : "tv/\(id)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "append_to_response", value: "external_ids"),
        ]
        guard let url = components?.url,
              let data = try? await data(from: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let title = (object["title"] as? String) ?? (object["name"] as? String) ?? ""
        let date = (object["release_date"] as? String) ?? (object["first_air_date"] as? String) ?? ""
        let seasons = (object["seasons"] as? [[String: Any]] ?? []).compactMap { season -> TMDBSeasonSummary? in
            guard let number = season["season_number"] as? Int else { return nil }
            return TMDBSeasonSummary(
                seasonNumber: number,
                name: season["name"] as? String ?? "第 \(number) 季",
                episodeCount: season["episode_count"] as? Int ?? 0,
                posterPath: season["poster_path"] as? String
            )
        }
        let details = TMDBWorkDetails(
            id: id,
            kind: kind,
            title: title,
            year: Int(date.prefix(4)),
            overview: object["overview"] as? String,
            posterPath: object["poster_path"] as? String,
            backdropPath: object["backdrop_path"] as? String,
            rating: (object["vote_average"] as? NSNumber)?.doubleValue,
            voteCount: object["vote_count"] as? Int,
            imdbID: (object["external_ids"] as? [String: Any])?["imdb_id"] as? String,
            seasons: seasons
        )
        detailsCache[key] = details
        return details
    }

    public func season(tvID: Int, season: Int) async -> [TMDBEpisodeDetails] {
        let key = "season|\(tvID)|\(season)"
        if let cached = seasonCache[key] { return cached }
        var components = URLComponents(
            url: baseURL.appendingPathComponent("tv/\(tvID)/season/\(season)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "language", value: language),
        ]
        guard let url = components?.url,
              let data = try? await data(from: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let episodes = object["episodes"] as? [[String: Any]]
        else { return [] }
        let result = episodes.compactMap { ep -> TMDBEpisodeDetails? in
            guard let number = ep["episode_number"] as? Int else { return nil }
            return TMDBEpisodeDetails(
                season: ep["season_number"] as? Int ?? season,
                number: number,
                title: ep["name"] as? String ?? "第 \(number) 集",
                overview: ep["overview"] as? String,
                stillPath: ep["still_path"] as? String,
                runtime: (ep["runtime"] as? NSNumber)?.doubleValue ?? 0,
                airDate: ep["air_date"] as? String,
                rating: (ep["vote_average"] as? NSNumber)?.doubleValue
            )
        }
        seasonCache[key] = result
        return result
    }

    private func data(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TMDBError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return data
    }
}
