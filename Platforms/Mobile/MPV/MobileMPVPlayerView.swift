import SwiftUI
import OpenFuseData

/// Player for sources AVPlayer cannot open (WebDAV MKV). Video and ASS
/// subtitles are rendered by libmpv, so styling, fonts and 简/繁 tracks behave
/// like the Mac player.
struct MobileMPVPlayerView: View {
    @EnvironmentObject private var model: MobileLibraryModel
    @Environment(\.dismiss) private var dismiss

    let item: MobilePlaybackItem
    @StateObject private var engine = MobileMPVEngine()
    @State private var activeItem: MobilePlaybackItem?
    @State private var didStart = false
    @State private var lastSaved: TimeInterval = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            MobileMPVSurface(engine: engine)
                .ignoresSafeArea()
            VStack {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text((activeItem ?? item).title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(subtitleLine)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .padding(10)
                            .background(.black.opacity(0.6), in: Circle())
                            .foregroundStyle(.white)
                    }
                }
                .padding(16)
                Spacer()
                controls
            }
        }
        .onAppear(perform: startIfNeeded)
        .onDisappear {
            engine.pause()
            save()
        }
        .onChange(of: engine.isReady) { _, ready in
            if !ready { return }
        }
    }

    private var subtitleLine: String {
        let name = engine.subtitleTracks.first(where: { $0.id == engine.selectedSubtitleID })?.displayName ?? "关闭字幕"
        let audio = engine.audioTracks.first(where: { $0.id == engine.selectedAudioID })?.displayName ?? "音轨"
        return "\(audio) · \(name)"
    }

    @ViewBuilder private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Text(Self.timecode(engine.position))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                Slider(
                    value: Binding(
                        get: { engine.duration > 0 ? min(engine.position, engine.duration) : 0 },
                        set: { engine.seek(to: $0) }
                    ),
                    in: 0...max(engine.duration, 0.1)
                )
                .tint(.accentColor)
                Text(Self.timecode(engine.duration))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
            }
            HStack(spacing: 18) {
                Button { engine.seek(to: max(0, engine.position - 10)) } label: {
                    Image(systemName: "gobackward.10").font(.system(size: 20))
                }
                Button { engine.togglePause() } label: {
                    Image(systemName: engine.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 22, weight: .bold))
                        .frame(width: 46, height: 46)
                        .background(.white.opacity(0.9), in: Circle())
                        .foregroundStyle(.black)
                }
                Button { engine.seek(to: engine.position + 10) } label: {
                    Image(systemName: "goforward.10").font(.system(size: 20))
                }
                Spacer()
                if !engine.subtitleTracks.isEmpty {
                    Menu {
                        Button("关闭字幕") { engine.selectSubtitle(nil) }
                        ForEach(engine.subtitleTracks) { track in
                            Button(track.displayName) { engine.selectSubtitle(track.id) }
                        }
                    } label: {
                        Label("字幕", systemImage: "captions.bubble")
                    }
                }
                if !engine.audioTracks.isEmpty {
                    Menu {
                        ForEach(engine.audioTracks) { track in
                            Button(track.displayName) { engine.selectAudio(track.id) }
                        }
                    } label: {
                        Label("音轨", systemImage: "speaker.wave.2")
                    }
                }
            }
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private static func timecode(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs)
                         : String(format: "%02d:%02d", minutes, secs)
    }

    private func startIfNeeded() {
        guard !didStart else { return }
        didStart = true
        engine.onEndOfFile = { advanceToNextEpisode() }
        play(item)
    }

    private func advanceToNextEpisode() {
        guard ProcessInfo.processInfo.environment["OPENFUSE_AUTOPLAY"] != "0" else { return }
        let finished = activeItem ?? item
        save()
        Task { @MainActor in
            guard let next = await model.nextEpisodeItem(after: finished) else { return }
            activeItem = next
            play(next)
        }
    }

    private func play(_ playback: MobilePlaybackItem) {
        var sidecars = playback.sidecarSubtitles.compactMap { track -> (String, URL, String?)? in
            guard let url = track.url else { return nil }
            return (track.displayName, url, track.language)
        }
        if let raw = ProcessInfo.processInfo.environment["OPENFUSE_TEST_MPV_SUB_INDEX"], let index = Int(raw),
           index > 0, index <= sidecars.count {
            sidecars = [sidecars[index - 1]]
        }
        engine.reopen(url: playback.url, headers: playback.httpHeaders,
                      startAt: playback.resumePosition ?? 0,
                      externalSubtitles: sidecars)
    }

    private func save() {
        guard engine.duration > 0 else { return }
        let playback = activeItem ?? item
        let finished = ResumePolicy.isFinished(position: engine.position, duration: engine.duration)
        model.recordProgress(item: playback, duration: engine.duration, position: engine.position, finished: finished)
    }
}
