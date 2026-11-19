import XCTest
@testable import OpenFuseCore

final class SubtitleCatalogTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("openfuse-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func touch(_ name: String) throws {
        let url = directory.appendingPathComponent(name)
        try Data().write(to: url)
    }

    func testDiscoversLanguageTaggedSidecarsAndSortsChineseFirst() throws {
        try touch("Movie.mkv")
        try touch("Movie.ass")
        try touch("Movie.zh-Hant.ass")
        try touch("Movie.zh-Hans.ass")
        try touch("Movie.ja.srt")
        try touch("Movie.eng.forced.vtt")
        try touch("OtherMovie.zh-Hans.ass")

        let tracks = SubtitleCatalog.discover(for: directory.appendingPathComponent("Movie.mkv"))
        XCTAssertEqual(tracks.count, 5)
        XCTAssertEqual(tracks[0].language, "zh-Hans")
        XCTAssertEqual(tracks[0].displayName, "中文（简体） (ASS)")
        XCTAssertEqual(tracks[1].language, "zh-Hant")
        XCTAssertEqual(tracks[2].language, "ja")
        XCTAssertEqual(tracks[3].language, "en")
        XCTAssertTrue(tracks[3].isForced)
        XCTAssertNil(tracks[4].language)
    }

    func testRejectsUnrelatedBasenamesAndTrailers() throws {
        try touch("Movie.mkv")
        try touch("Movie.trailer.ass")
        try touch("Movie.zh-Hans.extra-copy.ass")
        try touch("Trailer.zh-Hans.ass")
        let tracks = SubtitleCatalog.discover(for: directory.appendingPathComponent("Movie.mkv"))
        XCTAssertTrue(tracks.isEmpty)
    }

    func testSubsDirectoryIsScanned() throws {
        try touch("Movie.mkv")
        let subs = directory.appendingPathComponent("Subs", isDirectory: true)
        try FileManager.default.createDirectory(at: subs, withIntermediateDirectories: true)
        try Data().write(to: subs.appendingPathComponent("Movie.zh-Hans.ass"))
        try Data().write(to: subs.appendingPathComponent("Movie.zh-Hant.ass"))
        let tracks = SubtitleCatalog.discover(for: directory.appendingPathComponent("Movie.mkv"))
        XCTAssertEqual(tracks.map { $0.language ?? "" }, ["zh-Hans", "zh-Hant"])
    }

    func testLanguageTagNormalisation() {
        XCTAssertEqual(LanguageTag.parse("zh_TW"), "zh-Hant")
        XCTAssertEqual(LanguageTag.parse("CHS"), "zh-Hans")
        XCTAssertEqual(LanguageTag.parse("jpn"), "ja")
        XCTAssertEqual(LanguageTag.parse("eng"), "en")
        XCTAssertEqual(LanguageTag.parse("pt-br"), "pt-BR")
        XCTAssertNil(LanguageTag.parse("extended"))
    }
}
