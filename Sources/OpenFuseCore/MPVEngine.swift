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
    private var stopped = false
    private var eventExited = DispatchSemaphore(value: 0)
    private var lastTimeNotification: CFTimeInterval = 0

    // MARK: Public callbacks (main queue)

    public var onTimeChanged: ((Double) -> Void)?
    public var onDurationChanged: ((Double) -> Void)?
    public var onPauseChanged: ((Bool) -> Void)?
    public var onTracksChanged: (([MPVTrackInfo]) -> Void)?
    public var onFileLoaded: (() -> Void)?
    public var onEndFile: ((String) -> Void)?
    public var onLog: ((String) -> Void)?
    public var onRenderContextReady: (() -> Void)?

    public private(set) var snapshot = MPVSnapshot(position: 0, duration: 0, isPaused: true, tracks: [])

    public init(headless: Bool = false) {
        handle = mpv_create()
        guard let handle else {
            fatalError("mpv_create failed")
        }
        setOption("terminal", "no")
        setOption("input-default-bindings", "no")
        setOption("input-vo-keyboard", "no")
        setOption("osc", "no")
        setOption("osd-level", "0")
        setOption("vo", headless ? "null" : "libmpv")
        if !headless {
            setOption("gpu-api", "opengl")
        }
        setOption("hwdec", "videotoolbox")
        setOption("ao", headless ? "null" : "coreaudio")
        setOption("audio-channels", "auto-safe")
        setOption("keep-open", "yes")
        setOption("idle", "yes")
        setOption("sub-auto", "no")
        setOption("audio-file-auto", "no")
        setOption("sub-ass", "yes")
        setOption("sub-scale-with-window", "yes")
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
        mpv_request_log_messages(handle, logLevel)

        eventQueue.async { [weak self] in
            self?.runEventLoop()
        }
    }

    deinit {
        shutdown()
    }

    public func shutdown() {
        if stopped { return }
        stopped = true
        if let handle {
            command(["quit"])
            mpv_wakeup(handle)
        }
        _ = eventExited.wait(timeout: .now() + 2)
        destroyRenderContext()
        if let handle {
            mpv_terminate_destroy(handle)
            self.handle = nil
        }
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
        guard let handle else { return }
        let code = mpv_set_property_string(handle, name, value)
        if code < 0 {
            onLog?("mpv set \(name)=\(value) failed: \(String(cString: mpv_error_string(code)))")
        }
    }

    public func command(_ arguments: [String]) {
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
        command(["loadfile", url.path, "replace"])
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
        command(["seek", String(format: "%.3f", clamped), exact ? "absolute+exact" : "absolute"])
    }

    public func setAudioTrack(id: Int64) {
        setProperty("aid", String(id))
    }

    public func setSubtitleTrack(id: Int64?) {
        setProperty("sid", id.map(String.init) ?? "no")
    }

    public func addSubtitle(url: URL, select: Bool = false) {
        command(["sub-add", url.path, select ? "select" : "auto"])
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

    private func destroyRenderContext() {
        guard let renderContext else { return }
        mpv_render_context_set_update_callback(renderContext, { _ in }, nil)
        mpv_render_context_free(renderContext)
        self.renderContext = nil
    }

    // MARK: Event loop

    private func runEventLoop() {
        guard let handle else {
            eventExited.signal()
            return
        }
        var shouldExit = false
        while !shouldExit {
            guard let event = mpv_wait_event(handle, 0.2) else { break }
            let eventID = event.pointee.event_id
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
        case "eof-reached":
            break
        default:
            break
        }
    }

    public func refreshTracks() {
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

    public var clientAPIversion: UInt64 {
        UInt64(mpv_client_api_version())
    }
}
