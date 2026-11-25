import XCTest
@testable import OpenFuseCore

final class RenderTimingTests: XCTestCase {
    private func enabledTiming(frameBudgetMs: Double = 16.7) -> RenderTiming {
        RenderTiming(environment: [
            "OPENFUSE_RENDER_TIMING": "1",
            "OPENFUSE_RENDER_TIMING_INTERVAL": "0",
            "OPENFUSE_FRAME_BUDGET_MS": String(frameBudgetMs),
        ])
    }

    func testDisabledByDefaultIsCheapAndRecordsNothing() {
        let timing = RenderTiming(environment: [:])
        XCTAssertFalse(timing.isEnabled)
        timing.record(.render, 12)
        XCTAssertEqual(timing.stats(for: .render).count, 0)

        var ran = false
        let value = timing.measure(.draw) {
            ran = true
            return 7
        }
        XCTAssertTrue(ran)
        XCTAssertEqual(value, 7)
        XCTAssertEqual(timing.stats(for: .draw).count, 0)
    }

    func testPercentilesAndOverBudgetCount() {
        let timing = enabledTiming(frameBudgetMs: 3)
        for value in [1.0, 2.0, 3.0, 4.0] {
            timing.record(.draw, value)
        }
        let stats = timing.stats(for: .draw)
        XCTAssertEqual(stats.count, 4)
        XCTAssertEqual(stats.p50Ms, 2.5, accuracy: 0.001)
        XCTAssertEqual(stats.p95Ms, 3.85, accuracy: 0.001)
        XCTAssertEqual(stats.p99Ms, 3.97, accuracy: 0.001)
        XCTAssertEqual(stats.maxMs, 4.0, accuracy: 0.001)
        // Only 4.0 ms exceeds the 3 ms budget.
        XCTAssertEqual(stats.overBudget, 1)
    }

    func testMeasureRecordsElapsedTimeAndReturnsValue() {
        let timing = enabledTiming()
        let value = timing.measure(.render) {
            Thread.sleep(forTimeInterval: 0.002)
            return 42
        }
        XCTAssertEqual(value, 42)
        let stats = timing.stats(for: .render)
        XCTAssertEqual(stats.count, 1)
        XCTAssertGreaterThan(stats.p50Ms, 1.0)
    }

    func testTargetLeadIsSignedAndNeverCountedAsOverBudget() {
        let timing = enabledTiming(frameBudgetMs: 1)
        timing.record(.targetLead, 20)
        timing.record(.targetLead, -4)
        let stats = timing.stats(for: .targetLead)
        XCTAssertEqual(stats.count, 2)
        XCTAssertEqual(stats.overBudget, 0)
        XCTAssertEqual(stats.maxMs, 20, accuracy: 0.001)
    }

    func testSummaryReportsStagesAndEvents() {
        let timing = enabledTiming()
        timing.record(.draw, 5)
        timing.record(.swap, 9)
        timing.recordEvent("app.inactive")
        let summary = timing.summary()
        XCTAssertEqual(summary["enabled"] as? Bool, true)
        let stages = summary["stages"] as? [String: Any]
        XCTAssertNotNil(stages?["draw"])
        XCTAssertNotNil(stages?["swap"])
        let events = summary["events"] as? [[String: Any]]
        XCTAssertEqual(events?.first?["event"] as? String, "app.inactive")
    }

    func testRingIsBoundedButTotalCountKeepsGrowing() {
        let timing = RenderTiming(environment: [
            "OPENFUSE_RENDER_TIMING": "1",
            "OPENFUSE_RENDER_TIMING_INTERVAL": "0",
            "OPENFUSE_RENDER_TIMING_CAPACITY": "16",
        ])
        for index in 0..<20 {
            timing.record(.draw, Double(index))
        }
        let stats = timing.stats(for: .draw)
        XCTAssertEqual(stats.count, 20)
        // Only the 16 most recent samples feed the percentiles.
        XCTAssertEqual(stats.maxMs, 19, accuracy: 0.001)
    }

    func testEmptyPercentileIsZero() {
        XCTAssertEqual(RenderTiming.percentile([], 0.5), 0)
        XCTAssertEqual(RenderTiming.percentile([3], 0.95), 3)
    }
}

final class MPVEngineTargetLeadTests: XCTestCase {
    func testTargetLeadUsesNanosecondTargetTime() {
        // target_time is mp_time_ns() units; mpv_get_time_us() is microseconds.
        XCTAssertEqual(
            MPVEngine.targetLeadMilliseconds(targetTime: 5_000_000, nowMicroseconds: 4_000),
            1.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            MPVEngine.targetLeadMilliseconds(targetTime: 4_000_000, nowMicroseconds: 4_500),
            -0.5,
            accuracy: 0.0001
        )
    }
}
