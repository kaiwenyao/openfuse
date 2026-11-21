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
    @State private var rightClickMonitor: Any?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            MPVSurface(engine: player.engine)
                // A new engine needs its own NSOpenGLView: SwiftUI would
                // otherwise reuse the old view (whose GL context belongs to the
                // stopped engine), leaving the new session without a render
                // context when the user switches videos mid-load.
                .id(ObjectIdentifier(player.engine))
                .ignoresSafeArea()

            if player.showControls {
                PlayerChrome(player: player)
                    .transition(.opacity)
            }

            if player.showFolderList {
                FolderListOverlay(player: player)
                    .transition(.opacity)
            }

            PlayerCacheHUD(player: player)
                .animation(.easeInOut(duration: 0.18), value: player.isBuffering)
                .animation(.easeInOut(duration: 0.18), value: player.isOpening)
                .animation(.easeInOut(duration: 0.18), value: player.isNetworkStalled)

            VStack {
                Spacer()
                PlayerVolumeHUD(player: player)
                    .padding(.bottom, 132)
                if let notice = player.subtitleDelayNotice {
                    Text(notice)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.72), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 1))
                        .padding(.bottom, 14)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeInOut(duration: 0.16), value: player.showVolumeHUD)

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
            installRightClickMonitor()
        }
        .onDisappear {
            removeKeyboardMonitor()
            removeHitDebugMonitor()
            removeRightClickMonitor()
        }
        .onContinuousHover { phase in
            if case .active = phase {
                player.noteMouseActivity()
            }
        }
        .sheet(isPresented: $player.showSubtitleDelayPrompt) {
            SubtitleDelaySheet(player: player)
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

    /// Right click (mouse or trackpad two-finger click) toggles play/pause
    /// anywhere in the player: video, letterbox, subtitle area, buffering HUD
    /// and the control bar. Swallowing the event also prevents SwiftUI/AppKit
    /// context menus from opening in the player.
    private func installRightClickMonitor() {
        guard rightClickMonitor == nil else { return }
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { event in
            if ProcessInfo.processInfo.environment["OPENFUSE_DEBUG_HITS"] == "1" {
                print("[right] down window=\(String(describing: event.window)) key=\(String(describing: NSApp.keyWindow)) same=\(event.window === NSApp.keyWindow) loc=\(event.locationInWindow)")
            }
            guard event.window === NSApp.keyWindow else { return event }
            if NSApp.keyWindow?.firstResponder is NSTextView { return event }
            player.togglePlayPause(userInitiated: true)
            return nil
        }
    }

    private func removeRightClickMonitor() {
        if let rightClickMonitor {
            NSEvent.removeMonitor(rightClickMonitor)
            self.rightClickMonitor = nil
        }
    }

    private func installKeyboardMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Standard macOS fullscreen shortcut, kept in addition to ⌘3.
            if event.keyCode == 3,
               event.modifierFlags.contains([.control, .command]) {
                player.toggleFullScreen()
                return nil
            }
            if event.modifierFlags.contains(.command) { return event }
            if event.window !== NSApp.keyWindow { return event }
            // Never steal typing (none in the player today, but keep it safe).
            if NSApp.keyWindow?.firstResponder is NSTextView { return event }
            switch event.keyCode {
            case 126, 125:
                // Bare ↑/↓ adjust volume; modified arrows keep their system
                // meaning (e.g. ⇧↑ selection, ⌥↑ scroll).
                guard event.modifierFlags.intersection([.option, .control, .shift]).isEmpty else {
                    return event
                }
                player.adjustVolume(by: event.keyCode == 126 ? 5 : -5)
                return nil
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
                if player.showFolderList {
                    player.showFolderList = false
                    return nil
                }
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
    @State private var showSubtitleMenu = false

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
                thumbnails: player.thumbnails,
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

                Button {
                    player.toggleFolderList()
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .help("同文件夹视频")
                .disabled(player.folderVideos.isEmpty)

                Button {
                    showSubtitleMenu.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "captions.bubble")
                        Text(selectedSubtitleName ?? "字幕")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .help("字幕与字幕偏移")
                .accessibilityLabel("字幕菜单")
                .popover(isPresented: $showSubtitleMenu, arrowEdge: .bottom) {
                    subtitleMenuContent
                }
                .onAppear {
                    guard ProcessInfo.processInfo.environment["OPENFUSE_OPEN_SUBTITLE_MENU"] == "1" else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        showSubtitleMenu = true
                    }
                }

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

                VolumeControl(player: player)

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

    private var subtitleMenuContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            SubtitleMenuRow(
                title: "关闭字幕",
                selected: player.selectedSubtitleID == nil,
                action: { player.selectSubtitle(nil) }
            )
            Divider().padding(.vertical, 3)
            ForEach(player.subtitleTracks) { track in
                SubtitleMenuRow(
                    title: track.displayName,
                    selected: player.selectedSubtitleID == track.id,
                    action: { player.selectSubtitle(track) }
                )
            }
            Divider().padding(.vertical, 3)
            Text("字幕偏移：\(player.subtitleDelaySummary)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            SubtitleMenuRow(
                title: "提前 0.1 秒",
                selected: false,
                disabled: player.selectedSubtitleID == nil,
                action: { player.adjustSubtitleDelay(by: -0.1) }
            )
            SubtitleMenuRow(
                title: "延后 0.1 秒",
                selected: false,
                disabled: player.selectedSubtitleID == nil,
                action: { player.adjustSubtitleDelay(by: 0.1) }
            )
            SubtitleMenuRow(
                title: "输入秒数…",
                selected: false,
                disabled: player.selectedSubtitleID == nil,
                action: { player.beginSubtitleDelayInput() }
            )
            SubtitleMenuRow(
                title: "重置为 0",
                selected: false,
                disabled: player.selectedSubtitleID == nil,
                action: { player.resetSubtitleDelay() }
            )
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .padding(10)
        .frame(width: 260)
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


private struct SubtitleMenuRow: View {
    let title: String
    let selected: Bool
    var disabled = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .foregroundStyle(disabled ? Theme.secondary.opacity(0.45) : Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                hovering && !disabled ? Theme.accent.opacity(0.14) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
        .onAppear {
            if ProcessInfo.processInfo.environment["OPENFUSE_HOVER_SUBTITLE_ROW"] == title {
                hovering = true
            }
        }
        .accessibilityLabel(title)
        .accessibilityValue(hovering ? "hovered" : "idle")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct SubtitleDelaySheet: View {
    @ObservedObject var player: PlayerModel
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("字幕时间偏移")
                .font(.system(size: 16, weight: .semibold))
            Text("正数让字幕延后，负数让字幕提前。当前：\(player.subtitleDelaySummary)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField("例如 1.5 或 -1", text: $player.subtitleDelayInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .focused($inputFocused)
                .accessibilityLabel("字幕偏移秒数")
                .onSubmit(apply)
            if let error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("应用", action: apply)
                    .keyboardShortcut(.defaultAction)
                    .disabled(player.selectedSubtitleID == nil)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear { inputFocused = true }
    }

    private func apply() {
        if player.submitSubtitleDelayInput() {
            dismiss()
        } else {
            error = "请输入数字，例如 1.5（延后）或 -1（提前）"
        }
    }
}


private struct FolderListOverlay: View {
    @ObservedObject var player: PlayerModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { player.showFolderList = false }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 14, weight: .semibold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("同文件夹视频")
                            .font(.system(size: 14, weight: .semibold))
                        Text(player.folderLabel.isEmpty ? "\(player.folderVideos.count) 个视频" : player.folderLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                    Button { player.showFolderList = false } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 26, height: 26)
                            .background(.white.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .foregroundStyle(.white)

                Divider().overlay(.white.opacity(0.12))

                if player.folderVideos.isEmpty {
                    Spacer()
                    Text("这个文件夹没有可播放的视频")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                    Spacer()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(player.folderVideos) { video in
                                    row(video)
                                        .id(video.id)
                                    Divider().overlay(.white.opacity(0.08))
                                }
                            }
                        }
                        .onAppear {
                            if let id = player.currentFolderVideoID {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                }
            }
            .frame(width: 470, height: 520)
            .background(.black.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
        }
        .transition(.opacity)
    }

    private func row(_ video: FolderVideo) -> some View {
        let isCurrent = video.id == player.currentFolderVideoID
        return Button {
            player.showFolderList = false
            player.onSelectFolderVideo?(video)
        } label: {
            HStack(spacing: 10) {
                if let thumbnail = video.thumbnailURL, let url = URL(string: thumbnail) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.10))
                    }
                    .frame(width: 64, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(alignment: .topLeading) {
                        if isCurrent {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.accent)
                                .padding(2)
                        }
                    }
                } else {
                    Image(systemName: isCurrent ? "checkmark.circle.fill" : "play.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isCurrent ? Theme.accent : .white.opacity(0.55))
                        .frame(width: 18)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(video.rowTitle)
                        .font(.system(size: 13, weight: isCurrent ? .semibold : .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(video.subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(isCurrent ? Theme.accent.opacity(0.12) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}
