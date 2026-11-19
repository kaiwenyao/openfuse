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
        return URL(string: cleaned, relativeTo: imageBaseURL)?.absoluteURL
    }

    public func match(title: String, year: Int?, kind: LibraryKind) async -> TMDBMatch? {
        let key = "\(kind.rawValue)|\(title.lowercased())|\(year ?? 0)"
        if let cached = cache[key] { return cached }
        let result = await performSearch(title: title, year: year, kind: kind)
        cache[key] = result
        return result
    }

    private func performSearch(title: String, year: Int?, kind: LibraryKind) async -> TMDBMatch? {
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
        guard let url = components?.url else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else { return nil }
            guard (200..<300).contains(http.statusCode) else { return nil }
            let decoded = try JSONDecoder().decode(TMDBSearchResponse.self, from: data)
            return decoded.results.first.flatMap { result in
                let name = (kind == .movie ? result.title : result.name) ?? title
                let date = (kind == .movie ? result.releaseDate : result.firstAirDate) ?? ""
                let year = Int(date.prefix(4))
                return TMDBMatch(
                    id: result.id,
                    title: name,
                    year: year,
                    overview: result.overview,
                    posterPath: result.posterPath
                )
            }
        } catch {
            FileHandle.standardError.write("TMDB error: \(error)\n".data(using: .utf8)!)
            return nil
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
