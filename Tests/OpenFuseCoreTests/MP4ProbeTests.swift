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

    func testScansMoovAfterArbitraryTailPrefix() throws {
        let full = try Data(contentsOf: URL(fileURLWithPath: "Fixtures/generated/openfuse-hdr.mp4"))
        let bytes = [UInt8](full)
        let marker: [UInt8] = [0x6D, 0x6F, 0x6F, 0x76]
        let index = try XCTUnwrap(bytes.indices.first { i in
            i + 4 <= bytes.count && Array(bytes[i..<(i + 4)]) == marker
        })
        var tail = Data(count: 1_000_000)
        tail.append(contentsOf: bytes[(index - 4)...])
        let info = try XCTUnwrap(MP4Probe.parse(tail))
        XCTAssertEqual(info.height, 1080)
        XCTAssertEqual(info.transferCharacteristics, 16)
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
