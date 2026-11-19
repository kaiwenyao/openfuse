import XCTest
@testable import OpenFuseCore

final class LibraryTests: XCTestCase {
    func testFilenameParsing() {
        let movie = MediaNameParser.parse(
            fileURL: URL(fileURLWithPath: "OpenFuse Fixture (2026).mkv"),
            relativePath: "Movies/OpenFuse Fixture (2026)/OpenFuse Fixture (2026).mkv"
        )
        XCTAssertEqual(movie.kind, .movie)
        XCTAssertEqual(movie.showTitle, "OpenFuse Fixture")
        XCTAssertEqual(movie.year, 2026)

        let episode = MediaNameParser.parse(
            fileURL: URL(fileURLWithPath: "示例剧.S01E02.1080p.mkv"),
            relativePath: "Shows/示例剧/Season 01/示例剧.S01E02.1080p.mkv"
        )
        XCTAssertEqual(episode.kind, .series)
        XCTAssertEqual(episode.showTitle, "示例剧")
        XCTAssertEqual(episode.season, 1)
        XCTAssertEqual(episode.episode, 2)

        let episode2 = MediaNameParser.parse(
            fileURL: URL(fileURLWithPath: "Show - 2x03 - Name.mkv"),
            relativePath: "Show/Show - 2x03 - Name.mkv"
        )
        XCTAssertEqual(episode2.showTitle, "Show")
        XCTAssertEqual(episode2.season, 2)
        XCTAssertEqual(episode2.episode, 3)
        XCTAssertEqual(episode2.episodeTitle, "Name")
    }

    func testPosterRefsAndMergeKey() {
        XCTAssertEqual(PosterRef.parse("remote:https://example.com/poster.jpg")?.kind, "remote")
        XCTAssertEqual(PosterRef.parse("jellyfin:movie-1|tag")?.value, "movie-1")
        XCTAssertEqual(PosterRef.parse("jellyfin:movie-1|tag")?.extra, "tag")
        let movie = LibraryWork(
            id: "m", kind: .movie, title: "OpenFuse Fixture (2026)", sortTitle: "OpenFuse Fixture",
            year: 2026, overview: nil, poster: nil, sourceKind: "local", sourceID: "s",
            serverID: nil, seasonCount: 0, episodeCount: 1, addedAt: Date()
        )
        let other = LibraryWork(
            id: "n", kind: .movie, title: "OpenFuse Fixture", sortTitle: "OpenFuse Fixture",
            year: nil, overview: nil, poster: nil, sourceKind: "webdav", sourceID: "w",
            serverID: nil, seasonCount: 0, episodeCount: 1, addedAt: Date()
        )
        XCTAssertEqual(movie.mergeKey, other.mergeKey)
        XCTAssertEqual(movie.normalizedTitle, "OpenFuse Fixture")
        var enriched = movie
        enriched.title = "OpenFuse Fixture: TMDB Cut"
        XCTAssertEqual(enriched.mergeKey, movie.mergeKey)
        var localized = other
        localized.title = "示例剧：TMDB 版"
        var plain = other
        plain.title = "示例剧"
        XCTAssertEqual(localized.mergeKey, plain.mergeKey)
    }

