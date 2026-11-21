import Combine
import Foundation
import QuartzCore

/// UI-facing playhead, published at a fixed low rate.
///
/// The player used to publish `position` from `PlayerModel` 20 times a second.
/// Every tick invalidated the whole player chrome (three `Menu`s, the AirPlay
/// route picker and the fullscreen button) on the main thread, which is one of
/// the two causes of the occasional MKV stutter: an AppKit draw that lands
/// while SwiftUI is re-laying out the control bar misses its vsync deadline.
///
/// Keeping the playhead in a separate observable means a tick only invalidates
/// the scrubber subtree. 10 Hz is what a progress bar can show anyway; the
/// engine still samples mpv at 50 ms internally for resume/report accuracy.
/// One buffered span on the timeline (seconds).
public struct BufferedRange: Equatable, Sendable {
    public var start: Double
    public var end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }
}

@MainActor
public final class PlaybackClock: ObservableObject {
    /// Playhead in seconds, already throttled for display.
    @Published public private(set) var position: Double = 0
    /// End of the demuxer cache in seconds; 0 means "no buffered range known".
    @Published public private(set) var buffered: Double = 0
    /// Buffered spans for the progress bar highlight. Published at ~5 Hz: the
    /// demuxer cache updates far more often than a progress bar needs.
    @Published public private(set) var bufferedRanges: [BufferedRange] = []

    private let minimumInterval: TimeInterval
    private let now: () -> TimeInterval
    private var lastPublish: TimeInterval
    private var lastRangePublish: TimeInterval

    public init(
        minimumInterval: TimeInterval = 0.1,
        now: @escaping () -> TimeInterval = { CACurrentMediaTime() }
    ) {
        self.minimumInterval = minimumInterval
        self.now = now
        self.lastPublish = now() - minimumInterval
        self.lastRangePublish = now() - minimumInterval
    }

    /// Records a new playhead. `force` bypasses the throttle so a seek is
    /// reflected immediately instead of up to 100 ms later.
    public func update(position newValue: Double, force: Bool = false) {
        let timestamp = now()
        guard force || timestamp - lastPublish >= minimumInterval else { return }
        lastPublish = timestamp
        let clamped = max(0, newValue)
        if abs(clamped - position) > 0.0005 {
            position = clamped
        }
    }

    public func update(buffered newValue: Double) {
        let clamped = max(0, newValue)
        if abs(clamped - buffered) > 0.0005 {
            buffered = clamped
        }
    }

    /// Updates the cached spans drawn on the progress bar. `bufferedEnd` is the
    /// single "cache end" value used by simpler displays and kept in sync.
    public func update(bufferedRanges ranges: [BufferedRange], bufferedEnd: Double) {
        update(buffered: bufferedEnd)
        let timestamp = now()
        guard timestamp - lastRangePublish >= 0.2 else { return }
        lastRangePublish = timestamp
        let cleaned = ranges
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }
        if cleaned != bufferedRanges {
            bufferedRanges = cleaned
        }
    }

    /// New file, or playback restarted from the beginning.
    public func reset(position newValue: Double = 0, buffered newValue2: Double = 0) {
        lastPublish = now()
        lastRangePublish = now()
        position = max(0, newValue)
        buffered = max(0, newValue2)
        bufferedRanges = []
    }
}
