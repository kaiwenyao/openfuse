import AppKit
import CMpv
import Foundation
import QuartzCore

public struct MPVTrackInfo: Hashable, Sendable {
    public var id: Int64
    public var type: String
    public var codec: String?
    public var language: String?
    public var title: String?
    public var channels: Int?
    public var channelLayout: String?
    public var profile: String?
    public var codecDescription: String?
    public var external: Bool
    public var externalFilename: String?
    public var isDefault: Bool
    public var isSelected: Bool
}

public struct MPVSnapshot: Sendable {
    public var position: Double
    public var duration: Double
    public var isPaused: Bool
    public var tracks: [MPVTrackInfo]
}

/// Application-facing façade over `MPVController` + `MPVVideoLayer`.
///
/// The rendering and event plumbing that used to live here (main-thread
/// `NSOpenGLView`, blocking `mpv_wait_event` loop) has been replaced by the
/// IINA-style controller/layer pair; this type keeps the API the app and
/// `openfuse-probe` already use.
public final class MPVEngine: @unchecked Sendable {
    let controller: MPVController

    /// The video view currently presenting this engine, if any.
    weak var videoView: MPVVideoView?
    /// The layer that owns the render context.
    weak var videoLayer: MPVVideoLayer?

    public private(set) var snapshot = MPVSnapshot(position: 0, duration: 0, isPaused: true, tracks: [])

    // MARK: Public callbacks (main queue)

    public var onTimeChanged: ((Double) -> Void)?
    public var onDurationChanged: ((Double) -> Void)?
    public var onPauseChanged: ((Bool) -> Void)?
    public var onTracksChanged: (([MPVTrackInfo]) -> Void)?
    public var onFileLoaded: (() -> Void)?
    public var onEndFile: ((String) -> Void)?
    /// Fired once when `eof-reached` becomes true. With `keep-open=yes` mpv keeps
    /// the last frame on screen instead of emitting end-file, so this is the
    /// signal the player uses to mark an episode finished and move to the next.
    public var onEOFReached: (() -> Void)?
    public var onLog: ((String) -> Void)?
    public var onRenderContextReady: (() -> Void)?
    /// End of the demuxer cache in seconds (0 when unknown).
    public var onCacheChanged: ((Double) -> Void)?
    /// `paused-for-cache`: playback is waiting for the network.
    public var onBufferingChanged: ((Bool) -> Void)?

    private var pendingSeek: Double?
    private var stopped = false

    public init(headless: Bool = false, httpHeaders: [String] = []) {
        controller = MPVController(headless: headless, httpHeaders: httpHeaders)
        wireController()
    }

    deinit {
        shutdown()
    }

    private func wireController() {
        controller.onTimeChanged = { [weak self] value in
            guard let self else { return }
            self.snapshot.position = value
            self.onTimeChanged?(value)
        }
        controller.onDurationChanged = { [weak self] value in
            guard let self else { return }
            self.snapshot.duration = value
            self.onDurationChanged?(value)
        }
        controller.onPauseChanged = { [weak self] paused in
            guard let self else { return }
            self.snapshot.isPaused = paused
            self.videoView?.setPlaybackActive(!paused)
            self.onPauseChanged?(paused)
        }
        controller.onTracksChanged = { [weak self] tracks in
            guard let self else { return }
            self.snapshot.tracks = tracks
            self.onTracksChanged?(tracks)
        }
        controller.onFileLoaded = { [weak self] in
            guard let self else { return }
            if let target = self.pendingSeek {
                self.pendingSeek = nil
                self.controller.commandAsync(["seek", String(format: "%.3f", target), "absolute+exact"])
            }
            self.onFileLoaded?()
        }
        controller.onEndFile = { [weak self] reason in self?.onEndFile?(reason) }
        controller.onEOFReached = { [weak self] in self?.onEOFReached?() }
        controller.onCacheChanged = { [weak self] buffered in self?.onCacheChanged?(buffered) }
        controller.onBufferingChanged = { [weak self] buffering in self?.onBufferingChanged?(buffering) }
        controller.onLog = { [weak self] message in
            FileHandle.standardError.write("[mpv] \(message)\n".data(using: .utf8)!)
            self?.onLog?(message)
        }
    }

    // MARK: Registration

    func register(videoView: MPVVideoView, layer: MPVVideoLayer) {
        self.videoView = videoView
        self.videoLayer = layer
    }

