import Foundation
import Libmpv
import UIKit

struct MobileMPVTrack: Identifiable, Hashable {
    var id: Int64
    var type: String          // "sub" | "audio"
    var language: String?
    var title: String?
    var external: Bool

    var displayName: String {
        if let title, !title.isEmpty { return title }
        if let language, !language.isEmpty {
            switch language.lowercased() {
            case "zh-hans", "chi", "zho": return "中文（简体）"
            case "zh-hant": return "中文（繁體）"
            case "eng", "en": return "English"
            case "jpn", "ja": return "日本語"
            default: return language
            }
        }
        return "轨道 \(id)"
    }
}

/// libmpv engine used for containers AVPlayer cannot open (MKV on WebDAV).
/// Rendering goes through `gpu-next` + MoltenVK into a CAMetalLayer, so ASS
/// subtitles are rendered by libass exactly like the Mac player.
@MainActor
final class MobileMPVEngine: ObservableObject {
    @Published var position: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isPaused = false
    @Published var isReady = false
    @Published var errorText: String?
    @Published var subtitleTracks: [MobileMPVTrack] = []
    @Published var audioTracks: [MobileMPVTrack] = []
    @Published var selectedSubtitleID: Int64?
    @Published var selectedAudioID: Int64?
    /// Called when the file reaches its end (mpv `end-file`), used to load the next episode.
    var onEndOfFile: (() -> Void)?

    let metalLayer = MPVMetalLayer()
    private(set) var mpv: OpaquePointer?
    private let queue = DispatchQueue(label: "openfuse.mpv", qos: .userInitiated)
    private var startAt: TimeInterval = 0
    private var didApplyStart = false
    private var pendingSubtitles: [(title: String, url: URL, language: String?)] = []
    private var didAddSubtitles = false
    private var didSignalEnd = false

    init() {
        metalLayer.contentsScale = UIScreen.main.nativeScale
        metalLayer.framebufferOnly = true
        metalLayer.backgroundColor = UIColor.black.cgColor
    }

    func start(url: URL, headers: [String: String], startAt: TimeInterval,
               externalSubtitles: [(title: String, url: URL, language: String?)] = []) {
        guard mpv == nil else { return }
        self.startAt = startAt
        self.pendingSubtitles = externalSubtitles
        debugLog("start url=\(url.lastPathComponent) headers=\(headers.keys.joined(separator: ",")) subs=\(externalSubtitles.count)")
        guard let handle = mpv_create() else {
            errorText = "无法创建 mpv 实例"
            return
        }
        mpv = handle
        setOption("vo", "gpu-next")
        setOption("gpu-api", "vulkan")
        setOption("gpu-context", "moltenvk")
        setOption("hwdec", "videotoolbox")
        setOption("keep-open", "yes")
        setOption("subs-match-os-language", "yes")
        setOption("subs-fallback", "yes")
        setOption("sub-scale-by-window", "no")
        setOption("sub-font-size", "46")
        if let resources = Bundle.main.resourceURL?.path {
            setOption("sub-fonts-dir", resources)
            debugLog("fonts dir=\(resources)")
        }
        setOption("sub-font", "Noto Sans CJK SC")
        setOption("sub-font-provider", "fontconfig")
        if !headers.isEmpty {
            let fields = headers.map { "\($0.key): \($0.value)" }.joined(separator: ",")
            setOption("http-header-fields", fields)
        }
        var layerBits = UInt64(UInt(bitPattern: Unmanaged.passUnretained(metalLayer).toOpaque()))
        mpv_set_option(mpv, "wid", MPV_FORMAT_INT64, &layerBits)
        mpv_request_log_messages(mpv, "warn")
        guard mpv_initialize(mpv) >= 0 else {
            errorText = "mpv 初始化失败"
            return
        }
        mpv_observe_property(mpv, 0, "time-pos", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "duration", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "track-list", MPV_FORMAT_NONE)
        mpv_observe_property(mpv, 0, "eof-reached", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "eof-reached", MPV_FORMAT_FLAG)
        mpv_set_wakeup_callback(mpv, { context in
            guard let context else { return }
            let engine = Unmanaged<MobileMPVEngine>.fromOpaque(context).takeUnretainedValue()
            engine.readEvents()
        }, Unmanaged.passUnretained(self).toOpaque())

        command("loadfile", [url.absoluteString, "replace"])
        setFlag("pause", false)
    }

    deinit {
        if let mpv {
            mpv_terminate_destroy(mpv)
        }
    }

    // MARK: - control