    func testStoreRoundTripSearchAndReplace() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("openfuse-library-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try LibraryStore(directory: directory)
        let movie = ScannedWork(
            id: "w1", kind: .movie, title: "OpenFuse Fixture", sortTitle: "OpenFuse Fixture",
            year: 2026, overview: "test", poster: PosterRef.file("/tmp/poster.jpg"),
            sourceKind: "local", sourceID: "src1", serverID: nil, seasons: [],
            movie: ScannedEpisode(
                id: "e1", seasonNumber: 0, episodeNumber: 1, title: "OpenFuse Fixture",
                overview: nil, runtime: 60, poster: nil, serverID: nil, remotePath: nil,
                remoteVariant: nil, fileURL: "file:///tmp/a.mkv",
                versions: [ScannedVersion(id: "v1", name: "本地文件", mediaSourceID: nil, container: "MKV", resolution: nil, remotePath: nil, fileURL: "file:///tmp/a.mkv")]
            )
        )
        let series = ScannedWork(
            id: "w2", kind: .series, title: "示例剧", sortTitle: "示例剧", year: nil,
            overview: nil, poster: nil, sourceKind: "local", sourceID: "src1", serverID: nil,
            seasons: [ScannedSeason(id: "s1", number: 1, title: "第 1 季", poster: nil, episodes: [
                ScannedEpisode(id: "e2", seasonNumber: 1, episodeNumber: 1, title: "第 1 集", overview: nil,
                               runtime: 60, poster: nil, serverID: nil, remotePath: nil, remoteVariant: nil,
                               fileURL: "file:///tmp/b.mkv",
                               versions: [ScannedVersion(id: "v2", name: "本地文件", mediaSourceID: nil, container: "MKV", resolution: nil, remotePath: nil, fileURL: "file:///tmp/b.mkv")])
            ])],
            movie: nil
        )
        try store.replace(source: ScannedLibrary(sourceKind: "local", sourceID: "src1", sourceName: "fixture", works: [series, movie]))
        let works = try store.works()
        XCTAssertEqual(works.count, 2)
        XCTAssertEqual(works.first(where: { $0.id == "w2" })?.episodeCount, 1)
        XCTAssertEqual(try store.works(search: "示例").map(\.id), ["w2"])
        XCTAssertEqual(try store.episodes(workID: "w2").count, 1)
        XCTAssertEqual(try store.versions(itemID: "e1").first?.container, "MKV")

        // Replacing the source removes old rows but keeps other sources.
        try store.replace(source: ScannedLibrary(sourceKind: "local", sourceID: "src1", sourceName: "fixture", works: [movie]))
        XCTAssertEqual(try store.works().map(\.id), ["w1"])
        XCTAssertEqual(try store.counts().episodes, 1)
    }

    func testNFOReader() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("openfuse-nfo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let poster = directory.appendingPathComponent("poster.jpg")
        try Data().write(to: poster)
        let nfo = """
        <tvshow><title>本地 NFO 剧名</title><year>2024</year><plot>本地简介</plot><poster>poster.jpg</poster></tvshow>
        """
        try nfo.write(to: directory.appendingPathComponent("tvshow.nfo"), atomically: true, encoding: .utf8)
        let metadata = try XCTUnwrap(NFOReader.readShow(showDirectory: directory))
        XCTAssertEqual(metadata.title, "本地 NFO 剧名")
        XCTAssertEqual(metadata.year, 2024)
        XCTAssertEqual(metadata.overview, "本地简介")
        XCTAssertEqual(metadata.posterPath, poster.path)
    }

    func testLocalScannerGroupsSeriesAndMovies() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("openfuse-scan-\(UUID().uuidString)", isDirectory: true)
        let showDir = directory.appendingPathComponent("Shows/示例剧/Season 01", isDirectory: true)
        let movieDir = directory.appendingPathComponent("Movies/OpenFuse Fixture (2026)", isDirectory: true)
        try FileManager.default.createDirectory(at: showDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: movieDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data().write(to: showDir.appendingPathComponent("示例剧.S01E01.mkv"))
        try Data().write(to: showDir.appendingPathComponent("示例剧.S01E02.mkv"))
        try Data().write(to: movieDir.appendingPathComponent("OpenFuse Fixture (2026).mkv"))
        try Data().write(to: movieDir.appendingPathComponent("poster.jpg"))

        let library = try LibraryScanner.scanLocal(directory: directory)
        XCTAssertEqual(library.works.count, 2)
        let series = try XCTUnwrap(library.works.first { $0.kind == .series })
        XCTAssertEqual(series.title, "示例剧")
        XCTAssertEqual(series.seasons.first?.episodes.count, 2)
        let movie = try XCTUnwrap(library.works.first { $0.kind == .movie })
        XCTAssertEqual(movie.year, 2026)
        XCTAssertNotNil(movie.poster)
    }
}
