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
    @State private var scrubValue: Double?
    @State private var keyMonitor: Any?
    @State private var showLog = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            MPVSurface(engine: player.engine)
                .ignoresSafeArea()

            if player.showControls {
                controls
                    .transition(.opacity)
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
        }
        .animation(.easeInOut(duration: 0.22), value: player.showControls)
        .onAppear { installKeyboardMonitor() }
        .onDisappear { removeKeyboardMonitor() }
        .onContinuousHover { phase in
            if case .active = phase {
                player.noteMouseActivity()
            }
        }
        .sheet(isPresented: $showLog) {
            logSheet
        }
    }

    private var controls: some View {
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
                    .background(.black.opacity(0.35), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("返回首页（保存播放位置）")

            VStack(alignment: .leading, spacing: 3) {
                Text(player.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("本地文件")
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
                    .background(.black.opacity(0.35), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("播放日志")
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
    }

    private var bottomBar: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Text(Timecode.short(displayedPosition))
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 62, alignment: .trailing)

                Slider(
                    value: Binding(
                        get: { scrubValue ?? displayedPosition },
                        set: { scrubValue = $0 }
                    ),
                    in: 0...max(player.duration, 0.1),
                    onEditingChanged: { editing in
                        if editing {
                            player.beginScrub()
                        } else {
                            let target = scrubValue ?? displayedPosition
                            player.endScrub(at: target)
                            scrubValue = nil
                        }
                    }
                )
                .tint(Theme.accent)

                Text(player.duration > 0 ? Timecode.short(player.duration) : "--:--")
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 62, alignment: .leading)
            }
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
                    }
                } label: {
                    Label(selectedAudioName ?? "音轨", systemImage: "speaker.wave.2")
                        .font(.system(size: 12.5, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Menu {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                        Button(String(format: "%.2fx", speed)) {
                            player.setSpeed(speed)
                        }
                    }
                } label: {
                    Text("1.0x")
                        .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

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

    private var displayedPosition: Double {
        scrubValue ?? player.displayPosition
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
