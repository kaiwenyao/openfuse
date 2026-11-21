import XCTest
@testable import OpenFuseData

final class FolderVideosTests: XCTestCase {
    func testNaturalEpisodeOrderAndNaming() {
        let entries = [
            RemoteEntry(path: "/Shows/Game/Season 1/S01E10.mkv", name: "S01E10.mkv", url: URL(string: "https://x/10")!, isDirectory: false),
            RemoteEntry(path: "/Shows/Game/Season 1/S01E02 - The Kingsroad.mkv", name: "S01E02 - The Kingsroad.mkv", url: URL(string: "https://x/2")!, isDirectory: false),
            RemoteEntry(path: "/Shows/Game/Season 1/S01E01.mkv", name: "S01E01.mkv", url: URL(string: "https://x/1")!, isDirectory: false),
        ]
        let videos = FolderVideoBuilder.webdav(entries: entries, currentPath: "/Shows/Game/Season 1/S01E01.mkv")
        XCTAssertEqual(videos.map(\.episodeNumber), [1, 2, 10])
        XCTAssertEqual(videos[1].episodeLabel, "S1 · E2")
        XCTAssertEqual(videos[1].displayTitle, "The Kingsroad")
        XCTAssertTrue(videos[1].subtitle.contains("Game"))
    }

    func testFiltersSubtitlesImagesNFOAndSubdirectories() {
        let entries = [
            RemoteEntry(path: "/Movies/Film/Film.mkv", name: "Film.mkv", url: URL(string: "https://x/f")!, isDirectory: false),
            RemoteEntry(path: "/Movies/Film/Film.srt", name: "Film.srt", url: URL(string: "https://x/s")!, isDirectory: false),
            RemoteEntry(path: "/Movies/Film/poster.jpg", name: "poster.jpg", url: URL(string: "https://x/p")!, isDirectory: false),
            RemoteEntry(path: "/Movies/Film/Film.nfo", name: "Film.nfo", url: URL(string: "https://x/n")!, isDirectory: false),
            RemoteEntry(path: "/Movies/Film/Sub/Film2.mkv", name: "Film2.mkv", url: URL(string: "https://x/f2")!, isDirectory: false),
        ]
        let videos = FolderVideoBuilder.webdav(entries: entries, currentPath: "/Movies/Film/Film.mkv")
        XCTAssertEqual(videos.count, 1)
        XCTAssertEqual(videos[0].path, "/Movies/Film/Film.mkv")
    }

    func testDuplicateVersionsAreKeptAndDisambiguated() {
        let entries = [
            RemoteEntry(path: "/Movies/Film/Film.1080p.mkv", name: "Film.1080p.mkv", url: URL(string: "https://x/1")!, isDirectory: false),
            RemoteEntry(path: "/Movies/Film/Film.2160p.mkv", name: "Film.2160p.mkv", url: URL(string: "https://x/2")!, isDirectory: false),
        ]
        let videos = FolderVideoBuilder.webdav(entries: entries, currentPath: "/Movies/Film/Film.1080p.mkv")
        XCTAssertEqual(videos.count, 2)
        XCTAssertTrue(videos.contains { $0.displayTitle.contains("1080p") })
        XCTAssertTrue(videos.contains { $0.displayTitle.contains("2160p") })
    }

    func testMovieYearAndEpisodeTitle() {
        let movie = VideoNaming.parse(fileName: "Inception.2010.1080p.mkv", parentFolder: "Inception")
        XCTAssertEqual(movie.movieTitle, "Inception")
        XCTAssertEqual(movie.year, 2010)
        XCTAssertEqual(movie.resolution, "1080p")

        let episode = VideoNaming.parse(
            fileName: "Game.of.Thrones.S01E02.The.Kingsroad.1080p.BluRay.mkv",
            parentFolder: "Season 1"
        )
        XCTAssertEqual(episode.season, 1)
        XCTAssertEqual(episode.episode, 2)
        XCTAssertEqual(episode.episodeTitle, "The Kingsroad")
        XCTAssertEqual(episode.showTitle, "")
        XCTAssertEqual(episode.resolution, "1080p")
    }
}

extension FolderVideosTests {
    func testParsedShowTitleFromAbsoluteSeasonPath() {
        let parsed = VideoNaming.parse(
            fileName: "Game.of.Thrones.S01E02.The.Kingsroad.1080p.mkv",
            parentFolder: "/tmp/of/folder/Game of Thrones/Season 1"
        )
        XCTAssertEqual(parsed.showTitle, "Game of Thrones")
        XCTAssertEqual(parsed.episodeTitle, "The Kingsroad")
    }
}
