import XCTest
@testable import OpenFuseData

final class MetadataTests: XCTestCase {
    func testOMDbLabelsIncludeSourceAndScale() {
        let ratings = OMDbRatings(imdb: 9.2, rottenTomatoes: 89, metacritic: 86, imdbID: "tt0944947", title: "Game of Thrones")
        XCTAssertEqual(ratings.labels, ["IMDb 9.2/10", "烂番茄 89%", "Metacritic 86/100"])
        let missing = OMDbRatings(imdb: 8.8, rottenTomatoes: nil, metacritic: nil, imdbID: "tt1375666", title: nil)
        XCTAssertEqual(missing.labels, ["IMDb 8.8/10"])
    }

    func testTMDBImageURLKeepsBasePath() {
        let client = TMDBClient(
            apiKey: "test",
            imageBaseURL: URL(string: "https://image.example/t/p/w500")!
        )
        XCTAssertEqual(
            client.imageURL(path: "/poster.jpg")?.absoluteString,
            "https://image.example/t/p/w500/poster.jpg"
        )
        XCTAssertEqual(
            client.imageURL(path: "https://cdn.example/a.jpg")?.absoluteString,
            "https://cdn.example/a.jpg"
        )
    }

    func testEpisodeKeyAndLabel() {
        let episode = DirectoryEpisodeMetadata(
            season: 3, number: 13, title: "地下室", overview: nil,
            stillURL: nil, runtime: 24, rating: 8.9
        )
        XCTAssertEqual(episode.key, "S03E13")
        XCTAssertEqual(episode.label, "S03E13")
    }

    func testDirectoryMetadataEpisodeLookup() {
        let work = DirectoryWorkMetadata(
            kind: .series, title: "Game of Thrones", year: 2011, overview: nil,
            posterURL: nil, backdropURL: nil, tmdbRating: 8.4, tmdbVotes: 22000,
            imdbID: "tt0944947", externalRatings: ["IMDb 9.2/10"], seasonNumbers: [1]
        )
        let ep = DirectoryEpisodeMetadata(
            season: 1, number: 2, title: "The Kingsroad", overview: nil,
            stillURL: nil, runtime: 55, rating: 8.2
        )
        let metadata = DirectoryMetadata(work: work, episodes: [ep], sourceLabel: "TMDB", updatedAt: Date())
        XCTAssertEqual(metadata.episode(season: 1, number: 2)?.title, "The Kingsroad")
        XCTAssertNil(metadata.episode(season: 1, number: 3))
        XCTAssertEqual(metadata.work.allRatings, ["TMDB 8.4/10", "IMDb 9.2/10"])
    }
}
