import Foundation

/// Chooses the libmpv timing options for the macOS interactive playback
/// engine.
///
/// `video-sync=audio` lets libmpv start a frame up to `video-timing-offset`
/// seconds early and then block inside `mpv_render_context_render()` until the
/// target display time. OpenFuse renders that call synchronously from
/// `MPVGLView.draw(_:)` on the AppKit main thread, so the wait lands on the
/// same thread that `Cmd+Tab` needs to hand the window over to WindowServer.
///
/// The interactive engine is the only macOS engine with a visible
/// `NSOpenGLView` drawable: the headless probe and the thumbnail engine use
/// `vo=null`/`vo=image` and never share the main-thread draw path. Other
/// `video-sync` modes (`display-resample`, `desync`, ...) own their own present
/// pacing, so this policy only touches the default audio-clock mode.
public enum MPVVideoTimingPolicy {
    /// Default timing offset for the interactive engine. `0` removes the
    /// early-render headroom that turns into a blocking wait on the main
    /// thread; libmpv keeps scheduling frames from the audio clock.
    public static let interactiveTimingOffset = "0"

    /// Offset applied to a given engine, or `nil` when the engine keeps mpv's
    /// own default (0.05 s).
    ///
    /// `OPENFUSE_VIDEO_TIMING_OFFSET` overrides the chosen value so an A/B run
    /// can compare the old default without a second build:
    ///
    ///     OPENFUSE_VIDEO_TIMING_OFFSET=0.05   # group A (pre-fix behaviour)
    ///     OPENFUSE_VIDEO_TIMING_OFFSET=0      # group B (fix)
    ///
    /// An empty value means "leave mpv's default alone".
    public static func timingOffset(
        videoSync: String,
        headless: Bool,
        thumbnailOutput: URL?,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        if let override = environment["OPENFUSE_VIDEO_TIMING_OFFSET"] {
            if override.isEmpty { return nil }
            return override
        }
        guard !headless, thumbnailOutput == nil else { return nil }
        guard videoSync == "audio" else { return nil }
        return interactiveTimingOffset
    }

    /// `MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME=0` is the diagnostic alternative
    /// to the timing-offset change. It disables the wait without moving the
    /// update callback later, so frames can be presented early; it is opt-in
    /// and never applied together with the default fix.
    public static func disablesBlockForTargetTime(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment["OPENFUSE_BLOCK_FOR_TARGET_TIME"] == "0"
    }

    /// Effective `video-sync` for an engine. Mirrors `MPVEngine.init` so the
    /// policy and the engine can be tested without libmpv.
    public static func effectiveVideoSync(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        environment["OPENFUSE_VIDEO_SYNC"] ?? "audio"
    }
}
