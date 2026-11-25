import Foundation
import QuartzCore

/// Opt-in per-stage timing for the synchronous libmpv render path.
///
/// The macOS player renders on the AppKit main thread: the libmpv update
/// callback marks `MPVGLView` dirty, AppKit commits the layer and `draw(_:)`
/// calls into `mpv_render_context_render`, reports the swap and blocks in
/// `NSOpenGLContext.flushBuffer()`. A `Cmd+Tab` away from the window competes
/// with that same main thread, so the fix and its regression cover need to
/// know where each draw's time goes rather than only that "the main thread is
/// busy".
///
/// Enabled with `OPENFUSE_RENDER_TIMING=1`, or by the existing
/// `OPENFUSE_DEBUG_TIMING=1` used by the acceptance scripts. Everything is a
/// no-op when disabled: one boolean check per stage, no allocation, no clock
/// read.
///
/// Samples are kept in a bounded ring per stage so p50/p95/p99/max can be
/// computed on demand. A background timer batch-writes a window summary to
/// stderr every few seconds (`OPENFUSE_RENDER_TIMING_INTERVAL`, default 5 s,
/// `0` disables) instead of touching the disk per frame.
public final class RenderTiming: @unchecked Sendable {
    public enum Stage: String, CaseIterable, Sendable {
        /// Whole `MPVGLView.draw(_:)`, including render, swap and capture.
        case draw
        /// `mpv_render_context_render`, including libmpv's target-time wait.
        case render
        /// `NSOpenGLContext.flushBuffer()`.
        case swap
        /// Framebuffer readback for the player's screenshot request.
        case capture
        /// `mpv_render_context_report_swap`.
        case reportSwap
        /// `target_time - now` in ms for the frame about to be rendered.
        /// Positive means libmpv handed the frame over before its display
        /// time; negative means the render call is already late.
        case targetLead
    }

    public struct StageStats: Sendable {
        public let count: Int
        public let p50Ms: Double
        public let p95Ms: Double
        public let p99Ms: Double
        public let maxMs: Double
        public let totalMs: Double
        public let overBudget: Int
    }

    public static let shared = RenderTiming()

    public let isEnabled: Bool
    public let frameBudgetMs: Double
    private let capacity: Int
    private let flushInterval: Double

    private let lock = NSLock()
    private var rings: [Stage: [Double]] = [:]
    private var ringIndex: [Stage: Int] = [:]
    private var totals: [Stage: Int] = [:]
    private var overBudget: [Stage: Int] = [:]
    /// Samples since the last periodic flush.
    private var pending: [Stage: [Double]] = [:]
    private var events: [(timeMs: Double, name: String)] = []
    private var eventRingIndex = 0
    private let startTime = CACurrentMediaTime()
    private var timer: DispatchSourceTimer?
    private var lastFlush = CACurrentMediaTime()
    private let logQueue = DispatchQueue(label: "openfuse.render.timing", qos: .utility)

