import XCTest
@testable import OpenFuseCore
@testable import OpenFuseData

final class ProgressSyncTests: XCTestCase {
    func testLocalTransportMergesLatestProgressAcrossDevices() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("openfuse-sync-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let storeA = try PlaybackStore(directory: root.appendingPathComponent("A"))
        let storeB = try PlaybackStore(directory: root.appendingPathComponent("B"))
        let transportFile = root.appendingPathComponent("shared.json")
        let transport = LocalProgressTransport(fileURL: transportFile)
        let fingerprint = MediaFingerprint(path: "/media/OpenFuse.mkv", fileSize: 100, modifiedAt: nil)

        storeA.update(
            fingerprint: fingerprint, duration: 100, position: 30,
            displayTitle: "OpenFuse", sourceKind: "local"
        )
        _ = try await ProgressSyncService(store: storeA, transport: transport).sync()
        _ = try await ProgressSyncService(store: storeB, transport: transport).sync()
        XCTAssertEqual(storeB.record(forPath: fingerprint.resumeKey)?.position ?? 0, 30, accuracy: 0.001)
        XCTAssertEqual(
            storeB.record(forPath: fingerprint.resumeKey).flatMap(ResumePolicy.resumePosition(for:)) ?? 0,
            30, accuracy: 0.001
        )

        try await Task.sleep(nanoseconds: 50_000_000)
        storeB.update(
            fingerprint: fingerprint, duration: 100, position: 70,
            displayTitle: "OpenFuse", sourceKind: "local"
        )
        _ = try await ProgressSyncService(store: storeB, transport: transport).sync()
        _ = try await ProgressSyncService(store: storeA, transport: transport).sync()
        XCTAssertEqual(storeA.record(forPath: fingerprint.resumeKey)?.position ?? 0, 70, accuracy: 0.001)

        try await Task.sleep(nanoseconds: 50_000_000)
        storeB.update(
            fingerprint: fingerprint, duration: 100, position: 0,
            displayTitle: "OpenFuse", finished: true
        )
        _ = try await ProgressSyncService(store: storeB, transport: transport).sync()
        _ = try await ProgressSyncService(store: storeA, transport: transport).sync()
        let finished = try XCTUnwrap(storeA.record(forPath: fingerprint.resumeKey))
        XCTAssertTrue(finished.isFinished)
        XCTAssertNil(ResumePolicy.resumePosition(for: finished))
    }
}
