import Combine
import XCTest
@testable import OpenFuseCore

@MainActor
final class PlaybackClockTests: XCTestCase {
    private final class FakeTime {
        var seconds: Double = 0
    }

    func testPublishesAtTenHertz() {
        let time = FakeTime()
        let clock = PlaybackClock(now: { time.seconds })
        var publishes = 0
        let token = clock.objectWillChange.sink { _ in publishes += 1 }

        // A 1 kHz mpv stream must not invalidate the UI 1000 times a second.
        for index in 0..<1000 {
            time.seconds = Double(index) / 1000
            clock.update(position: Double(index) / 1000)
        }
        XCTAssertLessThanOrEqual(publishes, 12, "10 Hz clock published \(publishes) times for 1 s of updates")
        withExtendedLifetime(token) {}
    }

    func testForceBypassesThrottle() {
        let time = FakeTime()
        let clock = PlaybackClock(now: { time.seconds })
        clock.update(position: 12.0, force: true)
        XCTAssertEqual(clock.position, 12.0)
        time.seconds += 0.001
        clock.update(position: 30.0, force: true)
        XCTAssertEqual(clock.position, 30.0)
    }

    func testThrottleHoldsUntilIntervalElapsed() {
        let time = FakeTime()
        let clock = PlaybackClock(now: { time.seconds })
        clock.update(position: 1.0)
        XCTAssertEqual(clock.position, 1.0)
        time.seconds += 0.02
        clock.update(position: 2.0)
        XCTAssertEqual(clock.position, 1.0, "update inside the 100 ms window must be dropped")
        time.seconds += 0.1
        clock.update(position: 3.0)
        XCTAssertEqual(clock.position, 3.0)
    }

    func testResetClearsBufferedRange() {
        let time = FakeTime()
        let clock = PlaybackClock(now: { time.seconds })
        clock.update(position: 42)
        clock.update(buffered: 90)
        XCTAssertEqual(clock.buffered, 90)
        clock.reset(position: 0)
        XCTAssertEqual(clock.position, 0)
        XCTAssertEqual(clock.buffered, 0)
    }

    func testNegativePositionsClampToZero() {
        let clock = PlaybackClock(now: { 0 })
        clock.update(position: -3, force: true)
        XCTAssertEqual(clock.position, 0)
    }

    func testBufferedRangesAreThrottledAndReset() {
        let time = FakeTime()
        let clock = PlaybackClock(now: { time.seconds })
        clock.update(bufferedRanges: [BufferedRange(start: 0, end: 10)], bufferedEnd: 10)
        XCTAssertEqual(clock.bufferedRanges, [BufferedRange(start: 0, end: 10)])
        XCTAssertEqual(clock.buffered, 10)

        // Inside the 200 ms window: the progress bar keeps the previous spans.
        time.seconds += 0.05
        clock.update(bufferedRanges: [BufferedRange(start: 0, end: 30)], bufferedEnd: 30)
        XCTAssertEqual(clock.bufferedRanges, [BufferedRange(start: 0, end: 10)])
        XCTAssertEqual(clock.buffered, 30, "the cache end is not throttled")

        time.seconds += 0.2
        clock.update(bufferedRanges: [BufferedRange(start: 0, end: 30), BufferedRange(start: 40, end: 50)], bufferedEnd: 50)
        XCTAssertEqual(clock.bufferedRanges.count, 2)

        clock.reset(position: 0)
        XCTAssertTrue(clock.bufferedRanges.isEmpty)
    }
}
