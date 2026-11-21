import XCTest
@testable import OpenFuseData

final class ContinueWatchingTests: XCTestCase {
    private func record(
        _ path: String,
        series: String? = nil,
        position: Double = 100,
        duration: Double = 1000,
        finished: Bool = false,
        played: TimeInterval
    ) -> PlaybackRecord {
        PlaybackRecord(
            mediaPath: path,
            duration: duration,
            position: position,
            lastPlayedAt: Date(timeIntervalSince1970: played),
            isFinished: finished,
            displayTitle: path,
            sourceKind: "webdav",
            sourceID: "src",
            seriesKey: series
        )
    }

    func testOnlyFourNewestUnfinishedOnePerSeries() {
        var records: [PlaybackRecord] = []
        for episode in 1...3 {
            records.append(record("/Shows/A/S01E0\(episode).mkv", series: "A", played: Double(100 + episode)))
        }
        for episode in 1...2 {
            records.append(record("/Shows/B/S01E0\(episode).mkv", series: "B", played: Double(200 + episode)))
        }
        records.append(record("/Shows/C/S01E01.mkv", series: "C", played: 50))
        records.append(record("/Shows/D/S01E01.mkv", series: "D", played: 10))
        records.append(record("/Movies/X.mkv", played: 400))
        records.append(record("/Shows/A/S01E99.mkv", series: "A", position: 100, finished: true, played: 999))
        records.append(record("/Shows/Z/S01E01.mkv", series: "Z", position: 0, played: 1000))
        let visible = ContinueWatching.visible(records)
        XCTAssertEqual(visible.count, 4)
        XCTAssertEqual(visible.map(\.mediaPath), [
            "/Movies/X.mkv",
            "/Shows/B/S01E02.mkv",
            "/Shows/A/S01E03.mkv",
            "/Shows/C/S01E01.mkv",
        ])
        XCTAssertFalse(visible.contains { $0.isFinished })
    }

    func testZeroProgressAndDuplicatesExcluded() {
        let records = [
            record("/a.mkv", position: 0, played: 3),
            record("/b.mkv", position: 10, played: 2),
            record("/b.mkv", position: 10, played: 2),
        ]
        XCTAssertEqual(ContinueWatching.visible(records).map(\.mediaPath), ["/b.mkv"])
    }

    func testLegacySeriesKeyDerivation() {
        let legacy = PlaybackRecord(
            mediaPath: "webdav://src/Shows/Attack/Season 01/S01E02.mkv",
            duration: 1000,
            position: 100,
            sourceKind: "webdav",
            sourceID: "src",
            remotePath: "Shows/Attack/Season 01/S01E02.mkv"
        )
        XCTAssertEqual(ContinueWatching.groupKey(legacy), "src|Shows/Attack")
    }

    func testHistoryKeepsEverythingNewestFirst() {
        let records = [
            record("/a.mkv", finished: true, played: 1),
            record("/b.mkv", played: 3),
            record("/c.mkv", finished: true, played: 2),
        ]
        XCTAssertEqual(ContinueWatching.history(records).map(\.mediaPath), ["/b.mkv", "/c.mkv", "/a.mkv"])
    }
}
