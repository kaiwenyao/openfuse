import XCTest
@testable import OpenFuseCore

final class VideoTimingPolicyTests: XCTestCase {
    func testInteractiveAudioEngineUsesZeroOffset() {
        let offset = MPVVideoTimingPolicy.timingOffset(
            videoSync: "audio",
            headless: false,
            thumbnailOutput: nil,
            environment: [:]
        )
        XCTAssertEqual(offset, "0")
    }

    func testEnvironmentOverrideSelectsPreFixBehaviour() {
        let groupA = MPVVideoTimingPolicy.timingOffset(
            videoSync: "audio",
            headless: false,
            thumbnailOutput: nil,
            environment: ["OPENFUSE_VIDEO_TIMING_OFFSET": "0.05"]
        )
        XCTAssertEqual(groupA, "0.05")
    }

    func testEmptyOverrideKeepsMpvDefault() {
        let offset = MPVVideoTimingPolicy.timingOffset(
            videoSync: "audio",
            headless: false,
            thumbnailOutput: nil,
            environment: ["OPENFUSE_VIDEO_TIMING_OFFSET": ""]
        )
        XCTAssertNil(offset)
    }

    func testHeadlessAndThumbnailEnginesAreUntouched() {
        XCTAssertNil(MPVVideoTimingPolicy.timingOffset(
            videoSync: "audio", headless: true, thumbnailOutput: nil, environment: [:]
        ))
        XCTAssertNil(MPVVideoTimingPolicy.timingOffset(
            videoSync: "audio",
            headless: false,
            thumbnailOutput: URL(fileURLWithPath: "/tmp/thumbs"),
            environment: [:]
        ))
    }

    func testOtherVideoSyncModesAreUntouched() {
        for sync in ["display-resample", "display-tempo", "desync", "audio-display"] {
            XCTAssertNil(
                MPVVideoTimingPolicy.timingOffset(
                    videoSync: sync, headless: false, thumbnailOutput: nil, environment: [:]
                ),
                "unexpected timing offset for video-sync=\(sync)"
            )
        }
    }

    func testBlockForTargetTimeIsAnOptInDiagnostic() {
        XCTAssertFalse(MPVVideoTimingPolicy.disablesBlockForTargetTime(environment: [:]))
        XCTAssertFalse(MPVVideoTimingPolicy.disablesBlockForTargetTime(environment: ["OPENFUSE_BLOCK_FOR_TARGET_TIME": "1"]))
        XCTAssertTrue(MPVVideoTimingPolicy.disablesBlockForTargetTime(environment: ["OPENFUSE_BLOCK_FOR_TARGET_TIME": "0"]))
    }

    func testEffectiveVideoSyncDefaultsToAudio() {
        XCTAssertEqual(MPVVideoTimingPolicy.effectiveVideoSync(environment: [:]), "audio")
        XCTAssertEqual(
            MPVVideoTimingPolicy.effectiveVideoSync(environment: ["OPENFUSE_VIDEO_SYNC": "display-resample"]),
            "display-resample"
        )
    }
}
