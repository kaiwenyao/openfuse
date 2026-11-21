import XCTest
@testable import OpenFuseData

final class SubtitleOffsetTests: XCTestCase {
    func testSummaryDirectionAndValue() {
        XCTAssertEqual(SubtitleOffsetText.summary(0), "同步（0 秒）")
        XCTAssertEqual(SubtitleOffsetText.summary(1.5), "延后 1.5 秒")
        XCTAssertEqual(SubtitleOffsetText.summary(1.0), "延后 1 秒")
        XCTAssertEqual(SubtitleOffsetText.summary(-1.0), "提前 1 秒")
        XCTAssertEqual(SubtitleOffsetText.summary(0.05), "延后 0.1 秒")
        XCTAssertEqual(SubtitleOffsetText.summary(-1.55), "提前 1.6 秒")
    }

    func testParsing() {
        XCTAssertEqual(SubtitleOffsetText.parse("1.5"), 1.5)
        XCTAssertEqual(SubtitleOffsetText.parse("+1.5"), 1.5)
        XCTAssertEqual(SubtitleOffsetText.parse("-1"), -1)
        XCTAssertEqual(SubtitleOffsetText.parse("1,5"), 1.5)
        XCTAssertEqual(SubtitleOffsetText.parse("延后 2 秒"), 2)
        XCTAssertNil(SubtitleOffsetText.parse("abc"))
        XCTAssertEqual(SubtitleOffsetText.parse("9999"), 600)
    }

    func testStorePersistsPerMediaAndTrack() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("offset-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SubtitleOffsetStore(directory: dir)
        store.setOffset(1.5, media: "media-a", track: "zh-Hans")
        XCTAssertEqual(store.offset(media: "media-a", track: "zh-Hans"), 1.5)
        XCTAssertEqual(store.offset(media: "media-a", track: "zh-Hant"), 0)
        XCTAssertEqual(store.offset(media: "media-b", track: "zh-Hans"), 0)

        let reopened = try SubtitleOffsetStore(directory: dir)
        XCTAssertEqual(reopened.offset(media: "media-a", track: "zh-Hans"), 1.5)

        reopened.setOffset(0, media: "media-a", track: "zh-Hans")
        XCTAssertEqual(reopened.offset(media: "media-a", track: "zh-Hans"), 0)
        XCTAssertTrue(reopened.allOffsets.isEmpty)
    }
}

final class SubtitleCatalogQualityTests: XCTestCase {
    func testSidecarWithoutQualityStillMatches() {
        let match = SubtitleCatalog.matchSubtitleName(
            "Attack.on.Titan.S03E13.zh-Hans",
            videoBase: "Attack.on.Titan.S03E13.1080p"
        )
        XCTAssertEqual(match?.language, "zh-Hans")
        let hant = SubtitleCatalog.matchSubtitleName(
            "Attack.on.Titan.S03E13.zh-Hant",
            videoBase: "Attack.on.Titan.S03E13.1080p"
        )
        XCTAssertEqual(hant?.language, "zh-Hant")
        XCTAssertNil(SubtitleCatalog.matchSubtitleName("Other.Show.S03E13.zh-Hans", videoBase: "Attack.on.Titan.S03E13.1080p"))
    }
}
