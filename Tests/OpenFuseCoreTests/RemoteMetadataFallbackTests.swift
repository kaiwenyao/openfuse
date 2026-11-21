import XCTest
@testable import OpenFuseData

private struct EmptyResolver: PublicMetadataProviding {
    func series(titleCandidates: [String], year: Int?, season: Int?) async -> (work: DirectoryWorkMetadata, episodes: [DirectoryEpisodeMetadata])? { nil }
    func movie(titleCandidates: [String], year: Int?) async -> DirectoryWorkMetadata? { nil }
    func lastFailure() async -> Bool { false }
}

private struct FailingResolver: PublicMetadataProviding {
    func series(titleCandidates: [String], year: Int?, season: Int?) async -> (work: DirectoryWorkMetadata, episodes: [DirectoryEpisodeMetadata])? { nil }
    func movie(titleCandidates: [String], year: Int?) async -> DirectoryWorkMetadata? { nil }
    func lastFailure() async -> Bool { true }
}

private struct PartialResolver: PublicMetadataProviding {
    func series(titleCandidates: [String], year: Int?, season: Int?) async -> (work: DirectoryWorkMetadata, episodes: [DirectoryEpisodeMetadata])? {
        (DirectoryWorkMetadata(kind: .series, title: "Partial", year: nil, overview: nil, posterURL: nil,
                               backdropURL: nil, tmdbRating: nil, tmdbVotes: nil, imdbID: nil,
                               externalRatings: [], seasonNumbers: [], ratingLabels: []), [])
    }
    func movie(titleCandidates: [String], year: Int?) async -> DirectoryWorkMetadata? { nil }
    func lastFailure() async -> Bool { false }
}

private struct PerMovieResolver: PublicMetadataProviding {
    func series(titleCandidates: [String], year: Int?, season: Int?) async -> (work: DirectoryWorkMetadata, episodes: [DirectoryEpisodeMetadata])? { nil }
    func lastFailure() async -> Bool { false }
    func movie(titleCandidates: [String], year: Int?) async -> DirectoryWorkMetadata? {
        guard let title = titleCandidates.first else { return nil }
        return DirectoryWorkMetadata(
            kind: .movie, title: "Matched \(title)", year: year,
            overview: "Overview \(title)", posterURL: nil, backdropURL: nil,
            tmdbRating: nil, tmdbVotes: nil, imdbID: nil,
            externalRatings: [], seasonNumbers: [], ratingLabels: []
        )
    }
}

final class RemoteMetadataFallbackTests: XCTestCase {
    private func temp() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("of-meta-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func entry(_ name: String) -> RemoteEntry {
        RemoteEntry(
            path: "Shows/Season 01/\(name)",
            name: name,
            url: URL(string: "http://example.test/\(name)")!,
            isDirectory: false,
            size: 100,
            contentType: "video/x-matroska",
            modifiedAt: nil
        )
    }

    func testNFOParserReadsPlot() {
        let xml = "<tvshow><title>Xyzzy Local Show</title><year>2099</year><plot>Only the local NFO plot.</plot></tvshow>"
        let parsed = NFOReader.parse(data: Data(xml.utf8), baseURL: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(parsed?.title, "Xyzzy Local Show")
        XCTAssertEqual(parsed?.overview, "Only the local NFO plot.")
    }

    func testNFOIsReturnedWithoutTMDBOrResolver() async {
        let nfo = NFOMetadata(title: "NFO 剧名", year: 2013, overview: "NFO 简介", posterURL: nil)
        let service = RemoteMetadataService(tmdb: nil, omdb: nil, cacheDirectory: temp(), publicResolver: EmptyResolver())
        let metadata = await service.metadata(
            sourceID: "src",
            directoryPath: "Attack on Titan (2013)/Season 01",
            entries: [entry("Shingeki no Kyojin - S01E01.mkv")],
            nfo: nfo
        )
        XCTAssertEqual(metadata?.work.title, "NFO 剧名")
        XCTAssertEqual(metadata?.work.year, 2013)
        XCTAssertEqual(metadata?.work.overview, "NFO 简介")
        XCTAssertEqual(metadata?.sourceLabel, "本地资料")
    }

    func testNoCandidatesIsDistinguished() async {
        let service = RemoteMetadataService(tmdb: nil, omdb: nil, cacheDirectory: temp(), publicResolver: EmptyResolver())
        let metadata = await service.metadata(sourceID: "src", directoryPath: "Shows/Season 01", entries: [entry("Show - S01E01.mkv")])
        XCTAssertEqual(metadata?.matchState, "noCandidates")
        XCTAssertEqual(metadata?.matchNote, "未找到公开候选，显示本地资料")
    }

    func testNetworkFailureIsDistinguished() async {
        let service = RemoteMetadataService(tmdb: nil, omdb: nil, cacheDirectory: temp(), publicResolver: FailingResolver())
        let metadata = await service.metadata(sourceID: "src", directoryPath: "Shows/Season 01", entries: [entry("Show - S01E01.mkv")])
        XCTAssertEqual(metadata?.matchState, "networkFailure")
    }

    func testPartialMatchIsDistinguished() async {
        let service = RemoteMetadataService(tmdb: nil, omdb: nil, cacheDirectory: temp(), publicResolver: PartialResolver())
        let metadata = await service.metadata(sourceID: "src", directoryPath: "Shows/Season 01", entries: [entry("Show - S01E01.mkv")])
        XCTAssertEqual(metadata?.matchState, "partial")
        XCTAssertEqual(metadata?.matchNote, "匹配成功，部分字段缺失")
    }

    func testManualMatchWinsOverNFO() async {
        let nfo = NFOMetadata(title: "NFO 剧名", year: 2013, overview: "NFO 简介", posterURL: nil)
        let service = RemoteMetadataService(tmdb: nil, omdb: nil, cacheDirectory: temp(), publicResolver: EmptyResolver())
        let metadata = await service.metadata(
            sourceID: "src",
            directoryPath: "Shows/Season 01",
            entries: [entry("Show - S01E01.mkv")],
            nfo: nfo,
            matchTitle: "Manual Match",
            matchYear: 2014
        )
        XCTAssertEqual(metadata?.work.title, "Manual Match")
        XCTAssertEqual(metadata?.work.year, 2014)
    }

    func testEveryMovieGetsItsOwnWork() async {
        let service = RemoteMetadataService(tmdb: nil, omdb: nil, cacheDirectory: temp(), publicResolver: PerMovieResolver())
        let entries = [entry("Inception.2010.mkv"), entry("Interstellar.2014.mkv")]
        let metadata = await service.metadata(
            sourceID: "src",
            directoryPath: "Movies",
            entries: entries
        )
        XCTAssertEqual(metadata?.movieWorks?.count, 2)
        XCTAssertEqual(metadata?.movieWorks?["Shows/Season 01/Inception.2010.mkv"]?.title, "Matched Inception")
        XCTAssertEqual(metadata?.movieWorks?["Shows/Season 01/Interstellar.2014.mkv"]?.title, "Matched Interstellar")
    }
}
