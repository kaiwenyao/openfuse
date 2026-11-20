import AppKit
import CMpv
import Darwin
import Foundation
import OpenGL.GL

/// A decoded `mpv_node`, used for structured properties (`track-list`,
/// `video-params`). Mirrors IINA's `MPVNode` handling: read once with
/// `mpv_get_property(…, MPV_FORMAT_NODE, …)` instead of serialising to JSON on
/// every change.
enum MPVNodeValue {
    case string(String)
    case double(Double)
    case int(Int64)
    case bool(Bool)
    case array([MPVNodeValue])
    case dictionary([String: MPVNodeValue])
    case none

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var doubleValue: Double? {
        switch self {
        case .double(let value): return value
        case .int(let value): return Double(value)
        default: return nil
        }
    }

    var intValue: Int64? {
        switch self {
        case .int(let value): return value
        case .double(let value): return Int64(value)
        case .bool(let value): return value ? 1 : 0
        default: return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value): return value
        case .int(let value): return value != 0
        default: return nil
        }
    }

    var arrayValue: [MPVNodeValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var dictionaryValue: [String: MPVNodeValue]? {
        if case .dictionary(let value) = self { return value }
        return nil
    }
}

/// libmpv core: options, event pump, property observation and the render
/// context. Port of IINA's `MPVController.swift`
/// (https://github.com/iina/iina, GPL-3.0); see Docs/M7-PLAYER-PIPELINE.md for
/// the option-by-option mapping.
///
/// Threading contract:
/// - mpv commands/property writes may be issued from any thread (libmpv is
///   thread safe for these); they are serialised by `commandLock`.
/// - The render context is only touched on the thread that made the CGL
///   context current and while holding the CGL lock (`lockAndSetOpenGLContext`
///   / `unlockOpenGLContext`).
/// - All UI callbacks are delivered on the main queue.
public final class MPVController: @unchecked Sendable {
    private(set) var handle: OpaquePointer?
    private(set) var renderContext: OpaquePointer?
    private var openGLContext: CGLContextObj?

    private let commandLock = NSLock()
    private let wakeupLock = NSLock()
    private let eventQueue = DispatchQueue(label: "openfuse.mpv.events", qos: .userInitiated)
    private let queueKey = DispatchSpecificKey<Void>()
    private var wakeupPending = false
    private var stopped = false

    private var lastTimeNotification: CFTimeInterval = 0

    // MARK: Callbacks (main queue)

    var onTimeChanged: ((Double) -> Void)?
    var onDurationChanged: ((Double) -> Void)?
    var onPauseChanged: ((Bool) -> Void)?
    var onTracksChanged: (([MPVTrackInfo]) -> Void)?
    var onFileLoaded: (() -> Void)?
    var onEndFile: ((String) -> Void)?
    var onEOFReached: (() -> Void)?
    var onLog: ((String) -> Void)?
    var onCacheChanged: ((Double) -> Void)?
    var onBufferingChanged: ((Bool) -> Void)?
    var onSpeedChanged: ((Double) -> Void)?

    // MARK: Values mirrored for synchronous reads

    private(set) var duration: Double = 0
    private(set) var isPaused = true
    private(set) var tracks: [MPVTrackInfo] = []
    private(set) var displayFps: Double = 0

    // MARK: Lifecycle

    public init(headless: Bool, httpHeaders: [String]) {
        handle = mpv_create()
        guard let handle else {
            fatalError("mpv_create failed")
        }
        eventQueue.setSpecific(key: queueKey, value: ())
        configureOptions(handle: handle, headless: headless, httpHeaders: httpHeaders)
        let code = mpv_initialize(handle)
        if code < 0 {
            log("mpv_initialize failed: \(String(cString: mpv_error_string(code)))")
        }
        installWakeupCallback()
        observeProperties()
        mpv_request_log_messages(handle, ProcessInfo.processInfo.environment["OPENFUSE_MPV_LOG"] ?? "warn")
    }

    deinit {
        shutdown()
    }

