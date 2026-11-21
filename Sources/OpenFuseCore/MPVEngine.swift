import AppKit
import CMpv
import Darwin
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

/// One buffered span reported by mpv's demuxer cache.
public struct MPVCacheRange: Hashable, Sendable {
    public var start: Double
    public var end: Double
    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }
}

/// Snapshot of mpv's demuxer cache, used by the player HUD and the progress
/// bar. Mirrors what IINA reads in `PlayerCore.syncUI(.time)`:
/// `demuxer-cache-state`'s `seekable-ranges` / `fw-bytes` / `raw-input-rate`,
/// plus `demuxer-cache-time`, `cache-buffering-state` and `paused-for-cache`.
public struct MPVCacheState: Sendable {
    public var bufferedEnd: Double = 0
    public var ranges: [MPVCacheRange] = []
    public var speedBytesPerSecond: Double = 0
    public var usedBytes: Int64 = 0
    public var bufferingPercent: Int = 0
    public var pausedForCache: Bool = false
    /// True once mpv reported at least one download-speed sample for this file.
    public var hasSpeedSample: Bool = false
}

public struct MPVSnapshot: Sendable {
    public var position: Double
    public var duration: Double
    public var isPaused: Bool
    public var tracks: [MPVTrackInfo]
}

/// Thin, thread-safe wrapper around libmpv. Rendering is delegated to
/// `MPVGLView`; this class owns the mpv handle, the event loop and the
/// command surface the app uses. All callbacks fire on the main queue.
public final class MPVEngine: @unchecked Sendable {
    private(set) var handle: OpaquePointer?
    private var renderContext: OpaquePointer?
    private let eventQueue = DispatchQueue(label: "openfuse.mpv.events", qos: .userInitiated)
    private let commandLock = NSLock()
    /// Guards `tracks` and the track-list callback; refreshTracks can be called
    /// from the event loop and from the main thread.
    private let stateLock = NSLock()
    private var stopped = false
    private var stopping = false
    private var eventExited = DispatchSemaphore(value: 0)
    private var lastTimeNotification: CFTimeInterval = 0
    private var cacheState = MPVCacheState()
    private var lastCacheNotification: CFTimeInterval = 0
    private var hasSignaledFirstFrame = false

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
    /// End of the demuxer cache in seconds (kept for the playhead clock).
    public var onCacheChanged: ((Double) -> Void)?
    /// Full cache snapshot (ranges, speed, used bytes, buffering percentage).
    public var onCacheStateChanged: ((MPVCacheState) -> Void)?
    /// `paused-for-cache`.
    public var onBufferingChanged: ((Bool) -> Void)?
    /// Fired once per file when mpv reports the first decoded video frame; used
    /// to retire the "正在打开…" HUD even when resuming at a non-zero position.
    public var onFirstVideoFrame: (() -> Void)?

    public private(set) var snapshot = MPVSnapshot(position: 0, duration: 0, isPaused: true, tracks: [])

