import XCTest
@testable import OpenFuseCore
@testable import OpenFuseData

final class PlaylistOrderTests: XCTestCase {
    private func entry(_ name: String, dir: Bool = false) -> RemoteEntry {
        RemoteEntry(
            path: "Season 03/\(name)",
            name: name,
            url: URL(string: "https://example.com/\(name)")!,
            isDirectory: dir,
            size: 1,
            contentType: nil,
            modifiedAt: nil,
            etag: nil
        )
    }

    func testNextEntrySkipsSubtitleFilesAndSortsNaturally() {
        let siblings = [
            entry("Show - S03E13 - A.mkv"),
            entry("Show - S03E13 - A.zh-Hans.ass"),
            entry("Show - S03E14 - B.mkv"),
            entry("Show - S03E09 - Z.mkv"),
            entry("Season 03", dir: true),
        ]
        let next = PlaylistOrder.nextPlayableEntry(after: entry("Show - S03E13 - A.mkv"), among: siblings)
        XCTAssertEqual(next?.name, "Show - S03E14 - B.mkv")
    }

    func testNextEntryReturnsNilAtTheEnd() {
        let siblings = [entry("Show - S03E13 - A.mkv"), entry("Show - S03E14 - B.mkv")]
        XCTAssertNil(PlaylistOrder.nextPlayableEntry(after: entry("Show - S03E14 - B.mkv"), among: siblings))
        XCTAssertNil(PlaylistOrder.nextPlayableEntry(after: entry("missing.mkv"), among: siblings))
    }

    func testNextEpisodeUsesEpisodeNumber() {
        func episode(_ id: String, _ number: Int?) -> JellyfinItem {
            JellyfinItem(
                id: id,
                name: "E\(number ?? 0)",
                itemType: "Episode",
                collectionType: nil,
                parentID: "season",
                seriesID: "series",
                seriesName: "Show",
                seasonID: "season",
                indexNumber: number,
                parentIndexNumber: 3,
                productionYear: nil,
                overview: nil,
                runTimeTicks: nil,
                imageTags: nil,
                userData: nil,
                dateCreated: nil,
                mediaSources: nil
            )
        }
        let episodes = [episode("e12", 12), episode("e13", 13), episode("e14", 14)]
        XCTAssertEqual(PlaylistOrder.nextEpisode(after: episode("e13", 13), among: episodes)?.id, "e14")
        XCTAssertNil(PlaylistOrder.nextEpisode(after: episode("e14", 14), among: episodes))
    }
}