    /// `environment` is injectable so the unit tests do not have to rewrite the
    /// process environment.
    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let renderTiming = environment["OPENFUSE_RENDER_TIMING"] == "1"
        let debugTiming = environment["OPENFUSE_DEBUG_TIMING"] == "1"
        isEnabled = renderTiming || debugTiming
        frameBudgetMs = Double(environment["OPENFUSE_FRAME_BUDGET_MS"] ?? "") ?? (1000.0 / 60.0)
        capacity = max(16, Int(environment["OPENFUSE_RENDER_TIMING_CAPACITY"] ?? "") ?? 4096)
        flushInterval = Double(environment["OPENFUSE_RENDER_TIMING_INTERVAL"] ?? "") ?? 5
        if isEnabled {
            reset()
        }
    }

    // MARK: - Recording

    /// Measures `body` and records its wall time. Returns `body`'s value.
    @inline(__always)
    public func measure<T>(_ stage: Stage, _ body: () -> T) -> T {
        guard isEnabled else { return body() }
        let start = CACurrentMediaTime()
        let result = body()
        record(stage, (CACurrentMediaTime() - start) * 1000)
        return result
    }

    /// Records one already-measured duration in milliseconds.
    public func record(_ stage: Stage, _ milliseconds: Double) {
        guard isEnabled else { return }
        lock.lock()
        defer { lock.unlock() }
        if rings[stage] == nil {
            rings[stage] = []
            pending[stage] = []
        }
        var ring = rings[stage] ?? []
        let index = ringIndex[stage] ?? 0
        if ring.count < capacity {
            ring.append(milliseconds)
        } else {
            ring[index] = milliseconds
        }
        ringIndex[stage] = (index + 1) % capacity
        rings[stage] = ring
        totals[stage, default: 0] += 1
        // `targetLead` is a signed schedule offset, not a duration.
        if stage != .targetLead, milliseconds > frameBudgetMs {
            overBudget[stage, default: 0] += 1
        }
        var window = pending[stage] ?? []
        if window.count >= capacity {
            window.removeFirst()
        }
        window.append(milliseconds)
        pending[stage] = window
    }

    /// App activation, window occlusion and player lifecycle markers. They are
    /// written next to the timing windows so a `Cmd+Tab` round can be paired
    /// with the draw samples it produced.
    public func recordEvent(_ name: String) {
        guard isEnabled else { return }
        let timeMs = (CACurrentMediaTime() - startTime) * 1000
        lock.lock()
        if events.count < 256 {
            events.append((timeMs, name))
        } else {
            events[eventRingIndex] = (timeMs, name)
            eventRingIndex = (eventRingIndex + 1) % 256
        }
        lock.unlock()
        let line = String(format: "[timing] render-event %9.1fms %@\n", timeMs, name)
        logQueue.async {
            FileHandle.standardError.write(Data(line.utf8))
        }
    }

    // MARK: - Reading

    public func stats(for stage: Stage) -> StageStats {
        lock.lock()
        let ring = rings[stage] ?? []
        let total = totals[stage] ?? 0
        let over = overBudget[stage] ?? 0
        lock.unlock()
        let sorted = ring.sorted()
        return StageStats(
            count: total,
            p50Ms: Self.percentile(sorted, 0.50),
            p95Ms: Self.percentile(sorted, 0.95),
            p99Ms: Self.percentile(sorted, 0.99),
            maxMs: sorted.last ?? 0,
            totalMs: sorted.reduce(0, +),
            overBudget: over
        )
    }

    /// Report-shaped snapshot, merged into the acceptance JSON.
    public func summary() -> [String: Any] {
        var stages: [String: Any] = [:]
        for stage in Stage.allCases {
            let stats = stats(for: stage)
            guard stats.count > 0 else { continue }
            stages[stage.rawValue] = [
                "count": stats.count,
                "p50Ms": rounded(stats.p50Ms),
                "p95Ms": rounded(stats.p95Ms),
                "p99Ms": rounded(stats.p99Ms),
                "maxMs": rounded(stats.maxMs),
                "overBudget": stats.overBudget,
                "frameBudgetMs": rounded(frameBudgetMs),
            ]
        }
        lock.lock()
        let captured = events.sorted { $0.timeMs < $1.timeMs }
        lock.unlock()
        return [
            "enabled": isEnabled,
            "frameBudgetMs": rounded(frameBudgetMs),
            "stages": stages,
            "events": captured.map { ["t": rounded($0.timeMs), "event": $0.name] },
        ]
    }

    // MARK: - Periodic window log

    /// Starts the batched stderr summary used while sampling. Safe to call
    /// more than once.
    public func startPeriodicLogging() {
        guard isEnabled, flushInterval > 0 else { return }
        lock.lock()
        if timer != nil {
            lock.unlock()
            return
        }
        let source = DispatchSource.makeTimerSource(queue: logQueue)
        source.schedule(deadline: .now() + flushInterval, repeating: flushInterval, leeway: .milliseconds(250))
        source.setEventHandler { [weak self] in self?.flushWindow() }
        timer = source
        lock.unlock()
        source.resume()
    }

    /// Writes one window summary and clears the window buffers. The delta is
    /// what makes "before/after" comparable: the totals stay in `summary()`,
    /// while each window shows the p95 of the frames actually drawn during
    /// that interval.
    public func flushWindow() {
        guard isEnabled else { return }
        lock.lock()
        let now = CACurrentMediaTime()
        let seconds = max(now - lastFlush, 0.001)
        let window = pending
        pending = [:]
        lastFlush = now
        lock.unlock()

        var parts: [String] = []
        for stage in Stage.allCases {
            guard let samples = window[stage], !samples.isEmpty else { continue }
            let sorted = samples.sorted()
            if stage == .targetLead {
                parts.append(String(
                    format: "%@ n=%d p50=%.1f p95=%.1f p99=%.1f max=%.1f",
                    stage.rawValue,
                    sorted.count,
                    Self.percentile(sorted, 0.50),
                    Self.percentile(sorted, 0.95),
                    Self.percentile(sorted, 0.99),
                    sorted.last ?? 0
                ))
            } else {
                let over = sorted.filter { $0 > frameBudgetMs }.count
                parts.append(String(
                    format: "%@ n=%d p50=%.1f p95=%.1f p99=%.1f max=%.1f overBudget=%d",
                    stage.rawValue,
                    sorted.count,
                    Self.percentile(sorted, 0.50),
                    Self.percentile(sorted, 0.95),
                    Self.percentile(sorted, 0.99),
                    sorted.last ?? 0,
                    over
                ))
            }
        }
        guard !parts.isEmpty else { return }
        let line = String(format: "[timing] render-window %.1fs %@\n", seconds, parts.joined(separator: " "))
        // Synchronous: the window summary must survive a terminate right after
        // the last switch, and it is only written once per interval.
        FileHandle.standardError.write(Data(line.utf8))
    }

    /// Final block for the acceptance log at teardown.
    public func logSummary(label: String = "render-final") {
        guard isEnabled else { return }
        flushWindow()
        var parts: [String] = []
        for stage in Stage.allCases {
            let stats = stats(for: stage)
            guard stats.count > 0 else { continue }
            parts.append(String(
                format: "%@ n=%d p50=%.1f p95=%.1f p99=%.1f max=%.1f over=%d",
                stage.rawValue,
                stats.count,
                stats.p50Ms,
                stats.p95Ms,
                stats.p99Ms,
                stats.maxMs,
                stats.overBudget
            ))
        }
        let line = "[timing] \(label) \(parts.joined(separator: " "))\n"
        // Called from teardown (main thread) and must reach the log before the
        // process exits.
        FileHandle.standardError.write(Data(line.utf8))
    }

    // MARK: - Helpers

    private func reset() {
        rings = [:]
        ringIndex = [:]
        totals = [:]
        overBudget = [:]
        pending = [:]
        events = []
        eventRingIndex = 0
    }

    private func rounded(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let position = fraction * Double(sorted.count - 1)
        let lower = Int(position)
        let upper = min(lower + 1, sorted.count - 1)
        let weight = position - Double(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }
}