    /// Tears the mpv instance down and starts a new file (used by auto-advance).
    func reopen(url: URL, headers: [String: String], startAt: TimeInterval,
                externalSubtitles: [(title: String, url: URL, language: String?)] = []) {
        if let mpv {
            mpv_terminate_destroy(mpv)
            self.mpv = nil
        }
        isReady = false
        position = 0
        duration = 0
        isPaused = false
        subtitleTracks = []
        audioTracks = []
        selectedSubtitleID = nil
        selectedAudioID = nil
        didApplyStart = false
        didAddSubtitles = false
        didSignalEnd = false
        pendingSubtitles = []
        start(url: url, headers: headers, startAt: startAt, externalSubtitles: externalSubtitles)
    }

    func togglePause() { setFlag("pause", !isPaused) }
    func pause() { setFlag("pause", true) }
    func play() { setFlag("pause", false) }

    func seek(to seconds: TimeInterval) {
        command("seek", [String(format: "%.3f", seconds), "absolute"])
        position = seconds
    }

    func selectSubtitle(_ id: Int64?) {
        var value = id ?? -1
        mpv_set_property(mpv, "sid", MPV_FORMAT_INT64, &value)
        selectedSubtitleID = id
    }

    func selectAudio(_ id: Int64?) {
        var value = id ?? -1
        mpv_set_property(mpv, "aid", MPV_FORMAT_INT64, &value)
        selectedAudioID = id
    }

    private func logAudioParams() {
        guard let mpv else { return }
        func value(_ name: String) -> String {
            guard let cstr = mpv_get_property_string(mpv, name) else { return "-" }
            defer { mpv_free(cstr) }
            return String(cString: cstr)
        }
        debugLog("audio-codec=\(value("audio-codec-name")) params=\(value("audio-params")) out=\(value("audio-out-params")) ao=\(value("current-ao"))")
    }

    /// Sidecar ASS files discovered next to the WebDAV video are added as
    /// external tracks; 简体 is preferred, matching the Mac player.
    private func addExternalSubtitlesIfNeeded() {
        guard !didAddSubtitles, !pendingSubtitles.isEmpty else { return }
        didAddSubtitles = true
        debugLog("adding \(pendingSubtitles.count) external subtitles")
        for subtitle in pendingSubtitles {
            var args = [subtitle.url.absoluteString, "auto", subtitle.title]
            if let language = subtitle.language, !language.isEmpty { args.append(language) }
            command("sub-add", args)
            debugLog("sub-add \(subtitle.title) lang=\(subtitle.language ?? "-") -> \(subtitle.url.lastPathComponent)")
        }
        Task { @MainActor in
            for _ in 0..<10 {
                try? await Task.sleep(nanoseconds: 400_000_000)
                if let simplified = subtitleTracks.first(where: { ($0.language ?? "").lowercased().hasPrefix("zh-hans") })
                    ?? subtitleTracks.first(where: { ($0.language ?? "").lowercased().hasPrefix("zh") }) {
                    selectSubtitle(simplified.id)
                    return
                }
            }
        }
    }

    // MARK: - mpv plumbing

