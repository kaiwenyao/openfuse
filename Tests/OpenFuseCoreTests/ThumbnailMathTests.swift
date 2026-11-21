import XCTest
@testable import OpenFuseCore

final class ThumbnailMathTests: XCTestCase {
    func testHoverTimeClamps() {
        XCTAssertEqual(ThumbnailMath.hoverTime(x: 0, width: 100, duration: 60), 0)
        XCTAssertEqual(ThumbnailMath.hoverTime(x: 50, width: 100, duration: 60), 30)
        XCTAssertEqual(ThumbnailMath.hoverTime(x: 140, width: 100, duration: 60), 60)
        XCTAssertEqual(ThumbnailMath.hoverTime(x: -10, width: 100, duration: 60), 0)
        XCTAssertEqual(ThumbnailMath.hoverTime(x: 50, width: 100, duration: 0), 0)
    }

    func testBuckets() {
        XCTAssertEqual(ThumbnailMath.bucket(for: 0), 0)
        XCTAssertEqual(ThumbnailMath.bucket(for: 1.99), 0)
        XCTAssertEqual(ThumbnailMath.bucket(for: 2), 1)
        XCTAssertEqual(ThumbnailMath.bucket(for: 59.9), 29)
        XCTAssertEqual(ThumbnailMath.bucketTime(3), 6)
    }

    func testPreviewOriginClamping() {
        XCTAssertEqual(ThumbnailMath.previewOrigin(hoverX: 10, width: 400, previewWidth: 168), 0)
        XCTAssertEqual(ThumbnailMath.previewOrigin(hoverX: 200, width: 400, previewWidth: 168), 116)
        XCTAssertEqual(ThumbnailMath.previewOrigin(hoverX: 390, width: 400, previewWidth: 168), 232)
        XCTAssertEqual(ThumbnailMath.previewOrigin(hoverX: 100, width: 100, previewWidth: 168), 0)
    }
}