    /// Mirrors IINA's option block; comments call out every deliberate
    /// difference from mpv's own defaults.
    private func configureOptions(handle: OpaquePointer, headless: Bool, httpHeaders: [String]) {
        setOption("terminal", "no")
        setOption("input-default-bindings", "no")
        setOption("input-vo-keyboard", "no")
        setOption("osc", "no")
        setOption("osd-level", "0")
        setOption("vo", headless ? "null" : "libmpv")
        setOption("keepaspect", "yes")
        setOption("gpu-hwdec-interop", "auto")
        // macOS hardware decoding. IINA keeps mpv's default codec whitelist.
        setOption("hwdec", "videotoolbox")
        setOption("vd-lavc-threads", "0")
        // Network/local cache. MKV files with a long GOP benefit from a deeper
        // read-ahead; this is the main "stutter near a seek" mitigation and is
        // the same shape as IINA's cache defaults.
        setOption("cache", "yes")
        setOption("cache-secs", "20")
        setOption("demuxer-max-bytes", "512MiB")
        setOption("demuxer-max-back-bytes", "128MiB")
        setOption("demuxer-readahead-secs", "20")
        // IINA leaves mpv's `audio` default, but on this hardware 24 fps
        // content then lands on a refresh boundary one time in two: measured
        // p99 frame interval 51.0 ms with 19 intervals >50 ms in 30 s.
        // `display-resample` resamples audio to the panel clock and renders on
        // every vsync: p99 12.3 ms, max 17.5 ms, zero intervals >50 ms over the
        // same clip. The audio pitch correction above is what makes that
        // inaudible; OPENFUSE_VIDEO_SYNC=audio restores mpv's default.
        setOption("video-sync", ProcessInfo.processInfo.environment["OPENFUSE_VIDEO_SYNC"] ?? "display-resample")
        setOption("audio-pitch-correction", "yes")
        setOption("keep-open", "yes")
        setOption("idle", "yes")
        setOption("sub-auto", "no")
        setOption("audio-file-auto", "no")
        setOption("sub-ass", "yes")
        setOption("sub-scale-with-window", "yes")

        let pcmOutput = ProcessInfo.processInfo.environment["OPENFUSE_AO_PCM"] ?? ""
        setOption("ao", headless ? "null" : (pcmOutput.isEmpty ? "coreaudio" : "pcm"))
        if !pcmOutput.isEmpty {
            setOption("ao-pcm-file", pcmOutput)
            setOption("ao-pcm-waveheader", "yes")
            setOption("audio-channels", ProcessInfo.processInfo.environment["OPENFUSE_AO_CHANNELS"] ?? "5.1")
        } else {
            setOption("audio-channels", "auto-safe")
        }

        // SDR tone mapping for HDR10/HLG sources. HDR passthrough still
        // depends on the output/compositor and is not verified.
        setOption("tone-mapping", ProcessInfo.processInfo.environment["OPENFUSE_TONE_MAPPING"] ?? "spline")
        setOption("hdr-compute-peak", "yes")
        setOption("target-peak", "auto")
        let edr = NSScreen.main?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1
        let allowHDR = ProcessInfo.processInfo.environment["OPENFUSE_HDR_PASSTHROUGH"] != "0"
        setOption("target-colorspace-hint", (allowHDR && edr > 1) ? "yes" : "no")

        if !httpHeaders.isEmpty {
            setOption("http-header-fields", httpHeaders.joined(separator: ","))
        }
        setOption("screenshot-directory", NSTemporaryDirectory())
        setOption("msg-level", "all=\(ProcessInfo.processInfo.environment["OPENFUSE_MPV_LOG"] ?? "warn")")
        // macOS-specific renderer behaviour: use the GL engine's multithreaded
        // path and do not swap on every render (the layer drives the clock).
        setOption("opengl-swapinterval", "1")
        setOption("opengl-pbo", "yes")
    }

    private func setOption(_ name: String, _ value: String) {
        guard let handle else { return }
        let code = mpv_set_option_string(handle, name, value)
        if code < 0 {
            log("mpv option \(name)=\(value) failed: \(String(cString: mpv_error_string(code)))")
        }
    }

