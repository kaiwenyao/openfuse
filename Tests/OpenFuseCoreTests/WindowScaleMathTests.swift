import XCTest
@testable import OpenFuseCore

final class WindowScaleMathTests: XCTestCase {
    private let video = CGSize(width: 640, height: 360)
    private let maxContent = CGSize(width: 1452, height: 817)
    private let current = CGSize(width: 1180, height: 760)

    func testHalfNormalDouble() {
        XCTAssertEqual(
            WindowScaleMath.targetSize(action: .half, videoSize: video, current: current, maxContent: maxContent),
            CGSize(width: 320, height: 180)
        )
        XCTAssertEqual(
            WindowScaleMath.targetSize(action: .normal, videoSize: video, current: current, maxContent: maxContent),
            CGSize(width: 640, height: 360)
        )
        XCTAssertEqual(
            WindowScaleMath.targetSize(action: .doubleSize, videoSize: video, current: current, maxContent: maxContent),
            CGSize(width: 1280, height: 720)
        )
    }

    func testFitKeepsAspectAndFillsWidth() {
        let size = WindowScaleMath.targetSize(
            action: .fit, videoSize: video, current: current, maxContent: maxContent
        )
        XCTAssertEqual(size.width, 1452, accuracy: 0.5)
        XCTAssertEqual(size.height, 817, accuracy: 0.5)
    }

    func testSmallerBiggerUseCurrentSize() {
        let smaller = WindowScaleMath.targetSize(
            action: .smaller, videoSize: video, current: current, maxContent: maxContent
        )
        XCTAssertEqual(smaller.width, 1062, accuracy: 0.5)
        XCTAssertEqual(smaller.height, 684, accuracy: 0.5)
        let bigger = WindowScaleMath.targetSize(
            action: .bigger, videoSize: video, current: current, maxContent: maxContent
        )
        XCTAssertEqual(bigger.width, 1268.5, accuracy: 0.5)
        XCTAssertEqual(bigger.height, 817, accuracy: 0.5)
    }

    func testClampsOversizedVideoAndMinimum() {
        let big = CGSize(width: 3840, height: 2160)
        let size = WindowScaleMath.targetSize(
            action: .doubleSize, videoSize: big, current: current, maxContent: maxContent
        )
        XCTAssertEqual(size.width, 1452, accuracy: 0.5)
        XCTAssertEqual(size.height, 816.75, accuracy: 0.1)
        let tiny = WindowScaleMath.targetSize(
            action: .half, videoSize: CGSize(width: 160, height: 90), current: current, maxContent: maxContent
        )
        XCTAssertEqual(tiny, CGSize(width: 320, height: 180))
    }
}
