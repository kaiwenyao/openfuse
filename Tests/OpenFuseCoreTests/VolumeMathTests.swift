import XCTest
@testable import OpenFuseCore

final class VolumeMathTests: XCTestCase {
    func testClamp() {
        XCTAssertEqual(VolumeMath.clamp(-12), 0)
        XCTAssertEqual(VolumeMath.clamp(0), 0)
        XCTAssertEqual(VolumeMath.clamp(55.5), 55.5)
        XCTAssertEqual(VolumeMath.clamp(100), 100)
        XCTAssertEqual(VolumeMath.clamp(140), 100)
        XCTAssertEqual(VolumeMath.clamp(.nan), 0)
        XCTAssertEqual(VolumeMath.clamp(.infinity), 100)
    }

    func testArrowKeySteps() {
        XCTAssertEqual(VolumeMath.stepped(100, by: -5), 95)
        XCTAssertEqual(VolumeMath.stepped(98, by: 5), 100)
        XCTAssertEqual(VolumeMath.stepped(2, by: -5), 0)
        XCTAssertEqual(VolumeMath.stepped(50, by: 5), 55)
    }

    func testUnmuteRestoresLastAudibleLevel() {
        XCTAssertEqual(VolumeMath.unmuted(stored: 35), 35)
        XCTAssertEqual(VolumeMath.unmuted(stored: 0, fallback: 60), 60)
        XCTAssertEqual(VolumeMath.unmuted(stored: 250), 100)
    }
}