    private func installWakeupCallback() {
        guard let handle else { return }
        mpv_set_wakeup_callback(handle, { context in
            guard let context else { return }
            let controller = Unmanaged<MPVController>.fromOpaque(context).takeUnretainedValue()
            controller.scheduleEventRead()
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    private func observeProperties() {
        guard let handle else { return }
        // Only what the player reacts to; frame counters are read on demand in
        // `MPVEngine.renderStats` so they do not wake the event loop per frame.
        for name in ["time-pos", "duration", "demuxer-cache-time", "speed", "display-fps"] {
            mpv_observe_property(handle, 0, name, MPV_FORMAT_DOUBLE)
        }
        for name in ["pause", "eof-reached", "paused-for-cache"] {
            mpv_observe_property(handle, 0, name, MPV_FORMAT_FLAG)
        }
        mpv_observe_property(handle, 0, "track-list", MPV_FORMAT_NONE)
    }

    // MARK: Event pump

    private func scheduleEventRead() {
        wakeupLock.lock()
        if wakeupPending || stopped {
            wakeupLock.unlock()
            return
        }
        wakeupPending = true
        wakeupLock.unlock()
        eventQueue.async { [weak self] in self?.drainEvents() }
    }

    private func drainEvents() {
        while true {
            wakeupLock.lock()
            wakeupPending = false
            wakeupLock.unlock()
            guard let handle, !stopped else { break }
            var sawShutdown = false
            while let event = mpv_wait_event(handle, 0) {
                if event.pointee.event_id == MPV_EVENT_NONE { break }
                if event.pointee.event_id == MPV_EVENT_SHUTDOWN { sawShutdown = true }
                handleEvent(event)
                if sawShutdown { break }
            }
            if sawShutdown { break }
            wakeupLock.lock()
            let again = wakeupPending
            wakeupLock.unlock()
            if !again { break }
        }
    }

    private func handleEvent(_ event: UnsafePointer<mpv_event>) {
        switch event.pointee.event_id {
        case MPV_EVENT_FILE_LOADED:
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

    private func handlePropertyChange(_ event: UnsafePointer<mpv_event>) {
        guard let data = event.pointee.data else { return }
        let property = data.assumingMemoryBound(to: mpv_event_property.self).pointee
        guard let namePointer = property.name else { return }
        let name = String(cString: namePointer)

        switch name {
        case "time-pos":
            guard property.format == MPV_FORMAT_DOUBLE, let value = property.data else { return }
            let position = value.assumingMemoryBound(to: Double.self).pointee
            let now = CACurrentMediaTime()
            if now - lastTimeNotification >= 0.05 {
                lastTimeNotification = now
                DispatchQueue.main.async { [weak self] in self?.onTimeChanged?(position) }
            }
        case "duration":
            guard property.format == MPV_FORMAT_DOUBLE, let value = property.data else { return }
            let newValue = value.assumingMemoryBound(to: Double.self).pointee
            duration = newValue
            DispatchQueue.main.async { [weak self] in self?.onDurationChanged?(newValue) }
        case "pause":
            guard property.format == MPV_FORMAT_FLAG, let value = property.data else { return }
            let paused = value.assumingMemoryBound(to: Int32.self).pointee != 0
            isPaused = paused
            DispatchQueue.main.async { [weak self] in self?.onPauseChanged?(paused) }
        case "track-list":
            refreshTracks()
        case "eof-reached":
            guard property.format == MPV_FORMAT_FLAG, let value = property.data else { return }
            let reached = value.assumingMemoryBound(to: Int32.self).pointee != 0
            if reached {
                DispatchQueue.main.async { [weak self] in self?.onEOFReached?() }
            }
        case "demuxer-cache-time":
            guard property.format == MPV_FORMAT_DOUBLE, let value = property.data else { return }
            let buffered = value.assumingMemoryBound(to: Double.self).pointee
            DispatchQueue.main.async { [weak self] in self?.onCacheChanged?(buffered) }
        case "paused-for-cache":
            guard property.format == MPV_FORMAT_FLAG, let value = property.data else { return }
            let buffering = value.assumingMemoryBound(to: Int32.self).pointee != 0
            DispatchQueue.main.async { [weak self] in self?.onBufferingChanged?(buffering) }
        case "speed":
            guard property.format == MPV_FORMAT_DOUBLE, let value = property.data else { return }
            let speed = value.assumingMemoryBound(to: Double.self).pointee
            DispatchQueue.main.async { [weak self] in self?.onSpeedChanged?(speed) }
        case "display-fps":
            guard property.format == MPV_FORMAT_DOUBLE, let value = property.data else { return }
            displayFps = value.assumingMemoryBound(to: Double.self).pointee
        default:
            break
        }
    }

    // MARK: Commands

    public func command(_ arguments: [String]) {
        commandLock.lock()
        defer { commandLock.unlock() }
        guard let handle else { return }
        var pointers: [UnsafePointer<CChar>?] = arguments.map { UnsafePointer(strdup($0)) }
        defer { pointers.forEach { if let pointer = $0 { free(UnsafeMutablePointer(mutating: pointer)) } } }
        pointers.append(nil)
        let code = mpv_command(handle, &pointers)
        if code < 0 {
            log("mpv command \(arguments.first ?? "?") failed: \(String(cString: mpv_error_string(code)))")
        }
    }

    /// Non-blocking variant used for seek/loadfile: the UI must never wait for
    /// mpv to finish a demuxer-level operation.
    public func commandAsync(_ arguments: [String]) {
        commandLock.lock()
        defer { commandLock.unlock() }
        guard let handle else { return }
        var pointers: [UnsafePointer<CChar>?] = arguments.map { UnsafePointer(strdup($0)) }
        defer { pointers.forEach { if let pointer = $0 { free(UnsafeMutablePointer(mutating: pointer)) } } }
        pointers.append(nil)
        let code = mpv_command_async(handle, 0, &pointers)
        if code < 0 {
            log("mpv async command \(arguments.first ?? "?") failed: \(String(cString: mpv_error_string(code)))")
        }
    }

    public func setProperty(_ name: String, _ value: String) {
        commandLock.lock()
        defer { commandLock.unlock() }
        guard let handle else { return }
        let code = mpv_set_property_string(handle, name, value)
        if code < 0 {
            log("mpv set \(name)=\(value) failed: \(String(cString: mpv_error_string(code)))")
        }
    }

    public func getString(_ name: String) -> String? {
        commandLock.lock()
        defer { commandLock.unlock() }
        guard let handle, let value = mpv_get_property_string(handle, name) else { return nil }
        defer { mpv_free(value) }
        return String(cString: value)
    }

    public func getDouble(_ name: String) -> Double? {
        guard let handle else { return nil }
        var value = Double()
        guard mpv_get_property(handle, name, MPV_FORMAT_DOUBLE, &value) >= 0 else { return nil }
        return value
    }

    public func getInt(_ name: String) -> Int64? {
        guard let handle else { return nil }
        var value = Int64()
        guard mpv_get_property(handle, name, MPV_FORMAT_INT64, &value) >= 0 else { return nil }
        return value
    }

    public func getFlag(_ name: String) -> Bool? {
        guard let handle else { return nil }
        var value = Int32()
        guard mpv_get_property(handle, name, MPV_FORMAT_FLAG, &value) >= 0 else { return nil }
        return value != 0
    }

    // MARK: Tracks

    public func refreshTracks() {
        guard let list = readNode("track-list")?.arrayValue else { return }
        var result: [MPVTrackInfo] = []
        for entry in list {
            guard let dict = entry.dictionaryValue,
                  let id = dict["id"]?.intValue
            else { continue }
            result.append(
                MPVTrackInfo(
                    id: id,
                    type: dict["type"]?.stringValue ?? "",
                    codec: dict["codec"]?.stringValue,
                    language: dict["lang"]?.stringValue,
                    title: dict["title"]?.stringValue,
                    channels: dict["demux-channel-count"]?.intValue.map(Int.init)
                        ?? dict["audio-channels"]?.intValue.map(Int.init),
                    channelLayout: dict["demux-channels"]?.stringValue,
                    profile: dict["codec-profile"]?.stringValue,
                    codecDescription: dict["codec-desc"]?.stringValue,
                    external: dict["external"]?.boolValue ?? false,
                    externalFilename: dict["external-filename"]?.stringValue,
                    isDefault: dict["default"]?.boolValue ?? false,
                    isSelected: dict["selected"]?.boolValue ?? false
                )
            )
        }
        tracks = result
        DispatchQueue.main.async { [weak self] in self?.onTracksChanged?(result) }
    }

    private func readNode(_ name: String) -> MPVNodeValue? {
        guard let handle else { return nil }
        var node = mpv_node()
        guard mpv_get_property(handle, name, MPV_FORMAT_NODE, &node) >= 0 else { return nil }
        defer { mpv_free_node_contents(&node) }
        return Self.convert(node, depth: 0)
    }

    private static func convert(_ node: mpv_node, depth: Int) -> MPVNodeValue? {
        guard depth < 8 else { return nil }
        switch node.format {
        case MPV_FORMAT_STRING:
            guard let string = node.u.string else { return nil }
            return .string(String(cString: string))
        case MPV_FORMAT_DOUBLE:
            return .double(node.u.double_)
        case MPV_FORMAT_INT64:
            return .int(node.u.int64)
        case MPV_FORMAT_FLAG:
            return .bool(node.u.flag != 0)
        case MPV_FORMAT_NODE_ARRAY:
            guard let list = node.u.list else { return .array([]) }
            var values: [MPVNodeValue] = []
            values.reserveCapacity(Int(list.pointee.num))
            for index in 0..<Int(list.pointee.num) {
                guard let child = list.pointee.values?[index],
                      let converted = convert(child, depth: depth + 1)
                else { continue }
                values.append(converted)
            }
            return .array(values)
        case MPV_FORMAT_NODE_MAP:
            guard let list = node.u.list else { return .dictionary([:]) }
            var values: [String: MPVNodeValue] = [:]
            for index in 0..<Int(list.pointee.num) {
                guard let keyPointer = list.pointee.keys?[index],
                      let child = list.pointee.values?[index],
                      let converted = convert(child, depth: depth + 1)
                else { continue }
                values[String(cString: keyPointer)] = converted
            }
            return .dictionary(values)
        default:
            return .none
        }
    }

    // MARK: Render context

    /// Creates the libmpv render context for `context`. The caller must have
    /// made `context` current and must hold its CGL lock.
    func createRenderContext(openGLContext context: CGLContextObj) -> Bool {
        commandLock.lock()
        defer { commandLock.unlock() }
        guard let handle, renderContext == nil else { return renderContext != nil }
        openGLContext = context
        CGLSetCurrentContext(context)
        dlopen("/System/Library/Frameworks/OpenGL.framework/Versions/A/OpenGL", RTLD_NOW)
        var initParams = mpv_opengl_init_params(
            get_proc_address: { _, name in
                guard let name else { return nil }
                return dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
            },
            get_proc_address_ctx: nil
        )
        let apiType = strdup(MPV_RENDER_API_TYPE_OPENGL)!
        defer { free(apiType) }
        var advanced: CInt = 1
        var result: OpaquePointer?
        let code: Int32 = withUnsafeMutablePointer(to: &initParams) { initPointer in
            withUnsafeMutablePointer(to: &advanced) { advancedPointer in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: UnsafeMutableRawPointer(apiType)),
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: UnsafeMutableRawPointer(initPointer)),
                    mpv_render_param(type: MPV_RENDER_PARAM_ADVANCED_CONTROL, data: UnsafeMutableRawPointer(advancedPointer)),
                    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                ]
                return mpv_render_context_create(&result, handle, &params)
            }
        }
        guard code >= 0, let created = result else {
            log("mpv render context failed: \(String(cString: mpv_error_string(code)))")
            return false
        }
        renderContext = created
        return true
    }

    func setRenderUpdateCallback(
        _ callback: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?,
        context: UnsafeMutableRawPointer?
    ) {
        guard let renderContext else { return }
        mpv_render_context_set_update_callback(renderContext, callback, context)
    }

    func destroyRenderContext() {
        commandLock.lock()
        guard let renderContext else {
            commandLock.unlock()
            return
        }
        self.renderContext = nil
        commandLock.unlock()
        mpv_render_context_set_update_callback(renderContext, nil, nil)
        if let openGLContext {
            CGLLockContext(openGLContext)
            CGLSetCurrentContext(openGLContext)
            mpv_render_context_free(renderContext)
            CGLUnlockContext(openGLContext)
        } else {
            mpv_render_context_free(renderContext)
        }
    }

    func lockAndSetOpenGLContext() {
        guard let openGLContext else { return }
        CGLLockContext(openGLContext)
        CGLSetCurrentContext(openGLContext)
    }

    func unlockOpenGLContext() {
        guard let openGLContext else { return }
        CGLUnlockContext(openGLContext)
    }

    /// `true` when libmpv has a frame that should be drawn now.
    func shouldRenderUpdateFrame() -> Bool {
        guard let renderContext else { return false }
        let flags = mpv_render_context_update(renderContext)
        return flags & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) > 0
    }

    func reportSwap() {
        guard let renderContext else { return }
        mpv_render_context_report_swap(renderContext)
    }

    // MARK: Shutdown

    public func shutdown() {
        wakeupLock.lock()
        if stopped {
            wakeupLock.unlock()
            return
        }
        stopped = true
        wakeupLock.unlock()

        if let handle {
            mpv_unobserve_property(handle, 0)
            if let renderContext {
                mpv_render_context_set_update_callback(renderContext, nil, nil)
            }
            command(["quit"])
            mpv_wakeup(handle)
        }
        // The event queue is serial: a sync barrier guarantees no thread is
        // inside mpv_wait_event() while the handle is destroyed below.
        if DispatchQueue.getSpecific(key: queueKey) == nil {
            eventQueue.sync {}
        }
        destroyRenderContext()
        if let handle {
            mpv_terminate_destroy(handle)
            self.handle = nil
        }
    }

    private func log(_ message: String) {
        onLog?(message)
    }
}
