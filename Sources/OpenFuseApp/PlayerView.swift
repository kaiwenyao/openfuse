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
                print("[right] down window=\(String(describing: event.window)) key=\(String(describing: NSApp.keyWindow)) same=\(event.window === NSApp.keyWindow) loc=\(event.locationInWindow) target=\(AppModel.shared.player?.url.lastPathComponent ?? "-")")
            }
            guard event.window === NSApp.keyWindow else { return event }
            if NSApp.keyWindow?.firstResponder is NSTextView { return event }
            // 换集 replaces `AppModel.player` with a fresh `PlayerModel` while
            // the route stays `.player`, so `PlayerView` keeps its identity,
            // its `@State` and these installed monitors (`onAppear` does not
            // run again, and a SwiftUI `onChange` action still captures the
            // old view value). Capturing `player` here would therefore keep
            // toggling the first — already stopped — engine. Resolve the episode
            // on screen when the event arrives instead.
            let model = AppModel.shared
            guard model.route == .player, let player = model.player else { return event }
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
            // Same late binding as the right-click monitor: every shortcut
            // (space, ↑/↓, ←/→, Esc, ⌘3) must reach the episode playing now,
            // not the one that installed this monitor.
            let model = AppModel.shared
            guard model.route == .player, let player = model.player else { return event }
            if ProcessInfo.processInfo.environment["OPENFUSE_DEBUG_HITS"] == "1", event.keyCode == 49 {
                print("[key] space target=\(player.url.lastPathComponent)")
            }
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
            // Keyboard focus/use keeps the floating panel on screen; the
            // normal idle fade-out is re-armed after the key is handled.
            if !event.modifierFlags.contains(.command) {
                player.noteKeyboardActivity()
            }
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
/// hierarchy.
///
/// The chrome is a compact floating panel in the QuickTime style: a two-row
/// panel near the top centre of the video, draggable by its blank surface,
/// with the title bar reduced to the work name and season/episode. It only
/// hit-tests the controls it actually draws; the rest of the video canvas
/// keeps receiving interactions.
struct PlayerChrome: View {
    @ObservedObject var player: PlayerModel
    @State private var scrubValue: Double?
    @State private var showInfo = false
    @State private var showSubtitleMenu = false
    @State private var panelOffset: CGSize = .zero
    @State private var panelSize: CGSize = .zero
    @State private var draggingPanel = false
    @State private var dragStartOffset: CGSize = .zero
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { proxy in
            let container = proxy.size
            let width = FloatingPanelMath.panelWidth(containerWidth: container.width)
            let compact = width < 430
            let roomy = width >= 520
            let panelHeight = panelSize.height > 0
                ? panelSize.height
                : FloatingPanelMath.panelHeight(compact: compact)
            let layoutSize = CGSize(width: width, height: panelHeight)
            let clampedOffset = FloatingPanelMath.clampedOffset(
                offset: panelOffset,
                panelSize: layoutSize,
                containerSize: container
            )
            let base = FloatingPanelMath.baseOrigin(
                containerSize: container,
                panelSize: layoutSize
            )
            let panelOrigin = CGPoint(x: base.x + clampedOffset.width, y: base.y + clampedOffset.height)
            let previewBelow = FloatingPanelMath.previewOpensDownward(panelOriginY: panelOrigin.y)

            ZStack(alignment: .top) {
                topBar(compact: compact)
                    .frame(maxWidth: 560)
                    .padding(.horizontal, compact ? 8 : 18)
                    .padding(.top, compact ? 8 : 14)

                floatingPanel(
                    width: width,
                    containerSize: container,
                    compact: compact,
                    roomy: roomy,
                    previewBelow: previewBelow
                )
                    .frame(width: width)
                    .background(
                        GeometryReader { panelProxy in
                            Color.clear.preference(key: PanelSizeKey.self, value: panelProxy.size)
                        }
                    )
                    .onPreferenceChange(PanelSizeKey.self) { size in
                        if abs(size.height - panelSize.height) > 0.5 || abs(size.width - panelSize.width) > 0.5 {
                            panelSize = size
                        }
                    }
                    .offset(x: clampedOffset.width, y: panelOrigin.y)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onChange(of: panelOrigin) { _, newValue in
                player.recordPanelLayout(
                    origin: newValue,
                    size: CGSize(width: width, height: panelSize.height)
                )
            }
            .onChange(of: panelSize) { _, newSize in
                let height = newSize.height > 0 ? newSize.height : FloatingPanelMath.panelHeight(compact: compact)
                player.recordPanelLayout(
                    origin: CGPoint(x: base.x + clampedOffset.width, y: base.y + clampedOffset.height),
                    size: CGSize(width: width, height: height),
                    containerSize: container
                )
            }
            .onAppear {
                if panelSize.height <= 0 {
                    panelSize = CGSize(width: width, height: FloatingPanelMath.panelHeight(compact: compact))
                }
                player.recordPanelLayout(
                    origin: CGPoint(x: base.x + clampedOffset.width, y: base.y + clampedOffset.height),
                    size: CGSize(width: width, height: panelHeight),
                    containerSize: container
                )
            }
            .onChange(of: container) { _, newSize in
                let newWidth = FloatingPanelMath.panelWidth(containerWidth: newSize.width)
                let newHeight = panelSize.height > 0
                    ? panelSize.height
                    : FloatingPanelMath.panelHeight(compact: newWidth < 430)
                let newPanelSize = CGSize(width: newWidth, height: newHeight)
                let newOffset = FloatingPanelMath.clampedOffset(
                    offset: panelOffset,
                    panelSize: newPanelSize,
                    containerSize: newSize
                )
                panelOffset = newOffset
                let newBase = FloatingPanelMath.baseOrigin(
                    containerSize: newSize,
                    panelSize: newPanelSize
                )
                player.recordPanelLayout(
                    origin: CGPoint(x: newBase.x + newOffset.width, y: newBase.y + newOffset.height),
                    size: newPanelSize,
                    containerSize: newSize
                )
            }
        }
        .sheet(isPresented: $showInfo) {
            PlaybackInfoSheet(player: player)
        }
        .onChange(of: showInfo) { _, open in
            player.setChromeHold("playback-info", open)
        }
        .onChange(of: showSubtitleMenu) { _, open in
            player.setChromeHold("subtitle-popover", open)
        }
        .onChange(of: player.showSubtitleDelayPrompt) { _, open in
            player.setChromeHold("subtitle-offset-sheet", open)
        }
        .background {
            // Keyboard focus inside the panel (Full Keyboard Access / Tab)
            // keeps the controls on screen; the model releases the hold when
            // the first responder leaves.
            ChromeFocusMonitor { focused in
                player.setChromeHold("keyboard-focus", focused)
            }
            .allowsHitTesting(false)
        }
        .onDisappear {
            player.setChromeHold("panel-hover", false)
            player.setChromeHold("panel-drag", false)
            player.setChromeHold("titlebar-hover", false)
            player.setChromeHold("subtitle-popover", false)
            player.setChromeHold("playback-info", false)
            player.setChromeHold("subtitle-offset-sheet", false)
            player.setChromeHold("keyboard-focus", false)
        }
        .onAppear {
            if let raw = ProcessInfo.processInfo.environment["OPENFUSE_SUBTITLE_MENU_AFTER"],
               let delay = Double(raw) {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    showSubtitleMenu = true
                }
            }
            if let raw = ProcessInfo.processInfo.environment["OPENFUSE_SUBTITLE_MENU_CLOSE_AFTER"],
               let delay = Double(raw) {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    showSubtitleMenu = false
                }
            }
            if let raw = ProcessInfo.processInfo.environment["OPENFUSE_SUBTITLE_OFFSET_AFTER"],
               let delay = Double(raw),
               let value = ProcessInfo.processInfo.environment["OPENFUSE_SUBTITLE_OFFSET_VALUE"].flatMap(Double.init) {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    player.setSubtitleDelay(value)
                }
            }
            guard let raw = ProcessInfo.processInfo.environment["OPENFUSE_CLICK_SUBTITLE_AT"] else { return }
            let values = raw.split(separator: ",").compactMap { Double($0) }
            guard values.count >= 3 else { return }
            let x = values[0], y = values[1], width = values[2]
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                for fraction in [0.03, 0.5, 0.97] {
                    let point = CGPoint(x: x + width * fraction, y: y)
                    let source = CGEventSource(stateID: .hidSystemState)
                    let move = CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                                       mouseCursorPosition: point, mouseButton: .left)
                    let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                                       mouseCursorPosition: point, mouseButton: .left)
                    let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                                     mouseCursorPosition: point, mouseButton: .left)
                    down?.setIntegerValueField(.mouseEventClickState, value: 1)
                    up?.setIntegerValueField(.mouseEventClickState, value: 1)
                    move?.post(tap: .cghidEventTap)
                    down?.post(tap: .cghidEventTap)
                    up?.post(tap: .cghidEventTap)
                }
            }
        }
    }

    // MARK: - Title bar

    private func topBar(compact: Bool) -> some View {
        HStack(spacing: 10) {
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
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.10), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("返回来源（保存播放位置）")
            .accessibilityLabel("返回来源")

            VStack(alignment: .leading, spacing: 1) {
                Text(player.heading.title)
                    .font(.system(size: compact ? 12 : 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .shadow(color: .black.opacity(0.65), radius: 2, y: 1)
                if let detail = player.heading.detail {
                    Text(detail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.65), radius: 2, y: 1)
                }
            }

            Spacer(minLength: 6)

            Button {
                player.showControlsTemporarily()
                showInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.10), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("播放信息")
            .accessibilityLabel("播放信息")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background {
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(.black.opacity(0.52))
            }
        }
        .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 0.8))
        .onHover { player.setChromeHold("titlebar-hover", $0) }
    }

    // MARK: - Floating panel

    private func floatingPanel(
        width: CGFloat,
        containerSize: CGSize,
        compact: Bool,
        roomy: Bool,
        previewBelow: Bool
    ) -> some View {
        VStack(spacing: compact ? 6 : 8) {
            firstRow(compact: compact, roomy: roomy, previewBelow: previewBelow)
            PlayerTimeRow(
                clock: player.clock,
                duration: player.duration,
                thumbnails: player.thumbnails,
                dragValue: $scrubValue,
                previewBelow: previewBelow,
                compact: compact,
                onScrubBegan: {
                    player.beginScrub()
                    player.setChromeHold("scrubber", true)
                },
                onScrubEnded: { target in
                    player.endScrub(at: target)
                    player.setChromeHold("scrubber", false)
                    scrubValue = nil
                }
            )
        }
        .padding(.horizontal, compact ? 10 : 14)
        .padding(.top, compact ? 8 : 11)
        .padding(.bottom, compact ? 8 : 10)
        .background {
            PlayerPanelSurface(
                cornerRadius: compact ? 15 : 18,
                reduceTransparency: reduceTransparency || ProcessInfo.processInfo.environment["OPENFUSE_REDUCE_TRANSPARENCY"] == "1"
            )
            .contentShape(RoundedRectangle(cornerRadius: compact ? 15 : 18, style: .continuous))
        }
        .overlay(alignment: .top) {
            // Drag only by the blank strip above the transport row. Putting the
            // gesture on the whole panel background also fired while dragging
            // the volume slider or the scrubber, moving the panel under the
            // cursor.
            ZStack(alignment: .top) {
                Color.clear
                Capsule()
                    .fill(.white.opacity(0.16))
                    .frame(width: 28, height: 3)
                    .padding(.top, 3.5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 10)
            .contentShape(Rectangle())
            .gesture(panelDragGesture(containerSize: containerSize))
        }
        .onHover { inside in
            player.setChromeHold("panel-hover", inside)
            if inside { player.showControlsTemporarily() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("播放控制面板")
    }

    private func panelDragGesture(containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                if !draggingPanel {
                    draggingPanel = true
                    dragStartOffset = FloatingPanelMath.clampedOffset(
                        offset: panelOffset,
                        panelSize: panelSize,
                        containerSize: containerSize
                    )
                    player.setChromeHold("panel-drag", true)
                    player.showControlsTemporarily()
                }
                let proposed = CGSize(
                    width: dragStartOffset.width + value.translation.width,
                    height: dragStartOffset.height + value.translation.height
                )
                panelOffset = FloatingPanelMath.clampedOffset(
                    offset: proposed,
                    panelSize: panelSize,
                    containerSize: containerSize
                )
            }
            .onEnded { _ in
                draggingPanel = false
                player.setChromeHold("panel-drag", false)
                player.showControlsTemporarily()
            }
    }

    private func firstRow(compact: Bool, roomy: Bool, previewBelow: Bool) -> some View {
        ZStack {
            centerTransport(compact: compact)
            if compact {
                HStack(spacing: 8) {
                    subtitleButton(compact: true, previewBelow: previewBelow)
                    Spacer(minLength: 0)
                    moreMenu(compact: true, previewBelow: previewBelow)
                }
            } else {
                HStack(spacing: 0) {
                    VolumeControl(player: player, compact: !roomy)
                    Spacer(minLength: 6)
                    HStack(spacing: 8) {
                        Button { player.toggleFolderList() } label: {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.system(size: 14, weight: .medium))
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("同文件夹选集")
                        .accessibilityLabel("同文件夹选集")
                        .disabled(player.folderVideos.isEmpty)
                        subtitleButton(compact: false, previewBelow: previewBelow)
                        moreMenu(compact: false, previewBelow: previewBelow)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .frame(height: compact ? 38 : 42)
    }

    private func centerTransport(compact: Bool) -> some View {
        HStack(spacing: compact ? 10 : 14) {
            Button { player.skip(-10) } label: {
                Image(systemName: "gobackward.10")
                    .font(.system(size: compact ? 15 : 17, weight: .medium))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("快退 10 秒")
            .accessibilityLabel("快退 10 秒")

            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: compact ? 15 : 17, weight: .bold))
                    .frame(width: compact ? 38 : 42, height: compact ? 38 : 42)
                    .background(.white.opacity(0.94), in: Circle())
                    .foregroundStyle(.black)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(player.isPaused ? "播放" : "暂停")
            .accessibilityLabel(player.isPaused ? "播放" : "暂停")

            Button { player.skip(10) } label: {
                Image(systemName: "goforward.10")
                    .font(.system(size: compact ? 15 : 17, weight: .medium))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("快进 10 秒")
            .accessibilityLabel("快进 10 秒")
        }
    }

    private func subtitleButton(compact: Bool, previewBelow: Bool) -> some View {
        Button {
            player.showControlsTemporarily()
            showSubtitleMenu.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "captions.bubble")
                    .font(.system(size: 12.5, weight: .semibold))
                Text(subtitleButtonLabel ?? "字幕")
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .opacity(compact ? 0 : 0.7)
            }
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, 5)
            .background(.white.opacity(showSubtitleMenu ? 0.18 : 0.09), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("字幕与字幕偏移")
        .accessibilityLabel("字幕菜单")
        .popover(isPresented: $showSubtitleMenu, arrowEdge: previewBelow ? .top : .bottom) {
            subtitleMenuContent
        }
        .onAppear {
            guard ProcessInfo.processInfo.environment["OPENFUSE_OPEN_SUBTITLE_MENU"] == "1" else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                showSubtitleMenu = true
            }
        }
    }

    private func moreMenu(compact: Bool, previewBelow: Bool) -> some View {
        Menu {
            Button {
                player.playPreviousEpisode()
            } label: {
                Label("上一集", systemImage: "backward.end")
            }
            .disabled(!player.canPlayPreviousEpisode)
            Button {
                player.playNextEpisode()
            } label: {
                Label("下一集", systemImage: "forward.end")
            }
            .disabled(!player.canPlayNextEpisode)
            Menu("音量") {
                Button("增大 5%") { player.adjustVolume(by: 5) }
                Button("减小 5%") { player.adjustVolume(by: -5) }
                Button(player.volume > 0 ? "静音" : "取消静音") { player.toggleMute() }
            }
            Divider()
            Menu("音轨") {
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
            }
            Menu("播放速度") {
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
            }
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
            Divider()
            Button {
                player.toggleFolderList()
            } label: {
                Label("同文件夹视频", systemImage: "list.bullet.rectangle")
            }
            .disabled(player.folderVideos.isEmpty)
            Button {
                player.showControlsTemporarily()
                showInfo = true
            } label: {
                Label("播放信息…", systemImage: "info.circle")
            }
            Button {
                player.toggleFullScreen()
            } label: {
                Label("全屏", systemImage: "arrow.up.left.and.arrow.down.right")
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14, weight: .medium))
                if !compact {
                    Text("更多")
                        .font(.system(size: 10.5, weight: .medium))
                }
            }
            .foregroundStyle(.white)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("音轨、速度、输出与播放信息")
        .accessibilityLabel("更多播放选项")
    }

    private var subtitleMenuContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("字幕")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 2)
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

    /// "中文（简体）(ASS)" is too wide for the panel; the button only needs the
    /// language, while the full label stays in the popover and info sheet.
    private var subtitleButtonLabel: String? {
        guard let name = selectedSubtitleName else { return nil }
        for marker in [" (", "(", " · "] {
            if let range = name.range(of: marker) {
                let short = name[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                if !short.isEmpty { return String(short.prefix(10)) }
            }
        }
        return name
    }

}

/// Tracks whether the player window's first responder is a focused control
/// (not the window/content view). SwiftUI exposes keyboard focus through the
/// responder chain for AppKit-backed controls; this keeps the floating panel
/// visible while the user is tabbing through it.
private struct ChromeFocusMonitor: NSViewRepresentable {
    var onChange: (Bool) -> Void

    func makeNSView(context: Context) -> FocusView {
        let view = FocusView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: FocusView, context: Context) {
        nsView.onChange = onChange
    }

    final class FocusView: NSView {
        var onChange: ((Bool) -> Void)?
        private var observer: NSObjectProtocol?
        private var lastValue = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard let window else {
                publish(false)
                return
            }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didUpdateNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.evaluate()
            }
            evaluate()
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil {
                if let observer { NotificationCenter.default.removeObserver(observer) }
                observer = nil
                publish(false)
            }
            super.viewWillMove(toWindow: newWindow)
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }

        private func evaluate() {
            guard let window else {
                publish(false)
                return
            }
            let responder = window.firstResponder
            let focused = responder != nil
                && responder !== window
                && responder !== window.contentView
                && !(responder is NSTextView)
            publish(focused)
        }

        private func publish(_ value: Bool) {
            guard value != lastValue else { return }
            lastValue = value
            onChange?(value)
        }
    }
}

