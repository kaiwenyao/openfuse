import AppKit
import Combine
import Foundation
import OpenFuseCore
import UniformTypeIdentifiers

enum AppRoute: Equatable {
    case home
    case player
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var route: AppRoute = .home
    @Published var recent: [PlaybackRecord] = []
    @Published var player: PlayerModel?
    @Published var statusMessage: String?

    let supportDirectory: URL
    let store: PlaybackStore

    init(supportDirectory: URL? = nil) {
        let directory = supportDirectory ?? Self.defaultSupportDirectory()
        self.supportDirectory = directory
        do {
            self.store = try PlaybackStore(directory: directory)
        } catch {
            fatalError("cannot open playback store: \(error)")
        }
        refreshRecent()
    }

    static func defaultSupportDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["OPENFUSE_SUPPORT_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("OpenFuse", isDirectory: true)
    }

    func refreshRecent() {
        recent = store.recentlyPlayed(limit: 24)
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        var types: [UTType] = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        for ext in ["mkv", "mka", "m4v", "ts", "m2ts", "webm", "avi", "flv", "wmv", "iso", "mpg", "mpeg"] {
            if let type = UTType(filenameExtension: ext) { types.append(type) }
        }
        panel.allowedContentTypes = types
        panel.message = "选择要播放的视频文件"
        panel.prompt = "打开"
        if panel.runModal() == .OK, let url = panel.url {
            open(url: url)
        }
    }

    func open(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            statusMessage = "文件不存在：\(url.lastPathComponent)"
            return
        }
        let fingerprint: MediaFingerprint
        do {
            fingerprint = try MediaFingerprint(url: url)
        } catch {
            statusMessage = "无法读取文件：\(error.localizedDescription)"
            return
        }
        if let current = player {
            current.stopAndClose()
        }
        let record = store.record(forPath: fingerprint.resumeKey)
        let startAt = record.flatMap { ResumePolicy.resumePosition(for: $0) } ?? 0
        let model = PlayerModel(url: url, fingerprint: fingerprint, startAt: startAt, store: store)
        model.onClose = { [weak self] in
            self?.player = nil
            self?.route = .home
            self?.refreshRecent()
        }
        model.onFinished = { [weak self] in
            self?.refreshRecent()
        }
        player = model
        route = .player
        model.start()
        refreshRecent()
    }

    func closePlayer() {
        player?.stopAndClose()
        player = nil
        route = .home
        refreshRecent()
    }

    func resume(_ record: PlaybackRecord) {
        open(url: record.url)
    }

    func removeRecent(_ record: PlaybackRecord) {
        store.remove(path: record.mediaPath)
        refreshRecent()
    }

    func saveForTermination() {
        player?.saveProgress()
    }

    func captureUI(to url: URL) {
        guard let window = NSApp.windows.first, let view = window.contentView else { return }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
            print("[OpenFuse] wrote UI capture to \(url.path)")
        }
    }

    func writeTestReport(to url: URL) {
        guard let player else { return }
        var report: [String: Any] = [
            "app": "OpenFuse",
            "engine": "libmpv",
            "mpv": player.engine.getPropertyString("mpv-version") ?? "unknown",
            "file": player.url.path,
            "duration": player.duration,
            "position": player.position,
            "paused": player.isPaused,
            "videoCodec": player.engine.snapshot.tracks.first(where: { $0.type == "video" }).map { track in
                [track.codec, track.profile].compactMap { $0 }.joined(separator: " / ")
            } ?? "",
            "videoDescription": player.engine.snapshot.tracks.first(where: { $0.type == "video" })?.codecDescription ?? "",
            "audioCodec": player.engine.getPropertyString("audio-codec-name") ?? "",
            "audioChannels": player.engine.getPropertyString("audio-params/channel-count") ?? "",
            "hwdecCurrent": player.engine.getPropertyString("hwdec-current") ?? "",
            "audioParams": player.engine.getPropertyString("audio-params") ?? "",
            "audioOutParams": player.engine.getPropertyString("audio-out-params") ?? "",
            "audioDevice": player.engine.getPropertyString("audio-device") ?? "",
            "currentAO": player.engine.getPropertyString("current-ao") ?? "",
            "currentVO": player.engine.getPropertyString("current-vo") ?? "",
            "isFullScreen": NSApp.keyWindow?.styleMask.contains(.fullScreen) ?? false,
            "windowFrame": NSStringFromRect(NSApp.keyWindow?.frame ?? .zero),
            "videoOutParams": player.engine.getPropertyString("video-out-params") ?? "",
            "selectedSubtitle": player.selectedSubtitleID ?? "off",
            "selectedAudio": player.selectedAudioID ?? "default",
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "arguments": CommandLine.arguments,
            "logs": Array(player.logs.suffix(40)),
        ]
        report["subtitles"] = player.subtitleTracks.map { track -> [String: Any] in
            [
                "id": track.id,
                "name": track.displayName,
                "language": track.language ?? "und",
                "format": track.format.rawValue,
                "source": track.source.rawValue,
                "engineID": track.engineID ?? -1,
            ]
        }
        report["audio"] = player.audioTracks.map { track -> [String: Any] in
            [
                "id": track.id,
                "name": track.displayName,
                "codec": track.codec ?? "",
                "channels": track.channels ?? 0,
                "label": track.technicalLabel,
                "engineID": track.engineID ?? -1,
            ]
        }
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
            print("[OpenFuse] wrote report to \(url.path)")
        }
    }
}