    /// Creates the render context for a freshly attached layer. The callback is
    /// deferred: it starts playback, which must not run inside SwiftUI's
    /// `makeNSView`.
    func attachRenderer(layer: MPVVideoLayer) {
        guard !stopped else { return }
        videoLayer = layer
        guard layer.attachRenderer() else { return }
        DispatchQueue.main.async { [weak self] in self?.onRenderContextReady?() }
    }

    // MARK: Lifecycle

    public func shutdown() {
        if stopped { return }
        stopped = true
        videoView?.uninit()
        controller.shutdown()
    }

    // MARK: Options and commands

    public func setProperty(_ name: String, _ value: String) {
        controller.setProperty(name, value)
    }

    public func command(_ arguments: [String]) {
        controller.command(arguments)
    }

    public func load(url: URL, startAt: Double = 0) {
        controller.commandAsync(["loadfile", url.isFileURL ? url.path : url.absoluteString, "replace"])
        if startAt > 0.2 {
            // Applied after file-loaded: mpv drops a seek issued while the
            // demuxer is still initialising.
            pendingSeek = startAt
        }
    }

    public func play() { controller.setProperty("pause", "no") }
    public func pause() { controller.setProperty("pause", "yes") }
    public func togglePause() {
        controller.setProperty("pause", controller.isPaused ? "no" : "yes")
    }

    public func seek(to seconds: Double, exact: Bool = true) {
        let clamped = max(0, seconds)
        controller.commandAsync(["seek", String(format: "%.3f", clamped), exact ? "absolute+exact" : "absolute"])
    }

    public func setAudioTrack(id: Int64) {
        controller.setProperty("aid", String(id))
    }

    public func setSubtitleTrack(id: Int64?) {
        controller.setProperty("sid", id.map(String.init) ?? "no")
    }

    public func addSubtitle(url: URL, select: Bool = false) {
        controller.command(["sub-add", url.isFileURL ? url.path : url.absoluteString, select ? "select" : "auto"])
    }

    public func removeSubtitle(id: Int64) {
        controller.command(["sub-remove", String(id)])
    }

    public func setSubtitleVisible(_ visible: Bool) {
        controller.setProperty("sub-visibility", visible ? "yes" : "no")
    }

    public func setSubtitleDelay(_ seconds: Double) {
        controller.setProperty("sub-delay", String(format: "%.3f", seconds))
    }

    public func setAudioChannels(_ layout: String) {
        controller.setProperty("audio-channels", layout)
    }

    public func setSpeed(_ speed: Double) {
        controller.setProperty("speed", String(format: "%.2f", speed))
    }

    // MARK: Rendering / capture

    public var hasRenderContext: Bool { controller.renderContext != nil }

    /// Called from the CVDisplayLink once per display refresh; libmpv uses it
    /// for frame pacing and dropped-frame accounting.
    public func reportSwap() {
        guard !stopped else { return }
        controller.reportSwap()
    }

    public func screenshot(to url: URL) {
        if let layer = videoLayer, hasRenderContext {
            layer.requestFrameCapture(to: url)
        } else {
            controller.command(["screenshot-to-file", url.path, "video"])
        }
    }

    /// Frame accounting read straight from mpv. Used by the acceptance report
    /// and by `Scripts/run-player-pipeline.sh` to prove the stutter is gone.
    public var renderStats: [String: Any] {
        var stats: [String: Any] = [
            "renderer": "libmpv/CAOpenGLLayer",
            "hasRenderContext": hasRenderContext,
        ]
        if let value = controller.getInt("vo-drop-frame-count") { stats["voDropFrameCount"] = value }
        if let value = controller.getInt("mistimed-frame-count") { stats["mistimedFrameCount"] = value }
        if let value = controller.getInt("decoder-frame-drop-count") { stats["decoderDropFrameCount"] = value }
        if let value = controller.getInt("frame-drop-count") { stats["frameDropCount"] = value }
        if let value = controller.getDouble("estimated-vf-fps") { stats["estimatedVFFps"] = value }
        if let value = controller.getDouble("display-fps") { stats["displayFps"] = value }
        if let value = controller.getString("video-sync") { stats["videoSync"] = value }
        if let value = controller.getDouble("demuxer-cache-time") { stats["bufferAhead"] = value }
        return stats
    }

    public func refreshTracks() {
        controller.refreshTracks()
    }

    public func getPropertyString(_ name: String) -> String? {
        controller.getString(name)
    }

    public var clientAPIversion: UInt64 {
        UInt64(mpv_client_api_version())
    }
}
