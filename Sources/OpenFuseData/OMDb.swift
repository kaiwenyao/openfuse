import Foundation

public struct OMDbRatings: Sendable {
    public var imdb: Double?
    public var rottenTomatoes: Int?
    public var metacritic: Int?
    public var imdbID: String
    public var title: String?

    /// User-facing, source-labelled values. Missing services are omitted.
    public var labels: [String] {
        var result: [String] = []
        if let imdb { result.append("IMDb \(String(format: "%.1f", imdb))/10") }
        if let rottenTomatoes { result.append("烂番茄 \(rottenTomatoes)%") }
        if let metacritic { result.append("Metacritic \(metacritic)/100") }
        return result
    }
}

public actor OMDbClient {
    private let apiKey: String
    private let baseURL: URL
    private let session: URLSession
    private var cache: [String: OMDbRatings?] = [:]

    public init(
        apiKey: String,
        baseURL: URL = URL(string: "https://www.omdbapi.com/")!
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        self.session = URLSession(configuration: configuration)
    }

    public func ratings(imdbID: String) async -> OMDbRatings? {
        guard !imdbID.isEmpty else { return nil }
        if let cached = cache[imdbID] { return cached }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "i", value: imdbID),
            URLQueryItem(name: "plot", value: "short"),
        ]
        guard let url = components?.url,
              let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (object["Response"] as? String) != "False"
        else {
            cache[imdbID] = OMDbRatings?.none
            return nil
        }
        let ratings = object["Ratings"] as? [[String: Any]] ?? []
        var rt: Int?
        for rating in ratings {
            guard let source = rating["Source"] as? String,
                  let value = rating["Value"] as? String else { continue }
            if source.contains("Rotten Tomatoes") {
                rt = Int(value.replacingOccurrences(of: "%", with: ""))
            }
        }
        let result = OMDbRatings(
            imdb: (object["imdbRating"] as? String).flatMap(Double.init),
            rottenTomatoes: rt,
            metacritic: (object["Metascore"] as? String).flatMap(Int.init),
            imdbID: imdbID,
            title: object["Title"] as? String
        )
        cache[imdbID] = result
        return result
    }
}
