import AppKit
import OpenFuseCore
import SwiftUI

struct MPVSurface: NSViewRepresentable {
    let engine: MPVEngine

    func makeNSView(context: Context) -> MPVGLView {
        guard let view = MPVGLView(engine: engine) else {
            fatalError("OpenGL pixel format unavailable")
        }
        return view
    }

    func updateNSView(_ nsView: MPVGLView, context: Context) {}
}

struct PlayerView: View {
    @ObservedObject var player: PlayerModel
    @State private var keyMonitor: Any?
    @State private var hitDebugMonitor: Any?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            MPVSurface(engine: player.engine)
                .ignoresSafeArea()

            if player.showControls {
                PlayerChrome(player: player)
                    .transition(.opacity)
            }

            if player.isBuffering {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small).tint(.white)
                        Text("缓冲中…")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.7), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(.bottom, 120)
                }
                .allowsHitTesting(false)
            }

            if let status = player.statusMessage {
                VStack {
                    Spacer()
                    Text(status)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.7), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(.bottom, 120)
                }
                .allowsHitTesting(false)
            }

            // Keeps the window in darkAqua while the player is mounted so the
            // AppKit-drawn menu labels stay white on the black surface. Without
            // it the subtitle / audio / speed menus are invisible in the
            // default light theme.
            PlayerChromeHost()
                .frame(width: 1, height: 1)
                .opacity(0.001)
                .allowsHitTesting(false)
        }
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .tint(.white)
        .animation(.easeInOut(duration: 0.22), value: player.showControls)
        .onAppear {
            installKeyboardMonitor()
            installHitDebugMonitor()
        }
        .onDisappear {
            removeKeyboardMonitor()
            removeHitDebugMonitor()
        }
        .onContinuousHover { phase in
            if case .active = phase {
                player.noteMouseActivity()
            }
        }
    }

    /// `OPENFUSE_DEBUG_HITS=1` logs every mouse-down that reaches the player
    /// plus the AppKit view that would receive it. Used to work out why the
    /// in-player control bar ignored synthetic clicks during acceptance.
    private func installHitDebugMonitor() {
        guard ProcessInfo.processInfo.environment["OPENFUSE_DEBUG_HITS"] == "1", hitDebugMonitor == nil else { return }
        hitDebugMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
            let point = event.locationInWindow
            let window = event.window
            let content = window?.contentView
            let hit = content?.hitTest(point)
            let describeHit = hit.map { "\(type(of: $0)) frame=\($0.frame)" } ?? "nil"
            let line = "down window=\(window?.title ?? "?") point=\(point) contentBounds=\(content?.bounds ?? .zero) hit=\(describeHit)\n"
            PlayerView.appendHitLog(line)
            return event
        }
    }

    private func removeHitDebugMonitor() {
        if let hitDebugMonitor {
            NSEvent.removeMonitor(hitDebugMonitor)
            self.hitDebugMonitor = nil
        }
    }

    private static func appendHitLog(_ line: String) {
        let url = AppModel.shared.acceptanceDirectory().appendingPathComponent("hits.log")
        let data = Data(line.utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    private func installKeyboardMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command) { return event }
            switch event.keyCode {
            case 49:
                player.togglePlayPause()
                return nil
            case 123:
                player.skip(-10)
                return nil
            case 124:
                player.skip(10)
                return nil
            case 53:
                if NSApp.keyWindow?.styleMask.contains(.fullScreen) == true {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                } else {
                    player.stopAndClose()
                }
                return nil
            case 3:
                player.toggleFullScreen()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyboardMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

/// Control overlay. Split out of `PlayerView` so the 10 Hz playhead updates
/// only invalidate the scrubber (`PlaybackClock`) instead of this whole
/// hierarchy — re-laying out three `Menu`s and the AirPlay picker 20 times a
/// second was one half of the stutter.
struct PlayerChrome: View {
    @ObservedObject var player: PlayerModel
    @State private var scrubValue: Double?
    @State private var showLog = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            bottomBar
        }
        .background {
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 150)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.82)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 240)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .sheet(isPresented: $showLog) {
            logSheet
        }
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Button {
                if NSApp.keyWindow?.styleMask.contains(.fullScreen) == true {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        player.stopAndClose()
                    }
                } else {
                    player.stopAndClose()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 34, height: 34)
                    .background(.black.opacity(0.45), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("返回首页（保存播放位置）")

            VStack(alignment: .leading, spacing: 3) {
                Text(player.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(player.item.sourceName ?? "本地文件")
                    Text("·")
                    Text(player.audioTracks.first?.technicalLabel ?? "音频")
                    if let subtitle = selectedSubtitleName {
                        Text("·")
                        Text(subtitle)
                    }
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
            Button {
                showLog = true
            } label: {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(.black.opacity(0.45), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("播放日志")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 22)
        .padding(.top, 18)
    }

    private var bottomBar: some View {
        VStack(spacing: 14) {
            PlayerTimeRow(
                clock: player.clock,
                duration: player.duration,
                dragValue: $scrubValue,
                onScrubBegan: { player.beginScrub() },
                onScrubEnded: { target in
                    player.endScrub(at: target)
                    scrubValue = nil
                }
            )
            .padding(.horizontal, 24)

            HStack(spacing: 20) {
                Button { player.skip(-10) } label: {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 20, weight: .medium))
                }
                .buttonStyle(.plain)

                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 22, weight: .bold))
                        .frame(width: 50, height: 50)
                        .background(.white.opacity(0.92), in: Circle())
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)

                Button { player.skip(10) } label: {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 20, weight: .medium))
                }
                .buttonStyle(.plain)

                Spacer()

                Menu {
                    Button {
                        player.selectSubtitle(nil)
                    } label: {
                        if player.selectedSubtitleID == nil {
                            Label("关闭字幕", systemImage: "checkmark")
                        } else {
                            Text("关闭字幕")
                        }
                    }
                    Divider()
                    ForEach(player.subtitleTracks) { track in
                        Button {
                            player.selectSubtitle(track)
                        } label: {
                            if player.selectedSubtitleID == track.id {
                                Label(track.displayName, systemImage: "checkmark")
                            } else {
                                Text(track.displayName)
                            }
                        }
                    }
                } label: {
                    Label(selectedSubtitleName ?? "字幕", systemImage: "captions.bubble")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Menu {
                    ForEach(player.audioTracks) { track in
                        Button {
                            player.selectAudio(track)
                        } label: {
                            if player.selectedAudioID == track.id {
                                Label("\(track.displayName) · \(track.technicalLabel)", systemImage: "checkmark")
                            } else {
                                Text("\(track.displayName) · \(track.technicalLabel)")
                            }
                        }
                    }
                    Divider()
                    Menu("音频输出") {
                        Button("自动（立体声下混）") { player.setAudioLayout("auto-safe") }
                        Button("5.1 环绕") { player.setAudioLayout("5.1") }
                        Button("直通") { player.setAudioLayout("auto") }
                        Divider()
                        Button {
                            player.selectAudioDevice("auto")
                        } label: {
                            if player.selectedAudioDeviceID == "auto" {
                                Label("自动选择设备", systemImage: "checkmark")
                            } else {
                                Text("自动选择设备")
                            }
                        }
                        ForEach(player.audioDevices) { device in
                            Button {
                                player.selectAudioDevice(device.id)
                            } label: {
                                if player.selectedAudioDeviceID == device.id {
                                    Label("\(device.name)（\(device.outputChannels)ch）", systemImage: "checkmark")
                                } else {
                                    Text("\(device.name)（\(device.outputChannels)ch）")
                                }
                            }
                        }
                    }
                } label: {
                    Label(selectedAudioName ?? "音轨", systemImage: "speaker.wave.2")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Menu {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                        Button {
                            player.setSpeed(speed)
                        } label: {
                            if abs(player.speed - speed) < 0.001 {
                                Label(String(format: "%.2fx", speed), systemImage: "checkmark")
                            } else {
                                Text(String(format: "%.2fx", speed))
                            }
                        }
                    }
                } label: {
                    Text(String(format: "%.2fx", player.speed))
                        .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                AirPlayRoutePicker()
                    .frame(width: 24, height: 24)
                    .help("AirPlay 投屏")

                Button { player.toggleFullScreen() } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("全屏 (F)")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 26)
            .padding(.bottom, 22)
        }
    }

    private var selectedSubtitleName: String? {
        guard let id = player.selectedSubtitleID else { return nil }
        return player.subtitleTracks.first(where: { $0.id == id })?.displayName
    }

    private var selectedAudioName: String? {
        guard let id = player.selectedAudioID else { return nil }
        return player.audioTracks.first(where: { $0.id == id })?.displayName
    }

    private var logSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("播放会话")
                    .font(.headline)
                Spacer()
                Button("关闭") { showLog = false }
            }
            ScrollView {
                Text(player.logs.suffix(120).joined(separator: "\n"))
                    .font(.system(size: 10.5, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(width: 720, height: 420)
        .background(Theme.background)
    }
}
