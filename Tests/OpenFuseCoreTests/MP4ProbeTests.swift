import XCTest
@testable import OpenFuseCore
@testable import OpenFuseData

final class MP4ProbeTests: XCTestCase {
    func testTailMoovHDRFixture() throws {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: "Fixtures/generated/openfuse-hdr.mp4"))
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        let offset = size > 8_000_000 ? size - 8_000_000 : 0
        try handle.seek(toOffset: offset)
        let data = try handle.readToEnd() ?? Data()
        let info = try XCTUnwrap(MP4Probe.parse(data))
        XCTAssertEqual(info.width, 1920)
        XCTAssertEqual(info.height, 1080)
        XCTAssertEqual(info.transferCharacteristics, 16)
        XCTAssertEqual(info.colourPrimaries, 9)
        XCTAssertEqual(info.dynamicRange, "HDR10")
    }

    func testMobileFixtureDimensions() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: "Fixtures/mobile/openfuse-mobile.mp4"))
        let info = try XCTUnwrap(MP4Probe.parse(data))
        XCTAssertEqual(info.width, 1920)
        XCTAssertEqual(info.height, 1080)
        XCTAssertEqual(info.resolution, "1080p")
    }
}
