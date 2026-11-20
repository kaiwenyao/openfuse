import XCTest
@testable import OpenFuseCore

final class RemotePathTests: XCTestCase {
    func testStackSplitsPathIntoComponents() {
        XCTAssertEqual(RemotePath.stack("Show/Season 1"), ["", "Show", "Season 1"])
        XCTAssertEqual(RemotePath.stack("/Show/Season 1/"), ["", "Show", "Season 1"])
        XCTAssertEqual(RemotePath.stack(""), [""])
        XCTAssertEqual(RemotePath.stack("///"), [""])
    }

    func testPathJoinsComponents() {
        XCTAssertEqual(RemotePath.path(["", "Show", "Season 1"]), "Show/Season 1")
        XCTAssertEqual(RemotePath.path([""]), "")
    }

    func testEnterIsIdempotent() {
        var state = RemotePathState()
        XCTAssertTrue(state.enter("Movies"))
        XCTAssertEqual(state.stack, ["", "Movies"])
        // The same folder clicked again while loading must not stack the path.
        XCTAssertFalse(state.enter("Movies"))
        XCTAssertEqual(state.stack, ["", "Movies"])
    }

    func testEnterWhileBusyIsIgnored() {
        var state = RemotePathState(stack: ["", "Movies"])
        XCTAssertFalse(state.enter("Movies/Show", busy: true))
        XCTAssertEqual(state.stack, ["", "Movies"])
        XCTAssertEqual(state.path, "Movies")
    }

    func testEnterDeepPathReplacesTail() {
        var state = RemotePathState(stack: ["", "Movies"])
        XCTAssertTrue(state.enter("Movies/Show/Season 1"))
        XCTAssertEqual(state.stack, ["", "Movies", "Show", "Season 1"])
        XCTAssertEqual(state.path, "Movies/Show/Season 1")
    }

    func testUpStopsAtRoot() {
        var state = RemotePathState(stack: ["", "Movies", "Show"])
        XCTAssertTrue(state.up())
        XCTAssertEqual(state.stack, ["", "Movies"])
        XCTAssertTrue(state.up())
        XCTAssertEqual(state.stack, [""])
        XCTAssertFalse(state.up())
        XCTAssertTrue(state.isRoot)
    }

    func testJumpToBreadcrumbSegment() {
        var state = RemotePathState(stack: ["", "Movies", "Show", "Season 1"])
        XCTAssertTrue(state.jump(to: 1))
        XCTAssertEqual(state.stack, ["", "Movies"])
        XCTAssertFalse(state.jump(to: 1))
    }

    func testLegacyRootRelativeStackIsMigrated() {
        // Old builds appended `entry.path` (root-relative) to the stack.
        var state = RemotePathState(stack: ["", "Movies", "Movies/Show", "Movies/Show"])
        XCTAssertEqual(state.stack, ["", "Movies", "Show"])
        XCTAssertEqual(state.path, "Movies/Show")
        // And a subsequent click cannot duplicate it again.
        XCTAssertFalse(state.enter("Movies/Show"))
    }

    func testDirectoryNamedLikeParentIsNotCollapsed() {
        // "A" inside "A" is a legal layout and must survive normalisation.
        let state = RemotePathState(stack: ["", "A", "A"])
        XCTAssertEqual(state.stack, ["", "A", "A"])
    }

    func testPercentEncodedAndSpacesArePreserved() {
        var state = RemotePathState()
        XCTAssertTrue(state.enter("电影/Show 100%25"))
        XCTAssertEqual(state.stack, ["", "电影", "Show 100%25"])
        XCTAssertEqual(RemotePath.displayName(state.stack[2]), "Show 100%25")
    }
}
