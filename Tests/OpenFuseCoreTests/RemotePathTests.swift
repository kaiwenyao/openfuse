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

    func testFolderDisplayNameUsesASingleSegmentServerName() {
        XCTAssertEqual(
            RemotePath.folderDisplayName(name: "Fargo (2014)", path: "local/kaiwenyao/baidu/电视剧/Fargo (2014)"),
            "Fargo (2014)"
        )
        XCTAssertEqual(
            RemotePath.folderDisplayName(name: "Season 01", path: "Shows/Fargo (2014)/Season 01"),
            "Season 01"
        )
        XCTAssertEqual(
            RemotePath.folderDisplayName(name: "纪录片 100% 真实", path: "电影/纪录片 100% 真实"),
            "纪录片 100% 真实"
        )
        XCTAssertEqual(RemotePath.folderDisplayName(name: "电影", path: "电影"), "电影")
    }

    func testFolderDisplayNameFallsBackToTheLastPathSegment() {
        // OpenList sometimes repeats the whole root-relative path in
        // <displayname>. The parent belongs in the breadcrumb, not the card.
        XCTAssertEqual(
            RemotePath.folderDisplayName(
                name: "local/kaiwenyao/baidu/电视剧/Fargo (2014)",
                path: "local/kaiwenyao/baidu/电视剧/Fargo (2014)"
            ),
            "Fargo (2014)"
        )
        // Missing, whitespace-only and trailing-slash names are not usable.
        XCTAssertEqual(RemotePath.folderDisplayName(name: "", path: "电视剧/Season 01/"), "Season 01")
        XCTAssertEqual(RemotePath.folderDisplayName(name: "   ", path: "电视剧/Season 01/"), "Season 01")
        XCTAssertEqual(RemotePath.folderDisplayName(name: "Season 01/", path: "Shows/Season 01"), "Season 01")
        XCTAssertEqual(RemotePath.folderDisplayName(name: "/", path: "Shows/Season 01"), "Season 01")
        XCTAssertEqual(RemotePath.folderDisplayName(name: "..", path: "Shows/Season 01"), "Season 01")
        // A percent-encoded path is not a single display name; the already
        // decoded entry.path is authoritative.
        XCTAssertEqual(
            RemotePath.folderDisplayName(name: "Shows%2FSeason%2001", path: "Shows/Season 01"),
            "Season 01"
        )
        // A path with no components keeps the best available text.
        XCTAssertEqual(RemotePath.folderDisplayName(name: "Show/Season 01", path: ""), "Show/Season 01")
    }

    func testFolderDisplayNameCollapsesSameNamedFoldersFromDifferentParents() {
        // Two "Season 01" folders under different shows must both label
        // themselves "Season 01"; the parent is only in the breadcrumb and the
        // paths stay distinct for navigation and caching.
        let fargo = RemotePath.folderDisplayName(
            name: "Fargo (2014)/Season 01",
            path: "电视剧/Fargo (2014)/Season 01"
        )
        let attack = RemotePath.folderDisplayName(
            name: "Attack on Titan (2013)/Season 01",
            path: "电视剧/Attack on Titan (2013)/Season 01"
        )
        XCTAssertEqual(fargo, "Season 01")
        XCTAssertEqual(attack, "Season 01")
        XCTAssertNotEqual("电视剧/Fargo (2014)/Season 01", "电视剧/Attack on Titan (2013)/Season 01")
    }

    func testFolderDisplayNameKeepsExistingPercentDecodingBoundary() {
        // `entry.path` is already decoded once by WebDAVClient.decodePath. A
        // literal percent in the segment must not be decoded a second time.
        XCTAssertEqual(
            RemotePath.folderDisplayName(name: "100% 测试", path: "Shows/100% 测试"),
            "100% 测试"
        )
        // A percent-encoded server name is used verbatim, as before.
        XCTAssertEqual(
            RemotePath.folderDisplayName(name: "100%25 Test", path: "Shows/100% Test"),
            "100%25 Test"
        )
        // When the name is unusable the already-decoded path segment wins.
        XCTAssertEqual(
            RemotePath.folderDisplayName(name: "Shows/100%25 Test", path: "Shows/100% Test"),
            "100% Test"
        )
    }

    func testRemoteEntryFolderDisplayNameDoesNotChangeItsIdentity() {
        let entry = RemoteEntry(
            path: "local/kaiwenyao/baidu/电视剧/Fargo (2014)",
            name: "local/kaiwenyao/baidu/电视剧/Fargo (2014)",
            url: URL(string: "http://host/dav/local/kaiwenyao/baidu/%E7%94%B5%E8%A7%86%E5%89%A7/Fargo%20(2014)/")!,
            isDirectory: true
        )
        XCTAssertEqual(entry.folderDisplayName, "Fargo (2014)")
        XCTAssertEqual(entry.path, "local/kaiwenyao/baidu/电视剧/Fargo (2014)")
        XCTAssertEqual(entry.id, entry.path)
        XCTAssertEqual(
            entry.url.absoluteString,
            "http://host/dav/local/kaiwenyao/baidu/%E7%94%B5%E8%A7%86%E5%89%A7/Fargo%20(2014)/"
        )
    }

    func testRemoteEntryBaseNameFallsBackToThePathForFiles() {
        let full = RemoteEntry(
            path: "电视剧/Fargo (2014)/Season 01/Fargo (2014) - S01E01 - Pilot.mkv",
            name: "电视剧/Fargo (2014)/Season 01/Fargo (2014) - S01E01 - Pilot.mkv",
            url: URL(string: "http://host/dav/f.mkv")!,
            isDirectory: false
        )
        XCTAssertEqual(full.baseName, "Fargo (2014) - S01E01 - Pilot.mkv")
        XCTAssertEqual(full.fileBaseName, "Fargo (2014) - S01E01 - Pilot")

        let normal = RemoteEntry(
            path: "Shows/Season 01/episode.mkv",
            name: "Episode One.mkv",
            url: URL(string: "http://host/dav/e.mkv")!,
            isDirectory: false
        )
        XCTAssertEqual(normal.baseName, "Episode One.mkv")
        XCTAssertEqual(normal.fileBaseName, "Episode One")
    }
}