@MainActor
final class PlayerModel: ObservableObject {
    let url: URL
    let fingerprint: MediaFingerprint
    let engine: MPVEngine
    private let store: PlaybackStore
    private let initialPosition: Double

    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var isPaused = true
    @Published var subtitleTracks: [SubtitleTrack] = []
    @Published var audioTracks: [AudioTrack] = []
    @Published var selectedSubtitleID: String?
    @Published var selectedAudioID: String?
    @Published var showControls = true
    @Published var isScrubbing = false
    @Published var statusMessage: String?
    @Published var logs: [String] = []

    var onClose: (() -> Void)?
    var onFinished: (() -> Void)?

    private var catalog: [SubtitleTrack]
    private var didAddExternalSubtitles = false
    private var didApplyInitialSelection = false
    private var pendingSeek: Double?
    private var progressTimer: Timer?
    private var controlsTimer: Timer?
    private var hasFinished = false
    private var hasStarted = false
    private var lastMouseNote: TimeInterval = 0
    private var savedSubtitleID: String?
    private var savedAudioID: String?
    private var selectionWorkItem: DispatchWorkItem?
    private var selectionAttempts = 0

    init(url: URL, fingerprint: MediaFingerprint, startAt: Double, store: PlaybackStore) {
        self.url = url
        self.fingerprint = fingerprint
        self.initialPosition = startAt
        self.store = store
        self.catalog = SubtitleCatalog.discover(for: url)
        self.engine = MPVEngine()
        wireEngine()
        if let record = store.record(forPath: fingerprint.resumeKey) {
            savedAudioID = record.preferredAudioTrackID
            savedSubtitleID = record.preferredSubtitleTrackID
        }
    }

    var title: String {
        DisplayTitle.make(from: url)
    }

    var displayPosition: Double {
        min(max(position, 0), duration > 0 ? duration : position)
    }

    func start() {
        engine.onRenderContextReady = { [weak self] in
            self?.beginPlaybackIfReady()
        }
        if engine.hasRenderContext {
            beginPlaybackIfReady()
        }
    }

