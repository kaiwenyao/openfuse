import XCTest
@testable import OpenFuseCore
@testable import OpenFuseData

final class MediaSignatureTests: XCTestCase {
    func testRejectsTextAsMkv() {
        let data = Data("not a video".utf8)
        XCTAssertFalse(MediaSignature.looksLikeVideo(name: "Broken.Movie.mkv", header: data))
    }

    func testAcceptsKnownContainers() {
        XCTAssertTrue(MediaSignature.looksLikeVideo(
            name: "a.mkv", header: Data([0x1A, 0x45, 0xDF, 0xA3, 0, 0])
        ))
        XCTAssertTrue(MediaSignature.looksLikeVideo(
            name: "a.mp4", header: Data([0, 0, 0, 0x20]) + Data("ftypisom".utf8)
        ))
        XCTAssertTrue(MediaSignature.looksLikeVideo(
            name: "a.ts", header: Data([0x47, 0, 0, 0])
        ))
    }
}