    private func debugLog(_ message: String) {
        guard ProcessInfo.processInfo.environment["OPENFUSE_MPV_LOG"] == "1" else { return }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("mpv-debug.log")
        let line = "\(Date().timeIntervalSince1970) \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); handle.write(Data(line.utf8)); try? handle.close()
        } else { try? Data(line.utf8).write(to: url) }
    }

    private func setOption(_ name: String, _ value: String) {
        guard let mpv else { return }
        _ = mpv_set_option_string(mpv, name, value)
    }

    private func setFlag(_ name: String, _ value: Bool) {
        guard let mpv else { return }
        var data: Int32 = value ? 1 : 0
        mpv_set_property(mpv, name, MPV_FORMAT_FLAG, &data)
    }

    private func command(_ command: String, _ args: [String]) {
        guard let mpv else { return }
        var strings: [String?] = [command] + args + [nil]
        var cargs = strings.map { $0.flatMap { UnsafePointer<CChar>(strdup($0)) } }
        defer { for pointer in cargs where pointer != nil { free(UnsafeMutablePointer(mutating: pointer!)) } }
        let status = mpv_command(mpv, &cargs)
        if status < 0 {
            debugLog("command \(command) failed: \(String(cString: mpv_error_string(status)))")
        }
    }

    private func readEvents() {
        queue.async { [weak self] in
            guard let self, let mpv = self.mpv else { return }
            while true {
                guard let event = mpv_wait_event(mpv, 0), event.pointee.event_id != MPV_EVENT_NONE else { break }
                switch event.pointee.event_id {
                case MPV_EVENT_PROPERTY_CHANGE:
                    let data = OpaquePointer(event.pointee.data)
                    guard let property = UnsafePointer<mpv_event_property>(data)?.pointee,
                          let namePointer = property.name else { continue }
                    let name = String(cString: namePointer)
                    self.handleProperty(name, property)
                case MPV_EVENT_FILE_LOADED:
                    Task { @MainActor in
                        self.isReady = true
                        self.addExternalSubtitlesIfNeeded()
                        self.logAudioParams()
                        if !self.didApplyStart, self.startAt > 1 {
                            self.didApplyStart = true
                            self.seek(to: self.startAt)
                        }
                        if let raw = ProcessInfo.processInfo.environment["OPENFUSE_TEST_MPV_SEEK"],
                           let seconds = Double(raw), self.position < seconds {
                            self.seek(to: seconds)
                        }
                    }
                case MPV_EVENT_END_FILE:
                    let reason = event.pointee.data.map { UnsafePointer<mpv_event_end_file>(OpaquePointer($0))?.pointee.reason }
                    Task { @MainActor in
                        self.isReady = false
                        if reason == MPV_END_FILE_REASON_EOF { self.onEndOfFile?() }
                    }
                case MPV_EVENT_LOG_MESSAGE:
                    if let message = UnsafeMutablePointer<mpv_event_log_message>(OpaquePointer(event.pointee.data)) {
                        let text = String(cString: message.pointee.text)
                        if ProcessInfo.processInfo.environment["OPENFUSE_MPV_LOG"] == "1" {
                            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("mpv.log")
                            if let handle = try? FileHandle(forWritingTo: url) {
                                handle.seekToEndOfFile(); handle.write(Data(text.utf8)); try? handle.close()
                            } else { try? Data(text.utf8).write(to: url) }
                        }
                        Task { @MainActor in
                            if self.errorText == nil, text.lowercased().contains("error") { self.errorText = text }
                        }
                    }
                default:
                    break
                }
            }
        }
    }

    private func handleProperty(_ name: String, _ property: mpv_event_property) {
        switch name {
        case "time-pos":
            guard property.format == MPV_FORMAT_DOUBLE, let data = property.data else { return }
            let value = data.assumingMemoryBound(to: Double.self).pointee
            Task { @MainActor in self.position = value }
        case "duration":
            guard property.format == MPV_FORMAT_DOUBLE, let data = property.data else { return }
            let value = data.assumingMemoryBound(to: Double.self).pointee
            Task { @MainActor in self.duration = value }
        case "pause":
            guard property.format == MPV_FORMAT_FLAG, let data = property.data else { return }
            let value = data.assumingMemoryBound(to: Int32.self).pointee != 0
            Task { @MainActor in self.isPaused = value }
        case "eof-reached":
            guard property.format == MPV_FORMAT_FLAG, let data = property.data else { return }
            let reached = data.assumingMemoryBound(to: Int32.self).pointee != 0
            if reached {
                Task { @MainActor in
                    guard !self.didSignalEnd else { return }
                    self.didSignalEnd = true
                    self.onEndOfFile?()
                }
            }
        case "track-list":
            refreshTracks()
        case "eof-reached":
            guard property.format == MPV_FORMAT_FLAG, let data = property.data else { return }
            let reached = data.assumingMemoryBound(to: Int32.self).pointee != 0
            if reached { Task { @MainActor in self.isReady = false } }
        default:
            break
        }
    }

    private func refreshTracks() {
        guard let mpv, let json = mpv_get_property_string(mpv, "track-list") else { return }
        defer { mpv_free(json) }
        struct TrackList: Decodable { let id: Int64; let type: String; let lang: String?; let title: String?; let external: Bool?; let selected: Bool? }
        guard let data = String(cString: json).data(using: .utf8),
              let tracks = try? JSONDecoder().decode([TrackList].self, from: data) else { return }
        let subtitles = tracks.filter { $0.type == "sub" }.map {
            MobileMPVTrack(id: $0.id, type: $0.type, language: $0.lang, title: $0.title, external: $0.external ?? false)
        }
        let audio = tracks.filter { $0.type == "audio" }.map {
            MobileMPVTrack(id: $0.id, type: $0.type, language: $0.lang, title: $0.title, external: $0.external ?? false)
        }
        let selectedSub = tracks.first { $0.type == "sub" && ($0.selected ?? false) }?.id
        let selectedAudio = tracks.first { $0.type == "audio" && ($0.selected ?? false) }?.id
        debugLog("tracks sub=\(subtitles.count) audio=\(audio.count) selSub=\(String(describing: selectedSub))")
        Task { @MainActor in
            self.subtitleTracks = subtitles
            self.audioTracks = audio
            self.selectedSubtitleID = selectedSub
            self.selectedAudioID = selectedAudio
        }
    }
}
