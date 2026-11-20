import XCTest
@testable import OpenFuseCore
@testable import OpenFuseData

final class MP4ProbeTests: XCTestCase {
    func testMobileFixtureDimensions() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: "Fixtures/mobile/openfuse-mobile.mp4"))
        let info = try XCTUnwrap(MP4Probe.parse(data))
        XCTAssertEqual(info.width, 1920)
        XCTAssertEqual(info.height, 1080)
        XCTAssertEqual(info.resolution, "1080p")
    }
}
