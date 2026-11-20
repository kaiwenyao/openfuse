import AVKit
import CoreMedia
import OpenFuseData
import SwiftUI

struct MobilePlayerView: View {
    @EnvironmentObject private var model: MobileLibraryModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    let item: MobilePlaybackItem

    @State private var player: AVPlayer?
    @State private var resourceLoader: AuthenticatedAssetLoader?
    @State private var timeObserver: Any?
    @State private var lastPosition: TimeInterval = 0
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var errorText: String?
    @State private var audioGroup: AVMediaSelectionGroup?
    @State private var subtitleGroup: AVMediaSelectionGroup?
    @State private var audioOptions: [AVMediaSelectionOption] = []
    @State private var subtitleOptions: [AVMediaSelectionOption] = []
    @State private var audioLabels: [String] = []
    @State private var subtitleLabels: [String] = []
    @State private var selectedAudioLabel = "默认音轨"
    @State private var selectedSubtitleLabel = "关闭"
    @State private var sidecarTracks: [SubtitleTrack] = []
    @State private var sidecarLabels: [String] = []
    @State private var selectedSidecarIndex: Int?
    @State private var cues: [SubtitleCue] = []
    @State private var subtitleText = ""
    @State private var didPauseAtTarget = false
    private let ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView().tint(.white)
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .padding(10)
                    .background(.black.opacity(0.6), in: Circle())
                    .foregroundStyle(.white)
            }
            .padding(16)
            if !subtitleText.isEmpty {
                VStack {
                    Spacer()
                    Text(subtitleText)
                        .font(.system(size: 20, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 24)
                        .padding(.bottom, showsHUD ? 132 : 60)
                }
            }
            if let errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .padding()
                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 60)
            }
            if showsHUD {
                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        Text(String(format: "%.1f / %.1f s", currentTime, duration))
                            .font(.caption.monospaced())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.55), in: Capsule())
                        if !audioOptions.isEmpty {
                            Menu {
                                ForEach(audioOptions.indices, id: \.self) { index in
                                    Button(audioLabels[index]) { selectAudio(index) }
                                }
                            } label: {
                                Image(systemName: "waveform")
                                    .padding(7)
                                    .background(.black.opacity(0.55), in: Circle())
                                    .foregroundStyle(.white)
                            }
                        }
                        if !subtitleOptions.isEmpty && sidecarTracks.isEmpty {
                            Menu {
                                Button("关闭字幕") { selectSubtitle(nil) }
                                ForEach(subtitleOptions.indices, id: \.self) { index in
                                    Button(subtitleLabels[index]) { selectSubtitle(index) }
                                }
                            } label: {
                                Image(systemName: "captions.bubble")
                                    .padding(7)
                                    .background(.black.opacity(0.55), in: Circle())
                                    .foregroundStyle(.white)
                            }
                        }
                        if !sidecarTracks.isEmpty {
                            Menu {
                                Button("关闭字幕") { selectSidecar(nil) }
                                ForEach(sidecarTracks.indices, id: \.self) { index in
                                    Button(sidecarLabels[index]) { selectSidecar(index) }
                                }
                            } label: {
                                Image(systemName: "captions.bubble")
                                    .padding(7)
                                    .background(.black.opacity(0.55), in: Circle())
                                    .foregroundStyle(.white)
                            }
                        }
                        Spacer()
                    }
                    .padding(18)
                    HStack {
                        Text("音轨：\(selectedAudioLabel) · 字幕：\(selectedSubtitleLabel)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.85))
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
                }
            }

        }
        .onAppear { setupPlayer() }
        .onDisappear {
            saveProgress()
            player?.pause()
            if let timeObserver, let player {
                player.removeTimeObserver(timeObserver)
            }
            timeObserver = nil
            resourceLoader = nil
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { saveProgress() }
        }
        .onReceive(ticker) { _ in
            tick()
        }
    }

    private var showsHUD: Bool {
        ProcessInfo.processInfo.arguments.contains("--autoplay-sample")
            || ProcessInfo.processInfo.environment["OPENFUSE_AUTOPLAY"] == "1"
    }

    private func configureTracks(_ player: AVPlayer) {
        guard let asset = player.currentItem?.asset else { return }
        sidecarTracks = item.sidecarSubtitles
        sidecarLabels = sidecarTracks.map { "\($0.displayName)" }
        audioGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .audible)
        subtitleGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .legible)
        audioOptions = audioGroup?.options ?? []
        subtitleOptions = sidecarTracks.isEmpty
            ? (subtitleGroup?.options ?? []).filter { !$0.hasMediaCharacteristic(.containsOnlyForcedSubtitles) }
            : []
        let audioTracks = asset.tracks(withMediaType: .audio)
        audioLabels = audioOptions.enumerated().map { index, option in
            let codec = audioTracks.indices.contains(index) ? Self.audioCodec(audioTracks[index]) : option.displayName
            return "音轨 \(index + 1) · \(codec)"
        }
        subtitleLabels = subtitleOptions.enumerated().map { index, option in
            if subtitleOptions.count == 2 { return index == 0 ? "简体中文" : "繁體中文" }
            return option.displayName
        }
        if let group = audioGroup,
           let selected = player.currentItem?.currentMediaSelection.selectedMediaOption(in: group),
           let index = audioOptions.firstIndex(of: selected) {
            selectedAudioLabel = audioLabels[index]
        } else if !audioLabels.isEmpty {
            selectedAudioLabel = audioLabels[0]
        }
        if let group = subtitleGroup,
           let selected = player.currentItem?.currentMediaSelection.selectedMediaOption(in: group),
           let index = subtitleOptions.firstIndex(of: selected) {
            selectedSubtitleLabel = subtitleLabels[index]
        } else {
            selectedSubtitleLabel = "关闭"
        }
        let env = ProcessInfo.processInfo.environment
        if let raw = env["OPENFUSE_AUTOPLAY_AUDIO_INDEX"], let number = Int(raw), number > 0,
           audioOptions.indices.contains(number - 1) {
            selectAudio(number - 1)
        }
        if let raw = env["OPENFUSE_AUTOPLAY_SUBTITLE_INDEX"], let number = Int(raw) {
            if sidecarTracks.isEmpty {
                selectSubtitle(number == 0 ? nil : number - 1)
            } else {
                selectSidecar(number == 0 ? nil : number - 1)
            }
        }
    }

    private func selectSidecar(_ index: Int?) {
        if let index, sidecarTracks.indices.contains(index) {
            selectedSidecarIndex = index
            selectedSubtitleLabel = sidecarLabels[index]
            if let url = sidecarTracks[index].url {
                cues = (try? SubtitleParser.parse(url: url)) ?? []
            } else {
                cues = []
            }
            subtitleText = ""
        } else {
            selectedSidecarIndex = nil
            selectedSubtitleLabel = "关闭"
            cues = []
            subtitleText = ""
        }
    }

    private func tick() {
        guard let player else { return }
        let time = player.currentTime().seconds
        if time.isFinite {
            currentTime = max(0, time)
        }
        if let cue = cues.first(where: { time >= $0.start && time < $0.end }) {
            subtitleText = cue.text
        } else if !cues.isEmpty {
            subtitleText = ""
        }
        if !didPauseAtTarget,
           let raw = ProcessInfo.processInfo.environment["OPENFUSE_AUTOPLAY_PAUSE_AT"],
           let target = Double(raw), time >= target {
            didPauseAtTarget = true
            player.pause()
        }
    }

    private func selectAudio(_ index: Int) {
        guard let player, let group = audioGroup, audioOptions.indices.contains(index) else { return }
        player.currentItem?.select(audioOptions[index], in: group)
        selectedAudioLabel = audioLabels[index]
    }

    private func selectSubtitle(_ index: Int?) {
        guard let player, let group = subtitleGroup else { return }
        if let index, subtitleOptions.indices.contains(index) {
            player.currentItem?.select(subtitleOptions[index], in: group)
            selectedSubtitleLabel = subtitleLabels[index]
        } else {
            player.currentItem?.select(nil, in: group)
            selectedSubtitleLabel = "关闭"
        }
    }

    private static func audioCodec(_ track: AVAssetTrack) -> String {
        guard let description = track.formatDescriptions.first else { return "音频" }
        let format = description as! CMFormatDescription
        switch CMFormatDescriptionGetMediaSubType(format) {
        case kAudioFormatEnhancedAC3: return "E-AC-3 5.1"
        case kAudioFormatMPEG4AAC: return "AAC 立体声"
        case kAudioFormatAC3: return "AC-3"
        default: return "音频"
        }
    }

    private func setupPlayer() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            errorText = "音频会话失败：\(error.localizedDescription)"
        }

        let (player, loader) = model.makePlayer(for: item)
        self.player = player
        self.resourceLoader = loader
        player.appliesMediaSelectionCriteriaAutomatically = false
        configureTracks(player)
        duration = 0
        lastPosition = 0
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 600),
            queue: .main
        ) { time in
            lastPosition = max(0, time.seconds.isFinite ? time.seconds : 0)
            currentTime = lastPosition
            if let itemDuration = player.currentItem?.duration.seconds,
               itemDuration.isFinite, itemDuration > 0 {
                duration = itemDuration
            }
        }

        Task {
            let asset = player.currentItem?.asset ?? AVURLAsset(url: item.url)
            if let loaded = try? await asset.load(.duration) {
                duration = loaded.seconds
            }
            await waitUntilReady(player)
            if let raw = ProcessInfo.processInfo.environment["OPENFUSE_AUTOPLAY_SEEK"],
               let seconds = Double(raw) {
                await player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
                try? await Task.sleep(nanoseconds: 500_000_000)
                if ProcessInfo.processInfo.environment["OPENFUSE_AUTOPLAY_PAUSE"] == "1" {
                    player.pause()
                } else {
                    player.play()
                }
                tick()
            } else {
                if let resume = item.resumePosition, resume > 0 {
                    await player.seek(to: CMTime(seconds: resume, preferredTimescale: 600))
                }
                player.play()
            }
            if let raw = ProcessInfo.processInfo.environment["OPENFUSE_AUTOPLAY_SUBTITLE_INDEX"],
               let number = Int(raw) {
                if sidecarTracks.isEmpty {
                    selectSubtitle(number == 0 ? nil : number - 1)
                } else {
                    selectSidecar(number == 0 ? nil : number - 1)
                }
            }
            if let raw = ProcessInfo.processInfo.environment["OPENFUSE_AUTOPLAY_STOP_AFTER"],
               let seconds = Double(raw), seconds > 0 {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                saveProgress()
                dismiss()
            }
        }
    }

    private func waitUntilReady(_ player: AVPlayer) async {
        for _ in 0..<40 {
            if player.currentItem?.status == .readyToPlay { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func saveProgress() {
        guard let player else { return }
        let position = player.currentTime().seconds
        guard position.isFinite else { return }
        let currentDuration = duration > 0 ? duration : (player.currentItem?.duration.seconds ?? 0)
        guard currentDuration.isFinite, currentDuration > 0 else { return }
        let finished = ResumePolicy.isFinished(position: position, duration: currentDuration)
        model.recordProgress(
            item: item,
            duration: currentDuration,
            position: finished ? 0 : position,
            finished: finished
        )
    }
}
