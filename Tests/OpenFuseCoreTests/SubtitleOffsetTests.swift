import Foundation
import XCTest
@testable import OpenFuseData

final class SubtitleOffsetTests: XCTestCase {
    private func assertParsed(
        _ text: String,
        _ expected: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            SubtitleOffsetText.parse(text) ?? .nan,
            expected,
            accuracy: 1e-9,
            file: file,
            line: line
        )
    }

    private func assertRejected(
        _ text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNil(SubtitleOffsetText.parse(text), file: file, line: line)
    }

    // MARK: - Display precision

    func testSummaryDirectionAndValue() {
        XCTAssertEqual(SubtitleOffsetText.summary(0), "同步（0 秒）")
        XCTAssertEqual(SubtitleOffsetText.summary(1.5), "延后 1.5 秒")
        XCTAssertEqual(SubtitleOffsetText.summary(1.0), "延后 1 秒")
        XCTAssertEqual(SubtitleOffsetText.summary(-1.0), "提前 1 秒")
        XCTAssertEqual(SubtitleOffsetText.summary(0.05), "延后 0.05 秒")
        XCTAssertEqual(SubtitleOffsetText.summary(-1.55), "提前 1.55 秒")
        XCTAssertEqual(SubtitleOffsetText.summary(0.04), "延后 0.04 秒")
        XCTAssertEqual(SubtitleOffsetText.summary(-0.04), "提前 0.04 秒")
        XCTAssertEqual(SubtitleOffsetText.summary(0.15), "延后 0.15 秒")
        XCTAssertEqual(SubtitleOffsetText.summary(-0.15), "提前 0.15 秒")
    }

    func testSummaryUsesMillisecondPrecisionAndOnlyZeroIsSynced() {
        XCTAssertEqual(SubtitleOffsetText.summary(0.001), "延后 0.001 秒")
        XCTAssertEqual(SubtitleOffsetText.summary(-0.001), "提前 0.001 秒")
        XCTAssertEqual(SubtitleOffsetText.summary(0.0004), "同步（0 秒）")
        XCTAssertEqual(SubtitleOffsetText.summary(-0.0004), "同步（0 秒）")
        XCTAssertEqual(SubtitleOffsetText.summary(-0.0), "同步（0 秒）")
        XCTAssertEqual(SubtitleOffsetText.summary(600.4), "延后 600 秒")
        XCTAssertEqual(SubtitleOffsetText.summary(-600.4), "提前 600 秒")
    }

    func testEditFieldTextHasNoPaddedZeros() {
        XCTAssertEqual(SubtitleOffsetText.valueText(0), "0")
        XCTAssertEqual(SubtitleOffsetText.valueText(-0.0), "0")
        XCTAssertEqual(SubtitleOffsetText.valueText(0.04), "0.04")
        XCTAssertEqual(SubtitleOffsetText.valueText(0.15), "0.15")
        XCTAssertEqual(SubtitleOffsetText.valueText(-0.1), "-0.1")
        XCTAssertEqual(SubtitleOffsetText.valueText(2.0), "2")
        XCTAssertEqual(SubtitleOffsetText.valueText(2.50), "2.5")
        XCTAssertEqual(SubtitleOffsetText.valueText(0.0004), "0")
        XCTAssertEqual(SubtitleOffsetText.valueText(0.0006), "0.001")
        XCTAssertEqual(SubtitleOffsetText.valueText(-0.0006), "-0.001")
        XCTAssertEqual(SubtitleOffsetText.valueText(0.0016), "0.002")
    }

    /// Opening the sheet prefills `valueText`, and applying it unchanged must
    /// preserve the effective offset the menu and mpv use.
    func testEditFieldRoundTripKeepsEffectiveOffset() {
        let values: [Double] = [0, 0.04, -0.04, 0.15, -0.1, 2, -2.5, 600, -600, 0.001, 123.456]
        for value in values {
            let text = SubtitleOffsetText.valueText(value)
            XCTAssertEqual(
                SubtitleOffsetText.parse(text) ?? .nan,
                SubtitleOffsetText.normalized(value),
                accuracy: 1e-9,
                "round trip failed for \(value) via \(text)"
            )
        }
        // The regression from the report: 0.04 must not come back as 0.0.
        XCTAssertEqual(SubtitleOffsetText.parse(SubtitleOffsetText.valueText(0.04)) ?? .nan, 0.04, accuracy: 1e-9)
        XCTAssertEqual(SubtitleOffsetText.parse(SubtitleOffsetText.valueText(0.15)) ?? .nan, 0.15, accuracy: 1e-9)
    }

    // MARK: - Parsing

    func testParsing() {
        assertParsed("1.5", 1.5)
        assertParsed("+1.5", 1.5)
        assertParsed("-1", -1)
        assertParsed("1,5", 1.5)
        assertParsed("延后 2 秒", 2)
        assertParsed("  -0.1  ", -0.1)
        assertParsed("0", 0)
        assertParsed(".1", 0.1)
        assertParsed("-.1", -0.1)
        assertRejected("abc")
        assertParsed("9999", 600)
    }

    func testParsingMathAndFullWidthSigns() {
        // U+2212 math minus used to be dropped, turning -0.1 into +0.1.
        assertParsed("−0.1", -0.1) // U+2212
        assertParsed("－0.1", -0.1) // U+FF0D full width hyphen minus
        assertParsed("﹣0.1", -0.1) // U+FE63 small hyphen minus
        assertParsed("＋0.1", 0.1) // U+FF0B full width plus
        assertParsed("−1", -1)
        assertParsed("－1,5", -1.5)
        assertParsed("０.０４", 0.04) // full width digits
        assertParsed("−9999", -600)
    }

    func testParsingDirectionWords() {
        assertParsed("提前 0.1 秒", -0.1)
        assertParsed("提前 0.1", -0.1)
        assertParsed("提前：0.1 秒", -0.1)
        assertParsed("提前 −0.1", -0.1)
        assertParsed("提前-0.1", -0.1)
        assertParsed("延后 0.1 秒", 0.1)
        assertParsed("延后 +2", 2)
        // A contradictory direction and sign is rejected, never silently
        // flipped to a positive offset.
        assertRejected("提前 +0.1")
        assertRejected("延后 -0.1")
        assertRejected("提前")
        assertRejected("延后 abc")
    }

    func testParsingRejectsPartialMatches() {
        assertRejected("")
        assertRejected("   ")
        assertRejected("abc 5")
        assertRejected("5abc")
        assertRejected("x-0.1")
        assertRejected("1.2.3")
        assertRejected("1,2,3")
        assertRejected("1 2")
        assertRejected("0.1 0.2")
        assertRejected("5 秒 6")
        assertRejected("-")
        assertRejected("+")
        assertRejected(".")
        assertRejected("--1")
        assertRejected("提前：")
    }

    func testParsingClampsToSixHundredSeconds() {
        assertParsed("600", 600)
        assertParsed("-600", -600)
        assertParsed("600.4", 600)
        assertParsed("-600.4", -600)
        assertParsed("9999", 600)
        assertParsed("-9999", -600)
        assertParsed("−9999", -600)
    }

    // MARK: - Storage

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

    /// Records written by 0.9.1/0.9.3 must keep decoding, and reopening a film
    /// or switching back to its track must recover the same fine-grained value.
    func testStoreRestoresLegacyFineGrainedRecords() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("offset-legacy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let legacy = #"{"version":1,"offsets":{"media-a|zh-Hans":0.04,"media-a|zh-Hant":0.15,"media-b|zh-Hans":-0.04}}"#
        try legacy.write(
            to: dir.appendingPathComponent("subtitle-offsets.json"),
            atomically: true,
            encoding: .utf8
        )

        let store = try SubtitleOffsetStore(directory: dir)
        XCTAssertEqual(store.offset(media: "media-a", track: "zh-Hans"), 0.04, accuracy: 1e-9)
        XCTAssertEqual(store.offset(media: "media-a", track: "zh-Hant"), 0.15, accuracy: 1e-9)
        XCTAssertEqual(store.offset(media: "media-b", track: "zh-Hans"), -0.04, accuracy: 1e-9)

        // Resetting one track clears only that track.
        store.setOffset(0, media: "media-a", track: "zh-Hans")
        XCTAssertEqual(store.offset(media: "media-a", track: "zh-Hans"), 0)
        XCTAssertEqual(store.offset(media: "media-a", track: "zh-Hant"), 0.15, accuracy: 1e-9)

        let reopened = try SubtitleOffsetStore(directory: dir)
        XCTAssertEqual(reopened.offset(media: "media-a", track: "zh-Hans"), 0)
        XCTAssertEqual(reopened.offset(media: "media-a", track: "zh-Hant"), 0.15, accuracy: 1e-9)
        XCTAssertEqual(reopened.offset(media: "media-b", track: "zh-Hans"), -0.04, accuracy: 1e-9)
    }

    func testStoreUsesTheSameMillisecondGridAndDropsNearZero() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("offset-grid-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SubtitleOffsetStore(directory: dir)

        store.setOffset(0.0004, media: "m", track: "t")
        XCTAssertEqual(store.offset(media: "m", track: "t"), 0)
        XCTAssertTrue(store.allOffsets.isEmpty)

        store.setOffset(-0.0, media: "m", track: "t")
        XCTAssertEqual(store.offset(media: "m", track: "t"), 0)

        store.setOffset(0.0006, media: "m", track: "t")
        XCTAssertEqual(store.offset(media: "m", track: "t"), 0.001, accuracy: 1e-9)

        store.setOffset(0.04000000000000001, media: "m", track: "t")
        XCTAssertEqual(store.offset(media: "m", track: "t"), 0.04, accuracy: 1e-9)

        let reopened = try SubtitleOffsetStore(directory: dir)
        XCTAssertEqual(reopened.offset(media: "m", track: "t"), 0.04, accuracy: 1e-9)
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