    public init(headless: Bool = false, httpHeaders: [String] = [], thumbnailOutput: URL? = nil) {
        if ProcessInfo.processInfo.environment["OPENFUSE_DEBUG_TIMING"] == "1" {
            FileHandle.standardError.write(Data("[timing] mpvEngine.init.begin\n".utf8))
        }
        handle = mpv_create()
        guard let handle else {
            fatalError("mpv_create failed")
        }
        setOption("terminal", "no")
        setOption("input-default-bindings", "no")
        setOption("input-vo-keyboard", "no")
        setOption("osc", "no")
        setOption("osd-level", "0")
        if let thumbnailOutput {
            // One decoded frame written as a PNG. Used by the scrubber hover
            // preview on a private engine, so playback is never disturbed.
            try? FileManager.default.createDirectory(at: thumbnailOutput, withIntermediateDirectories: true)
            setOption("vo", "image")
            setOption("vo-image-format", "png")
            setOption("vo-image-outdir", thumbnailOutput.path)
            setOption("frames", "1")
            setOption("hwdec", "no")
            setOption("audio", "no")
            setOption("keep-open", "no")
            setOption("vf", "scale=320:-2")
            setOption("sub-visibility", "no")
            setOption("sid", "no")
        } else {
            setOption("vo", headless ? "null" : "libmpv")
            if !headless {
                setOption("gpu-api", "opengl")
            }
            setOption("hwdec", "videotoolbox")
        }
        let pcmOutput = ProcessInfo.processInfo.environment["OPENFUSE_AO_PCM"] ?? ""
        setOption("ao", (headless || thumbnailOutput != nil) ? "null" : (pcmOutput.isEmpty ? "coreaudio" : "pcm"))
        if !pcmOutput.isEmpty {
            setOption("ao-pcm-file", pcmOutput)
            setOption("ao-pcm-waveheader", "yes")
            setOption("audio-channels", ProcessInfo.processInfo.environment["OPENFUSE_AO_CHANNELS"] ?? "5.1")
        } else {
            setOption("audio-channels", "auto-safe")
        }
        setOption("keep-open", "yes")
        setOption("cache", "yes")
        setOption("cache-secs", "20")
        setOption("demuxer-max-bytes", "512MiB")
        setOption("demuxer-max-back-bytes", "128MiB")
        setOption("video-sync", ProcessInfo.processInfo.environment["OPENFUSE_VIDEO_SYNC"] ?? "audio")
        setOption("audio-pitch-correction", "yes")
        setOption("idle", "yes")
        setOption("sub-auto", "no")
        setOption("audio-file-auto", "no")
        setOption("sub-ass", "yes")
        setOption("sub-scale-with-window", "yes")
        // SDR tone mapping for HDR10/HLG sources. HDR passthrough still
        // depends on the output/compositor and is not verified.
        setOption("tone-mapping", ProcessInfo.processInfo.environment["OPENFUSE_TONE_MAPPING"] ?? "spline")
        setOption("hdr-compute-peak", "yes")
        setOption("target-peak", "auto")
        if thumbnailOutput == nil {
            let edr = NSScreen.main?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1
            let allowHDR = ProcessInfo.processInfo.environment["OPENFUSE_HDR_PASSTHROUGH"] != "0"
            setOption("target-colorspace-hint", (allowHDR && edr > 1) ? "yes" : "no")
        } else {
            setOption("target-colorspace-hint", "no")
        }
        if !httpHeaders.isEmpty {
            setOption("http-header-fields", httpHeaders.joined(separator: ","))
        }
        setOption("screenshot-directory", NSTemporaryDirectory())
        let logLevel = ProcessInfo.processInfo.environment["OPENFUSE_MPV_LOG"] ?? "warn"
        setOption("msg-level", "all=\(logLevel)")

        let code = mpv_initialize(handle)
        if code < 0 {
            onLog?("mpv_initialize failed: \(String(cString: mpv_error_string(code)))")
        }

        mpv_observe_property(handle, 0, "time-pos", MPV_FORMAT_DOUBLE)
        mpv_observe_property(handle, 0, "duration", MPV_FORMAT_DOUBLE)
        mpv_observe_property(handle, 0, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(handle, 0, "track-list", MPV_FORMAT_NONE)
        mpv_observe_property(handle, 0, "eof-reached", MPV_FORMAT_FLAG)
        mpv_observe_property(handle, 0, "demuxer-cache-time", MPV_FORMAT_DOUBLE)
        mpv_observe_property(handle, 0, "demuxer-cache-state", MPV_FORMAT_NONE)
        mpv_observe_property(handle, 0, "cache-buffering-state", MPV_FORMAT_NONE)
        mpv_observe_property(handle, 0, "paused-for-cache", MPV_FORMAT_FLAG)
        mpv_observe_property(handle, 0, "cache-speed", MPV_FORMAT_INT64)
        mpv_observe_property(handle, 0, "video-frame-info", MPV_FORMAT_NONE)
        mpv_request_log_messages(handle, logLevel)

        // Strong capture: the event loop must keep the engine alive for its
        // whole lifetime. A weak capture could leave `self` deallocated on the
        // main thread while the loop was between statements (use-after-free
        // seen as a SIGSEGV in `refreshTracks`).
        eventQueue.async {
            self.runEventLoop()
        }
        if ProcessInfo.processInfo.environment["OPENFUSE_DEBUG_TIMING"] == "1" {
            FileHandle.standardError.write(Data("[timing] mpvEngine.init.end\n".utf8))
        }
    }

    // No `deinit` teardown: the event loop and the terminate block keep this
    // object alive until mpv has shut down. Tearing down from `deinit` could
    // run on the event thread and touch AppKit/GL (or resurrect `self` inside
    // the async terminate closure), which crashed with a SIGSEGV.


    /// Stops the engine without blocking the caller. The GL render context is
    /// released on the main thread (the view calls `prepareForTeardown`), then
    /// `quit` is queued and mpv is destroyed on the event queue after its event
    /// loop exits. The old implementation waited on a semaphore and called
    /// `mpv_terminate_destroy` from the main thread, which could freeze the UI
    /// for seconds when a slow source was still opening.
    public func stop() {
        if stopped || stopping { return }
        stopping = true
        if ProcessInfo.processInfo.environment["OPENFUSE_DEBUG_TIMING"] == "1" {
            FileHandle.standardError.write(Data("[timing] mpvEngine.stop.begin\n".utf8))
        }
        renderView?.prepareForTeardown()
        renderView = nil
        // Release UI callbacks on the main thread, before mpv can deliver more
        // events, so no PlayerModel/AppKit object is deallocated on the mpv
        // event thread during teardown.
        onTimeChanged = nil
        onDurationChanged = nil
        onPauseChanged = nil
        onTracksChanged = nil
        onFileLoaded = nil
        onEndFile = nil
        onEOFReached = nil
        onLog = nil
        onRenderContextReady = nil
        onCacheChanged = nil
        onCacheStateChanged = nil
        onBufferingChanged = nil
        onFirstVideoFrame = nil
        guard let handle else { return }
        commandAsync(["quit"])
        mpv_wakeup(handle)
        let handleToDestroy = handle
        eventQueue.async {
            _ = self.eventExited.wait(timeout: .now() + 3)
            mpv_terminate_destroy(handleToDestroy)
            // Publish the closed handle only after termination, and only from
            // the event queue: writing it from the main thread while the event
            // loop was reading it produced a torn Optional and a SIGSEGV.
            self.handle = nil
            self.stopped = true
            if ProcessInfo.processInfo.environment["OPENFUSE_DEBUG_TIMING"] == "1" {
                FileHandle.standardError.write(Data("[timing] mpvEngine.stop.destroyed\n".utf8))
            }
        }
    }

    /// Kept for callers that used the old name; no longer blocks.
    public func shutdown() {
        stop()
    }

    /// Frees the libmpv render context. Must run with the view's GL context
    /// current (see `MPVGLView.prepareForTeardown`).
    func freeRenderContext() {
        guard let renderContext else { return }
        mpv_render_context_set_update_callback(renderContext, nil, nil)
        mpv_render_context_free(renderContext)
        self.renderContext = nil
    }

    // MARK: Options and commands

    private func setOption(_ name: String, _ value: String) {
        guard let handle else { return }
        let code = mpv_set_option_string(handle, name, value)
        if code < 0 {
            onLog?("mpv option \(name)=\(value) failed: \(String(cString: mpv_error_string(code)))")
        }
    }

    public func setProperty(_ name: String, _ value: String) {
        guard !stopping, !stopped else { return }
        guard let handle else { return }
        let code = mpv_set_property_string(handle, name, value)
        if code < 0 {
            onLog?("mpv set \(name)=\(value) failed: \(String(cString: mpv_error_string(code)))")
        }
    }

    /// Non-blocking variant used for loadfile/seek: the UI must never wait for
    /// the demuxer, especially when a remote source is slow to answer.
    private func commandAsync(_ arguments: [String]) {
        commandLock.lock()
        defer { commandLock.unlock() }
        guard let handle else { return }
        var pointers: [UnsafePointer<CChar>?] = arguments.map { UnsafePointer(strdup($0)) }
        defer { pointers.forEach { if let pointer = $0 { free(UnsafeMutablePointer(mutating: pointer)) } } }
        pointers.append(nil)
        let code = mpv_command_async(handle, 0, &pointers)
        if code < 0 {
            onLog?("mpv async command \(arguments.first ?? "?") failed: \(String(cString: mpv_error_string(code)))")
        }
    }

    public func command(_ arguments: [String]) {
        guard !stopping, !stopped else { return }
        commandLock.lock()
        defer { commandLock.unlock() }
        guard let handle else { return }
        var pointers: [UnsafePointer<CChar>?] = arguments.map { argument in
            UnsafePointer(strdup(argument))
        }
        defer { pointers.forEach { if let pointer = $0 { free(UnsafeMutablePointer(mutating: pointer)) } } }
        pointers.append(nil)
        let code = mpv_command(handle, &pointers)
        if code < 0 {
            onLog?("mpv command \(arguments.first ?? "?") failed: \(String(cString: mpv_error_string(code)))")
        }
    }

    public func load(url: URL, startAt: Double = 0) {
        commandAsync(["loadfile", url.isFileURL ? url.path : url.absoluteString, "replace"])
        if startAt > 0.2 {
            // Applied after file-loaded to avoid mpv dropping the seek during
            // demuxer initialisation.
            pendingSeek = startAt
        }
    }

    private var pendingSeek: Double?
    private weak var renderView: MPVGLView?

    public func play() { setProperty("pause", "no") }
    public func pause() { setProperty("pause", "yes") }
    public func togglePause() {
        let paused = snapshot.isPaused
        setProperty("pause", paused ? "no" : "yes")
    }

    public func seek(to seconds: Double, exact: Bool = true) {
        let clamped = max(0, seconds)
        commandAsync(["seek", String(format: "%.3f", clamped), exact ? "absolute+exact" : "absolute"])
    }

    public func setAudioTrack(id: Int64) {
        setProperty("aid", String(id))
    }

    public func setSubtitleTrack(id: Int64?) {
        setProperty("sid", id.map(String.init) ?? "no")
    }

    public func addSubtitle(url: URL, select: Bool = false) {
        // Async: local ASS parsing (+ font setup) can take hundreds of ms and
        // used to stall the main thread for every sidecar right after open.
        commandAsync(["sub-add", url.isFileURL ? url.path : url.absoluteString, select ? "select" : "auto"])
    }

    public func removeSubtitle(id: Int64) {
        command(["sub-remove", String(id)])
    }

    public func setSubtitleVisible(_ visible: Bool) {
        setProperty("sub-visibility", visible ? "yes" : "no")
    }

    public func setSubtitleDelay(_ seconds: Double) {
        setProperty("sub-delay", String(format: "%.3f", seconds))
    }

    public func setAudioChannels(_ layout: String) {
        setProperty("audio-channels", layout)
    }

    public func setVolume(_ volume: Double) {
        guard !stopping, !stopped else { return }
        let clamped = min(max(volume, 0), 100)
        setProperty("volume", String(format: "%.0f", clamped))
    }

    /// Native video size reported by mpv (`width`/`height`), used by the
    /// IINA-style window-size commands.
    public func videoSize() -> CGSize? {
        guard let width = getPropertyString("width").flatMap(Double.init),
              let height = getPropertyString("height").flatMap(Double.init),
              width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    public func getVolume() -> Double? {
        getPropertyString("volume").flatMap(Double.init)
    }

    public func setSpeed(_ speed: Double) {
        setProperty("speed", String(format: "%.2f", speed))
    }

    public func screenshot(to url: URL) {
        if let renderView {
            renderView.requestFrameCapture(to: url)
        } else {
            command(["screenshot-to-file", url.path, "video"])
        }
    }

    // MARK: Rendering

    public func makeRenderContext(view: NSOpenGLView) -> Bool {
        guard let handle, renderContext == nil else { return renderContext != nil }
        renderView = view as? MPVGLView
        dlopen("/System/Library/Frameworks/OpenGL.framework/Versions/A/OpenGL", RTLD_NOW)
        var initParams = mpv_opengl_init_params(
            get_proc_address: { _, name in
                guard let name else { return nil }
                return dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
            },
            get_proc_address_ctx: nil
        )
        let apiType = strdup("opengl")!
        defer { free(apiType) }
        var result: OpaquePointer?
        let code: Int32 = withUnsafeMutablePointer(to: &initParams) { initPointer in
            var params = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: UnsafeMutableRawPointer(apiType)),
                mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: UnsafeMutableRawPointer(initPointer)),
                mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
            ]
            return mpv_render_context_create(&result, handle, &params)
        }
        guard code >= 0, let result else {
            onLog?("mpv render context failed: \(String(cString: mpv_error_string(code)))")
            return false
        }
        renderContext = result
        DispatchQueue.main.async { [weak self] in self?.onRenderContextReady?() }
        let opaque = Unmanaged.passUnretained(view).toOpaque()
        mpv_render_context_set_update_callback(result, { context in
            guard let context else { return }
            let view = Unmanaged<NSOpenGLView>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                view.needsDisplay = true
            }
        }, opaque)
        return true
    }

    @discardableResult
    public func render(into view: NSOpenGLView) -> Int32 {
        guard let renderContext else { return -1 }
        let backing = view.convertToBacking(view.bounds)
        let width = Int32(max(1, backing.width))
        let height = Int32(max(1, backing.height))
        var fbo = mpv_opengl_fbo(fbo: 0, w: width, h: height, internal_format: 0)
        var flip: CInt = 1
        return withUnsafeMutablePointer(to: &fbo) { fboPointer in
            withUnsafeMutablePointer(to: &flip) { flipPointer in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: UnsafeMutableRawPointer(fboPointer)),
                    mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: UnsafeMutableRawPointer(flipPointer)),
                    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                ]
                let code = mpv_render_context_render(renderContext, &params)
                if code < 0 {
                    onLog?("mpv render failed: \(String(cString: mpv_error_string(code)))")
                }
                if ProcessInfo.processInfo.environment["OPENFUSE_DEBUG_GL"] != nil {
                    print("[gl] render code=\(code) size=\(width)x\(height) vo=\(getPropertyString("vo-configured") ?? "?")")
                }
                return code
            }
        }
    }

    public var hasRenderContext: Bool { renderContext != nil }

    public func reportSwap() {
        guard let renderContext else { return }
        mpv_render_context_report_swap(renderContext)
    }

    // MARK: Event loop

    private func runEventLoop() {
        let keepAlive = self
        defer { _ = keepAlive }
        guard let handle else {
            eventExited.signal()
            return
        }
        var shouldExit = false
        while !shouldExit {
            guard let event = mpv_wait_event(handle, 0.2) else { break }
            let eventID = event.pointee.event_id
            if stopping, eventID != MPV_EVENT_SHUTDOWN {
                continue
            }
            switch eventID {
            case MPV_EVENT_NONE:
                continue
            case MPV_EVENT_SHUTDOWN:
                shouldExit = true
            case MPV_EVENT_FILE_LOADED:
                if let target = pendingSeek {
                    pendingSeek = nil
                    seek(to: target)
                }
                refreshTracks()
                DispatchQueue.main.async { [weak self] in self?.onFileLoaded?() }
            case MPV_EVENT_PROPERTY_CHANGE:
                handlePropertyChange(event)
            case MPV_EVENT_END_FILE:
                let reasonCode = event.pointee.data?
                    .assumingMemoryBound(to: mpv_event_end_file.self).pointee.reason
                let reason: String
                switch reasonCode {
                case MPV_END_FILE_REASON_EOF: reason = "eof"
                case MPV_END_FILE_REASON_STOP: reason = "stop"
                case MPV_END_FILE_REASON_QUIT: reason = "quit"
                case MPV_END_FILE_REASON_ERROR: reason = "error"
                default: reason = "unknown"
                }
                DispatchQueue.main.async { [weak self] in self?.onEndFile?(reason) }
            case MPV_EVENT_LOG_MESSAGE:
                if let data = event.pointee.data {
                    let message = data.assumingMemoryBound(to: mpv_event_log_message.self).pointee
                    let prefix = message.prefix.map { String(cString: $0) } ?? ""
                    let level = message.level.map { String(cString: $0) } ?? ""
                    let text = message.text.map { String(cString: $0) } ?? ""
                    let line = "[\(level)] \(prefix): \(text.trimmingCharacters(in: .whitespacesAndNewlines))"
                    DispatchQueue.main.async { [weak self] in self?.onLog?(line) }
                }
            default:
                break
            }
        }
        eventExited.signal()
    }

    private func handlePropertyChange(_ event: UnsafePointer<mpv_event>) {
        guard let data = event.pointee.data else { return }
        let property = data.assumingMemoryBound(to: mpv_event_property.self).pointee
        guard let namePointer = property.name else { return }
        let name = String(cString: namePointer)

        switch name {
        case "time-pos":
            guard property.format == MPV_FORMAT_DOUBLE, let value = property.data else { return }
            let position = value.assumingMemoryBound(to: Double.self).pointee
            snapshot.position = position
            let now = CACurrentMediaTime()
            if now - lastTimeNotification >= 0.05 {
                lastTimeNotification = now
                DispatchQueue.main.async { [weak self] in self?.onTimeChanged?(position) }
            }
        case "duration":
            guard property.format == MPV_FORMAT_DOUBLE, let value = property.data else { return }
            let duration = value.assumingMemoryBound(to: Double.self).pointee
            snapshot.duration = duration
            DispatchQueue.main.async { [weak self] in self?.onDurationChanged?(duration) }
        case "pause":
            guard property.format == MPV_FORMAT_FLAG, let value = property.data else { return }
            let paused = value.assumingMemoryBound(to: Int32.self).pointee != 0
            snapshot.isPaused = paused
            DispatchQueue.main.async { [weak self] in self?.onPauseChanged?(paused) }
        case "track-list":
            refreshTracks()
        case "demuxer-cache-time":
            guard property.format == MPV_FORMAT_DOUBLE, let value = property.data else { return }
            cacheState.bufferedEnd = value.assumingMemoryBound(to: Double.self).pointee
            emitCacheState()
        case "demuxer-cache-state":
            refreshCacheState()
        case "cache-speed":
            guard property.format == MPV_FORMAT_INT64, let value = property.data else { return }
            cacheState.speedBytesPerSecond = Double(value.assumingMemoryBound(to: Int64.self).pointee)
            cacheState.hasSpeedSample = true
            emitCacheState()
        case "video-frame-info":
            guard !hasSignaledFirstFrame else { return }
            hasSignaledFirstFrame = true
            DispatchQueue.main.async { [weak self] in self?.onFirstVideoFrame?() }
        case "cache-buffering-state":
            if let raw = getPropertyString("cache-buffering-state"), let percent = Int(raw) {
                cacheState.bufferingPercent = percent
                emitCacheState()
            }
        case "paused-for-cache":
            guard property.format == MPV_FORMAT_FLAG, let value = property.data else { return }
            cacheState.pausedForCache = value.assumingMemoryBound(to: Int32.self).pointee != 0
            emitCacheState(force: true)
        case "eof-reached":
            guard property.format == MPV_FORMAT_FLAG, let value = property.data else { return }
            let reached = value.assumingMemoryBound(to: Int32.self).pointee != 0
            if reached {
                DispatchQueue.main.async { [weak self] in self?.onEOFReached?() }
            }
        default:
            break
        }
    }

    /// Reads mpv's `demuxer-cache-state` node (JSON) and publishes a snapshot
    /// at most five times per second. `seekable-ranges` is what the progress
    /// bar highlights; `raw-input-rate` is the download speed shown in the
    /// buffering HUD, matching IINA's `cacheSpeed`.
    private func refreshCacheState() {
        guard let json = getPropertyString("demuxer-cache-state"),
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        var spans: [MPVCacheRange] = []
        if let ranges = dict["seekable-ranges"] as? [[String: Any]] {
            spans = ranges.compactMap { entry in
                guard let start = (entry["start"] as? NSNumber)?.doubleValue,
                      let end = (entry["end"] as? NSNumber)?.doubleValue,
                      end > start
                else { return nil }
                return MPVCacheRange(start: start, end: end)
            }
        }
        let cacheEnd = (dict["cache-end"] as? NSNumber)?.doubleValue ?? 0
        if cacheEnd > 0 {
            cacheState.bufferedEnd = cacheEnd
            // `seekable-ranges` only covers spans with an index entry and can
            // lag behind the bytes already downloaded. Extend the span that
            // reaches the cache end, or add a span starting at the playhead so
            // the highlight reflects the forward cache shown in the HUD.
            if let index = spans.lastIndex(where: { $0.start <= cacheEnd + 0.5 && $0.end >= cacheEnd - 6 }) {
                spans[index].end = max(spans[index].end, cacheEnd)
            } else {
                // No indexed span reaches the cache end yet. If the beginning is
                // cached (sequential download) the highlight starts at 0;
                // otherwise it starts where the playhead is.
                let bofCached = (dict["bof-cached"] as? Bool) ?? false
                let start = bofCached ? 0 : max(0, snapshot.position - 0.5)
                spans.append(MPVCacheRange(start: start, end: cacheEnd))
            }
        }
        cacheState.ranges = spans
        if let used = (dict["fw-bytes"] as? NSNumber)?.int64Value {
            cacheState.usedBytes = used
        }
        if let speed = (dict["raw-input-rate"] as? NSNumber)?.doubleValue {
            cacheState.speedBytesPerSecond = speed
            cacheState.hasSpeedSample = true
        }
        if let raw = getPropertyString("cache-buffering-state"), let percent = Int(raw) {
            cacheState.bufferingPercent = percent
        }
        emitCacheState()
    }

    private func emitCacheState(force: Bool = false) {
        let now = CACurrentMediaTime()
        guard force || now - lastCacheNotification >= 0.2 else { return }
        lastCacheNotification = now
        let state = cacheState
        DispatchQueue.main.async { [weak self] in
            self?.onCacheChanged?(state.bufferedEnd)
            self?.onCacheStateChanged?(state)
            self?.onBufferingChanged?(state.pausedForCache)
        }
    }

    public func refreshTracks() {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let handle else { return }
        guard let jsonPointer = mpv_get_property_string(handle, "track-list") else {
            return
        }
        defer { mpv_free(jsonPointer) }
        let json = String(cString: jsonPointer)
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return }
        var tracks: [MPVTrackInfo] = []
        for entry in array {
            guard let id = entry["id"] as? Int64 ?? (entry["id"] as? Int).map(Int64.init) else { continue }
            let type = entry["type"] as? String ?? ""
            tracks.append(
                MPVTrackInfo(
                    id: id,
                    type: type,
                    codec: entry["codec"] as? String,
                    language: entry["lang"] as? String,
                    title: entry["title"] as? String,
                    channels: (entry["demux-channel-count"] as? Int) ?? (entry["audio-channels"] as? Int),
                    channelLayout: entry["demux-channels"] as? String,
                    profile: entry["codec-profile"] as? String,
                    codecDescription: entry["codec-desc"] as? String,
                    external: entry["external"] as? Bool ?? false,
                    externalFilename: entry["external-filename"] as? String,
                    isDefault: entry["default"] as? Bool ?? false,
                    isSelected: entry["selected"] as? Bool ?? false
                )
            )
        }
        snapshot.tracks = tracks
        DispatchQueue.main.async { [weak self] in self?.onTracksChanged?(tracks) }
    }

    public func getPropertyString(_ name: String) -> String? {
        guard let handle, let value = mpv_get_property_string(handle, name) else { return nil }
        defer { mpv_free(value) }
        return String(cString: value)
    }

    /// Frame accounting read from mpv for the acceptance report.
    public var renderStats: [String: Any] {
        var stats: [String: Any] = [
            "renderer": "libmpv/NSOpenGLView",
            "hasRenderContext": hasRenderContext,
        ]
        let counters: [String: String] = [
            "voDropFrameCount": "vo-drop-frame-count",
            "mistimedFrameCount": "mistimed-frame-count",
            "decoderDropFrameCount": "decoder-frame-drop-count",
            "frameDropCount": "frame-drop-count",
        ]
        for (key, property) in counters {
            if let value = getPropertyString(property), let number = Int(value) {
                stats[key] = number
            }
        }
        if let value = getPropertyString("estimated-vf-fps"), let fps = Double(value) { stats["estimatedVFFps"] = fps }
        if let value = getPropertyString("display-fps"), let fps = Double(value) { stats["displayFps"] = fps }
        if let value = getPropertyString("video-sync") { stats["videoSync"] = value }
        return stats
    }

    public var clientAPIversion: UInt64 {
        UInt64(mpv_client_api_version())
    }
}