    private func beginPlaybackIfReady() {
        guard !hasStarted, engine.hasRenderContext else { return }
        hasStarted = true
        engine.onRenderContextReady = nil
        engine.load(url: url, startAt: initialPosition)
        engine.play()
        scheduleControlsHide()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.saveProgress() }
        }
    }

    private func wireEngine() {
        engine.onTimeChanged = { [weak self] value in
            guard let self, !self.isScrubbing else { return }
            self.position = value
        }
        engine.onDurationChanged = { [weak self] value in
            guard let self else { return }
            self.duration = value
            if let pending = self.pendingSeek, value > 0 {
                self.pendingSeek = nil
                self.engine.seek(to: pending)
            }
        }
        engine.onPauseChanged = { [weak self] paused in
            self?.isPaused = paused
        }
        engine.onTracksChanged = { [weak self] tracks in
            self?.applyTracks(tracks)
        }
        engine.onFileLoaded = { [weak self] in
            self?.handleFileLoaded()
        }
        engine.onEndFile = { [weak self] reason in
            guard let self else { return }
            if reason == "eof" {
                self.finishPlayback()
            }
        }
        engine.onLog = { [weak self] message in
            guard let self else { return }
            FileHandle.standardError.write("[mpv] \(message)\n".data(using: .utf8)!)
            self.logs.append(message)
            if self.logs.count > 400 { self.logs.removeFirst(self.logs.count - 400) }
        }
    }

    private func handleFileLoaded() {
        guard !didAddExternalSubtitles else { return }
        didAddExternalSubtitles = true
        for track in catalog where track.source == .external {
            if let url = track.url {
                engine.addSubtitle(url: url, select: false)
            }
        }
        engine.refreshTracks()
        if initialPosition > 0.2 {
            pendingSeek = initialPosition
            engine.seek(to: initialPosition)
        }
    }

    private func applyTracks(_ mpvTracks: [MPVTrackInfo]) {
        var subtitleResult: [SubtitleTrack] = []
        var usedMPVIDs = Set<Int64>()

        for var track in catalog {
            guard let trackURL = track.url else { continue }
            let mpv = mpvTracks.first {
                $0.type == "sub" && $0.externalFilename == trackURL.path
            }
            if let mpv {
                var updated = track
                updated.engineID = mpv.id
                updated.language = LanguageTag.normalizeISO(mpv.language) ?? track.language
                updated.displayName = SubtitleLabel.make(
                    language: updated.language,
                    format: updated.format,
                    forced: updated.isForced,
                    includeFormat: true
                )
                usedMPVIDs.insert(mpv.id)
                subtitleResult.append(updated)
                if mpv.isSelected { selectedSubtitleID = updated.id }
            } else {
                subtitleResult.append(track)
            }
        }

        for mpv in mpvTracks where mpv.type == "sub" {
            guard !usedMPVIDs.contains(mpv.id) else { continue }
            let format = SubtitleFormat(fileExtension: mpv.codec ?? "")
            let language = LanguageTag.normalizeISO(mpv.language)
            let label: String
            if let title = mpv.title, !title.isEmpty {
                label = title
            } else {
                label = SubtitleLabel.make(language: language, format: format, forced: false, includeFormat: true)
            }
            let track = SubtitleTrack(
                id: "mpv:\(mpv.id)",
                displayName: label,
                language: language,
                format: format,
                source: .embedded,
                engineID: mpv.id
            )
            subtitleResult.append(track)
            if mpv.isSelected { selectedSubtitleID = track.id }
        }
        subtitleTracks = subtitleResult

        var audioResult: [AudioTrack] = []
        for mpv in mpvTracks where mpv.type == "audio" {
            let track = AudioTrack(
                id: "mpv-audio:\(mpv.id)",
                displayName: audioLabel(mpv),
                language: LanguageTag.normalizeISO(mpv.language),
                codec: mpv.codec,
                channels: mpv.channels,
                isDefault: mpv.isDefault,
                engineID: mpv.id
            )
            audioResult.append(track)
            if mpv.isSelected { selectedAudioID = track.id }
        }
        audioTracks = audioResult

        if !didApplyInitialSelection {
            scheduleInitialSelection(after: 0.35)
        }
    }

    private func scheduleInitialSelection(after delay: Double) {
        guard !didApplyInitialSelection else { return }
        selectionWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.applyInitialSelectionIfReady()
        }
        selectionWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func applyInitialSelectionIfReady() {
        guard !didApplyInitialSelection else { return }
        let externalCatalog = catalog.filter { $0.source == .external }
        let loadedExternal = subtitleTracks.filter { $0.source == .external && $0.engineID != nil }
        if !externalCatalog.isEmpty, loadedExternal.count < externalCatalog.count, selectionAttempts < 6 {
            selectionAttempts += 1
            scheduleInitialSelection(after: 0.4)
            return
        }
        applyInitialSelection()
        didApplyInitialSelection = true
        selectionWorkItem?.cancel()
        selectionWorkItem = nil
    }

    private func applyInitialSelection() {
        if let savedAudio = savedAudioID,
           let match = audioTracks.first(where: { $0.id == savedAudio }), let engineID = match.engineID {
            engine.setAudioTrack(id: engineID)
            selectedAudioID = match.id
        }
        let selectable = subtitleTracks.filter { $0.engineID != nil }
        guard !selectable.isEmpty else { return }
        if let saved = savedSubtitleID, let match = selectable.first(where: { $0.id == saved }) {
            selectSubtitle(match)
            return
        }
        if let simplified = selectable.first(where: { $0.language == "zh-Hans" }) {
            selectSubtitle(simplified)
            return
        }
        if let anyChinese = selectable.first(where: { ($0.language ?? "").hasPrefix("zh") }) {
            selectSubtitle(anyChinese)
            return
        }
        if let embedded = selectable.first(where: { $0.source == .embedded }) {
            selectSubtitle(embedded)
        }
    }

    private func audioLabel(_ mpv: MPVTrackInfo) -> String {
        var pieces: [String] = []
        if let language = LanguageTag.normalizeISO(mpv.language) {
            pieces.append(LanguageTag.displayName(language))
        }
        if let title = mpv.title, !title.isEmpty {
            pieces.append(title)
        }
        if pieces.isEmpty {
            pieces.append("音轨 \(mpv.id)")
        }
        return pieces.joined(separator: " · ")
    }

    func togglePlayPause() {
        engine.togglePause()
        showControlsTemporarily()
    }

    func pause() {
        engine.pause()
    }

    func play() {
        engine.play()
    }

    func skip(_ delta: Double) {
        seek(to: displayPosition + delta)
    }

    func seek(to target: Double) {
        let clamped = max(0, min(duration > 0 ? duration - 0.25 : target, target))
        position = clamped
        engine.seek(to: clamped)
        hasFinished = false
        showControlsTemporarily()
    }

    func beginScrub() {
        isScrubbing = true
        showControlsTemporarily()
    }

    func endScrub(at target: Double) {
        isScrubbing = false
        seek(to: target)
    }

    func selectSubtitle(_ track: SubtitleTrack?) {
        guard let track else {
            selectedSubtitleID = nil
            savedSubtitleID = nil
            engine.setSubtitleTrack(id: nil)
            showControlsTemporarily()
            return
        }
        selectedSubtitleID = track.id
        savedSubtitleID = track.id
        if let engineID = track.engineID {
            engine.setSubtitleTrack(id: engineID)
        }
        showControlsTemporarily()
    }

    func selectAudio(_ track: AudioTrack) {
        selectedAudioID = track.id
        savedAudioID = track.id
        if let engineID = track.engineID {
            engine.setAudioTrack(id: engineID)
        }
        showControlsTemporarily()
    }

    func setAudioLayout(_ layout: String) {
        engine.setAudioChannels(layout)
    }

    func setSpeed(_ speed: Double) {
        engine.setSpeed(speed)
    }

    func saveProgress(finished: Bool? = nil) {
        guard duration > 0 else { return }
        let resolvedFinished = finished ?? (hasFinished || ResumePolicy.isFinished(position: position, duration: duration))
        store.update(
            fingerprint: fingerprint,
            duration: duration,
            position: position,
            displayTitle: title,
            audioTrackID: selectedAudioID,
            subtitleTrackID: selectedSubtitleID,
            finished: resolvedFinished
        )
    }

    private func finishPlayback() {
        hasFinished = true
        saveProgress(finished: true)
        onFinished?()
        showControls = true
    }

    func stopAndClose() {
        saveProgress()
        progressTimer?.invalidate()
        progressTimer = nil
        controlsTimer?.invalidate()
        controlsTimer = nil
        engine.pause()
        engine.shutdown()
        onClose?()
    }

    func freeze(at target: Double) {
        let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                if self.position >= target {
                    self.pause()
                    timer.invalidate()
                    self.showControls = true
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    func selectSubtitle(language tag: String, attempts: Int) {
        guard attempts > 0 else {
            statusMessage = "未找到语言为 \(tag) 的字幕轨"
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            if self.subtitleTracks.isEmpty {
                self.selectSubtitle(language: tag, attempts: attempts - 1)
                return
            }
            let match = self.subtitleTracks.first { track in
                guard let language = track.language else { return false }
                return language == tag || language.hasPrefix(tag + "-") || language.hasPrefix(tag)
            }
            if let match {
                self.selectSubtitle(match)
            } else {
                self.selectSubtitle(language: tag, attempts: attempts - 1)
            }
        }
    }

    func captureScreenshot(to path: URL) {
        engine.screenshot(to: path)
    }

    func showControlsTemporarily() {
        showControls = true
        scheduleControlsHide()
    }

    func noteMouseActivity() {
        let now = Date().timeIntervalSince1970
        guard now - lastMouseNote > 0.4 else { return }
        lastMouseNote = now
        if !showControls { showControls = true }
        scheduleControlsHide()
    }

    private func scheduleControlsHide() {
        controlsTimer?.invalidate()
        guard !isPaused else { return }
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 3.2, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isPaused, !self.isScrubbing else { return }
                self.showControls = false
            }
        }
    }

    func toggleFullScreen() {
        NSApp.keyWindow?.toggleFullScreen(nil)
    }
}

enum DisplayTitle {
    static func make(from url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent
        var title = base.replacingOccurrences(of: ".", with: " ")
        title = title.replacingOccurrences(of: "_", with: " ")
        let noise = ["2160p", "1080p", "720p", "WEB-DL", "WEBRip", "BluRay", "HEVC", "x265", "H265", "DDP5.1", "HDR"]
        for token in noise {
            title = title.replacingOccurrences(of: token, with: "", options: .caseInsensitive)
        }
        title = title.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? base : title
    }
}