/// Opaque fallback when Reduce Transparency is on, system glass on macOS 26+,
/// and NSVisualEffectView's within-window blend on the macOS 14/15 deployment
/// targets. The panel only occupies its drawn area, so the video surface keeps
/// its own hit testing everywhere else.
private struct PlayerPanelSurface: View {
    let cornerRadius: CGFloat
    let reduceTransparency: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
            if reduceTransparency {
                shape.fill(Color(white: 0.075).opacity(0.985))
            } else {
                if #available(macOS 26.0, *) {
                    shape
                        .fill(.clear)
                        .glassEffect(.regular, in: shape)
                        .overlay(shape.fill(.black.opacity(0.18)))
                } else {
                    VisualEffectBackground(material: .hudWindow, blendingMode: .withinWindow)
                        .clipShape(shape)
                }
            }
        }
        .overlay(shape.stroke(.white.opacity(0.14), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.40), radius: 18, y: 8)
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

private struct PanelSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

/// Full file name, source, coding and session log live here so the floating
/// panel can stay short.
private struct PlaybackInfoSheet: View {
    @ObservedObject var player: PlayerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("播放信息")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("关闭") { dismiss() }
            }
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
                row("标题", player.title)
                row("作品", player.heading.title)
                if let detail = player.heading.detail { row("季集", detail) }
                row("文件", player.playbackFileName)
                row("来源", player.sourceLabel)
                GridRow {
                    Text("AirPlay")
                        .foregroundStyle(Theme.secondary)
                    AirPlayRoutePicker()
                        .frame(width: 22, height: 22)
                        .help("AirPlay 投屏")
                }
                row("音轨", selectedAudioName ?? "默认")
                row("字幕", selectedSubtitleName ?? "关闭")
                row("速度", String(format: "%.2fx", player.speed))
                row("时长", player.duration > 0 ? Timecode.short(player.duration) : "--:--")
                if let codec = player.engine.getPropertyString("video-codec"), !codec.isEmpty {
                    row("视频编码", codec)
                }
                if let codec = player.engine.getPropertyString("audio-codec-name"), !codec.isEmpty {
                    row("音频编码", codec)
                }
                if let size = player.engine.videoSize() {
                    row("画面", "\(Int(size.width))×\(Int(size.height))")
                }
                row("缓存", player.isNetworkSource ? byteString(player.cacheBytes) : "本地文件")
            }
            .font(.system(size: 11.5))

            Text("会话日志")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.secondary)
            ScrollView {
                Text(player.logs.suffix(160).joined(separator: "\n"))
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(Theme.elevated.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(20)
        .frame(width: 640, height: 480)
        .background(Theme.background)
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(Theme.secondary)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }

    private var selectedAudioName: String? {
        guard let id = player.selectedAudioID else { return nil }
        return player.audioTracks.first(where: { $0.id == id })?.displayName
    }

    private var selectedSubtitleName: String? {
        guard let id = player.selectedSubtitleID else { return nil }
        return player.subtitleTracks.first(where: { $0.id == id })?.displayName
    }

    /// "中文（简体）(ASS)" is too wide for the panel; the button only needs the
    /// language, while the full label stays in the popover and info sheet.
    private var subtitleButtonLabel: String? {
        guard let name = selectedSubtitleName else { return nil }
        for marker in [" (", "(", " · "] {
            if let range = name.range(of: marker) {
                let short = name[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                if !short.isEmpty { return String(short.prefix(10)) }
            }
        }
        return name
    }

    private func byteString(_ size: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
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
                hovering && !disabled ? Theme.accent.opacity(0.24) : Color.clear,
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
