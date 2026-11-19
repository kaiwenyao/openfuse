import XCTest
@testable import OpenFuseCore

final class PlaybackStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("openfuse-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testResumeRoundTripAcrossRelaunch() throws {
        let media = directory.appendingPathComponent("Movie.mkv")
        try Data(repeating: 1, count: 2048).write(to: media)
        let fingerprint = try MediaFingerprint(url: media)

        let store = try PlaybackStore(directory: directory)
        store.update(
            fingerprint: fingerprint,
            duration: 60,
            position: 30,
            displayTitle: "Movie",
            audioTrackID: "mpv-audio:2",
            subtitleTrackID: "ext:/tmp/Movie.zh-Hans.ass"
        )

        let reopened = try PlaybackStore(directory: directory)
        let record = try XCTUnwrap(reopened.record(forPath: fingerprint.resumeKey))
        XCTAssertEqual(record.position, 30, accuracy: 0.01)
        XCTAssertEqual(record.duration, 60, accuracy: 0.01)
        XCTAssertFalse(record.isFinished)
        XCTAssertEqual(record.preferredAudioTrackID, "mpv-audio:2")
        XCTAssertEqual(ResumePolicy.resumePosition(for: record), 30)
    }

    func testFinishedClearsResumeAndIncrementsPlayCount() throws {
        let media = directory.appendingPathComponent("Movie.mkv")
        try Data(repeating: 1, count: 10).write(to: media)
        let fingerprint = try MediaFingerprint(url: media)
        let store = try PlaybackStore(directory: directory)
        store.update(fingerprint: fingerprint, duration: 60, position: 58)
        let finished = try XCTUnwrap(store.record(forPath: fingerprint.resumeKey))
        XCTAssertTrue(finished.isFinished)
        XCTAssertEqual(finished.position, 0)
        XCTAssertEqual(finished.playCount, 1)
        XCTAssertNil(ResumePolicy.resumePosition(for: finished))
    }

    func testBelowMinimumAndNearEndAreNotResumed() throws {
        let media = directory.appendingPathComponent("Movie.mkv")
        try Data(repeating: 1, count: 10).write(to: media)
        let fingerprint = try MediaFingerprint(url: media)
        let store = try PlaybackStore(directory: directory)

        store.update(fingerprint: fingerprint, duration: 60, position: 3)
        XCTAssertNil(ResumePolicy.resumePosition(for: store.record(forPath: fingerprint.resumeKey)!))

        store.update(fingerprint: fingerprint, duration: 60, position: 55)
        let nearEnd = try XCTUnwrap(store.record(forPath: fingerprint.resumeKey))
        XCTAssertNil(ResumePolicy.resumePosition(for: nearEnd))
    }

    func testFileReplacementKeepsProgress() throws {
        let media = directory.appendingPathComponent("Movie.mkv")
        try Data(repeating: 1, count: 10).write(to: media)
        let first = try MediaFingerprint(url: media)
        let store = try PlaybackStore(directory: directory)
        store.update(fingerprint: first, duration: 100, position: 42)

        try Data(repeating: 2, count: 4096).write(to: media)
        let second = try MediaFingerprint(url: media)
        XCTAssertNotEqual(first.fileSize, second.fileSize)
        XCTAssertEqual(first.resumeKey, second.resumeKey)
        XCTAssertEqual(store.record(forPath: second.resumeKey)?.position ?? 0, 42, accuracy: 0.01)
    }
}
