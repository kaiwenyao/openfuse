import XCTest
@testable import OpenFuseData

final class MetadataLanguageTests: XCTestCase {
    func testSimplifiedAndTraditionalAreDistinct() {
        let hans = MetadataLanguage.resolve("zh-Hans")
        let hant = MetadataLanguage.resolve("zh-Hant")
        XCTAssertEqual(hans.identifier, "zh-Hans")
        XCTAssertEqual(hant.identifier, "zh-Hant")
        XCTAssertEqual(hans.tmdb, "zh-CN")
        XCTAssertEqual(hant.tmdb, "zh-TW")
        XCTAssertEqual(hant.convert("进击的巨人"), "進擊的巨人")
        XCTAssertEqual(hant.convertToHans("進擊的巨人"), "进击的巨人")
    }

    func testRegionalChineseVariants() {
        XCTAssertEqual(MetadataLanguage.resolve("zh-TW").identifier, "zh-Hant")
        XCTAssertEqual(MetadataLanguage.resolve("zh-HK").identifier, "zh-Hant")
        XCTAssertEqual(MetadataLanguage.resolve("zh-SG").identifier, "zh-Hans")
        XCTAssertEqual(MetadataLanguage.resolve("zh-CN").identifier, "zh-Hans")
    }

    func testNonEnglishLanguage() {
        let ja = MetadataLanguage.resolve("ja-JP")
        XCTAssertEqual(ja.identifier, "ja")
        XCTAssertEqual(ja.wikipedia.first, "ja")
        XCTAssertEqual(ja.tmdb, "ja-JP")
    }

    func testFieldFallbackKeepsLocalizedTitle() {
        let hans = MetadataLanguage.resolve("zh-Hans")
        XCTAssertEqual(hans.localized("进击的巨人", english: "Attack on Titan"), "进击的巨人")
        XCTAssertNil(hans.localized(nil, english: nil))
    }
}
