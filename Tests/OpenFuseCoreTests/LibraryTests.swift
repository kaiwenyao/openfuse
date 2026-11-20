import XCTest
@testable import OpenFuseCore
@testable import OpenFuseData

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
        var webdav = other
        webdav.title = "示例剧 · WebDAV NFO"
        XCTAssertEqual(webdav.mergeKey, plain.mergeKey)
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

    func testLibraryOverrideStoreAndApply() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("openfuse-override-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LibraryOverrideStore(directory: directory)
        let override = LibraryOverride(
            workID: "w1", title: "人工标题", year: 2024, overview: "人工简介",
            poster: PosterRef.remote("https://example.com/p.jpg")
        )
        try store.upsert(override)
        let reopened = try LibraryOverrideStore(directory: directory)
        XCTAssertEqual(reopened.all["w1"]?.title, "人工标题")

        let work = LibraryWork(
            id: "w1", kind: .movie, title: "Original", sortTitle: "Original", year: 2026,
            overview: nil, poster: nil, sourceKind: "local", sourceID: "s",
            serverID: nil, seasonCount: 0, episodeCount: 1, addedAt: Date()
        )
        let applied = override.apply(to: work)
        XCTAssertEqual(applied.title, "人工标题")
        XCTAssertEqual(applied.year, 2024)
        XCTAssertEqual(applied.overview, "人工简介")
        XCTAssertEqual(applied.poster, "remote:https://example.com/p.jpg")
        try reopened.remove(workID: "w1")
        XCTAssertNil(try LibraryOverrideStore(directory: directory).all["w1"])
    }

    func testReplacePreservesFailedRemotePrefix() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("openfuse-recovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LibraryStore(directory: directory)

        func episode(_ id: String, remote: String) -> ScannedEpisode {
            ScannedEpisode(
                id: id, seasonNumber: 1, episodeNumber: 1, title: id,
                overview: nil, runtime: 60, poster: nil, serverID: nil,
                remotePath: remote, remoteVariant: nil, fileURL: nil,
                versions: [ScannedVersion(
                    id: id + "-v", name: "WebDAV", mediaSourceID: nil,
                    container: "MKV", resolution: nil, remotePath: remote, fileURL: nil
                )]
            )
        }
        let movie = ScannedWork(
            id: "movie", kind: .movie, title: "Movie", sortTitle: "Movie", year: 2026,
            overview: nil, poster: nil, sourceKind: "webdav", sourceID: "s", serverID: nil,
            addedAt: nil, seasons: [],
            movie: episode("movie-main", remote: "Movies/Movie.mkv")
        )
        let series = ScannedWork(
            id: "series", kind: .series, title: "Series", sortTitle: "Series", year: 2026,
            overview: nil, poster: nil, sourceKind: "webdav", sourceID: "s", serverID: nil,
            addedAt: nil,
            seasons: [ScannedSeason(
                id: "season", number: 1, title: "S1", poster: nil,
                episodes: [episode("series-s1e1", remote: "Shows/Series/S01E01.mkv")]
            )],
            movie: nil
        )
        try store.replace(source: ScannedLibrary(
            sourceKind: "webdav", sourceID: "s", sourceName: "webdav",
            works: [movie, series]
        ))
        try store.replace(
            source: ScannedLibrary(
                sourceKind: "webdav", sourceID: "s", sourceName: "webdav",
                works: [movie]
            ),
            preservingRemotePrefixes: ["Shows/Series"]
        )
        let works = try store.works()
        XCTAssertEqual(works.count, 2)
        XCTAssertTrue(works.contains { $0.id == "series" })
        XCTAssertTrue(works.contains { $0.id == "movie" })
    }

    func testMergedEpisodesCombineSourcesAndVersions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("openfuse-merge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LibraryStore(directory: directory)

        func movieWork(id: String, sourceKind: String, sourceID: String, title: String) -> ScannedWork {
            ScannedWork(
                id: id, kind: .movie, title: title, sortTitle: title, year: 2026,
                overview: nil, poster: nil, sourceKind: sourceKind, sourceID: sourceID,
                serverID: nil, seasons: [],
                movie: ScannedEpisode(
                    id: id + "-main", seasonNumber: 0, episodeNumber: 1, title: title,
                    overview: nil, runtime: 60, poster: nil, serverID: nil,
                    remotePath: nil, remoteVariant: nil, fileURL: nil,
                    versions: [ScannedVersion(
                        id: id + "-v", name: sourceKind == "jellyfin" ? "1080p" : "本地文件",
                        mediaSourceID: sourceKind == "jellyfin" ? "ms1" : nil,
                        container: "MKV", resolution: nil,
                        remotePath: sourceKind == "webdav" ? "movie.mkv" : nil,
                        fileURL: sourceKind == "local" ? "file:///tmp/movie.mkv" : nil
                    )]
                )
            )
        }
        try store.replace(source: ScannedLibrary(
            sourceKind: "local", sourceID: "s", sourceName: "local",
            works: [movieWork(id: "local", sourceKind: "local", sourceID: "s", title: "OpenFuse Fixture")]
        ))
        try store.replace(source: ScannedLibrary(
            sourceKind: "jellyfin", sourceID: "j", sourceName: "jf",
            works: [movieWork(id: "jf", sourceKind: "jellyfin", sourceID: "j", title: "OpenFuse Fixture (2026)")]
        ))
        let works = try store.works()
        let primary = works.first { $0.sourceKind == "jellyfin" }!
        let local = works.first { $0.sourceKind == "local" }!
        let group = LibraryGroup(id: primary.id, key: primary.mergeKey, primary: primary, works: [primary, local])
        let merged = try LibraryAggregation.mergedEpisodes(group: group, store: store)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].versions.count, 2)
        XCTAssertEqual(Set(merged[0].versions.map { $0.label.split(separator: "·").first.map(String.init) ?? "" }),
                       ["Jellyfin ", "本地 "])
    }

    func testVersionDedupeMergesJellyfinAndEmby() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("openfuse-version-dedupe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LibraryStore(directory: directory)

        func work(kind: String, sourceID: String) -> ScannedWork {
            let episodeID = "dup-main-\(kind)"
            return ScannedWork(
                id: "dup-\(kind)", kind: .movie, title: "Dup Movie", sortTitle: "Dup Movie",
                year: 2026, overview: nil, poster: nil, sourceKind: kind, sourceID: sourceID,
                serverID: "movie-dup", seasons: [],
                movie: ScannedEpisode(
                    id: episodeID, seasonNumber: 0, episodeNumber: 1, title: "Dup Movie",
                    overview: nil, runtime: 60, poster: nil, serverID: "movie-dup",
                    remotePath: "movie-dup", remoteVariant: nil, fileURL: nil,
                    versions: [ScannedVersion(
                        id: episodeID + "-v0", name: "1080p HEVC 5.1",
                        mediaSourceID: "ms-movie-1080", container: "MKV",
                        resolution: "1080p", remotePath: "movie-dup", fileURL: nil
                    )]
                )
            )
        }
        try store.replace(source: ScannedLibrary(
            sourceKind: "jellyfin", sourceID: "j", sourceName: "Jellyfin",
            works: [work(kind: "jellyfin", sourceID: "j")]
        ))
        try store.replace(source: ScannedLibrary(
            sourceKind: "emby", sourceID: "e", sourceName: "Emby",
            works: [work(kind: "emby", sourceID: "e")]
        ))
        let works = try store.works()
        let primary = works.first { $0.sourceKind == "jellyfin" }!
        let group = LibraryGroup(id: primary.id, key: primary.mergeKey, primary: primary, works: works)
        let merged = try LibraryAggregation.mergedEpisodes(group: group, store: store)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].versions.count, 1)
        XCTAssertTrue(merged[0].versions[0].label.contains("Jellyfin/Emby"))
    }

    func testNFODataParsingKeepsRemotePosterReference() throws {
        let xml = """
        <movie><title>远程电影</title><year>2026</year><plot>简介</plot><poster>poster.jpg</poster></movie>
        """
        let metadata = try XCTUnwrap(NFOReader.parse(
            data: xml.data(using: .utf8)!,
            baseURL: URL(fileURLWithPath: "/remote/Movies/Movie")
        ))
        XCTAssertEqual(metadata.title, "远程电影")
        XCTAssertEqual(metadata.overview, "简介")
        XCTAssertEqual(metadata.posterReference, "poster.jpg")
        XCTAssertNil(metadata.posterPath)
    }

    func testSubtitleCueParsers() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("openfuse-cues-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let srt = """
        1
        00:00:02,500 --> 00:00:06,200
        第一句：简体

        2
        00:00:09,000 --> 00:00:13,500
        第二句
        """
        let srtURL = directory.appendingPathComponent("a.zh-Hans.srt")
        try srt.write(to: srtURL, atomically: true, encoding: .utf8)
        let cues = try SubtitleParser.parse(url: srtURL)
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].start, 2.5, accuracy: 0.001)
        XCTAssertEqual(cues[0].text, "第一句：简体")

        let ass = #"""
        [Events]
        Dialogue: 0,0:00:02.50,0:00:06.20,Default,,0,0,0,,{\an8}<b>最初の字幕</b>\N第二行
        """#
        let assURL = directory.appendingPathComponent("a.ass")
        try ass.write(to: assURL, atomically: true, encoding: .utf8)
        let assCues = try SubtitleParser.parse(url: assURL)
        XCTAssertEqual(assCues.first?.text, "最初の字幕\n第二行")
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
