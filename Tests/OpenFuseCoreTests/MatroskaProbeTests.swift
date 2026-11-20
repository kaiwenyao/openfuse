import XCTest
@testable import OpenFuseCore
@testable import OpenFuseData

final class MatroskaProbeTests: XCTestCase {
    private func header(_ path: String) throws -> Data {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        return try handle.read(upToCount: 2_000_000) ?? Data()
    }

    func testParsesMainFixtureDimensions() throws {
        let data = try header("Fixtures/generated/openfuse-fixture.mkv")
        let info = try XCTUnwrap(MatroskaProbe.parse(data))
        XCTAssertEqual(info.width, 1920)
        XCTAssertEqual(info.height, 1080)
        XCTAssertEqual(info.resolution, "1080p")
    }

    func testParsesHDR10Colour() throws {
        let data = try header("Fixtures/generated/openfuse-hdr.mkv")
        let info = try XCTUnwrap(MatroskaProbe.parse(data))
        XCTAssertEqual(info.height, 1080)
        XCTAssertEqual(info.transferCharacteristics, 16)
        XCTAssertEqual(info.colourPrimaries, 9)
        XCTAssertEqual(info.dynamicRange, "HDR10")
    }
}
