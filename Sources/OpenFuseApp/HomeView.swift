import AppKit
import OpenFuseCore
import SwiftUI

@main
struct OpenFuseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup("OpenFuse") {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .frame(minWidth: 980, minHeight: 620)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开文件…") {
                    model.presentOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        if let window = NSApp.windows.first {
            window.setContentSize(NSSize(width: 1180, height: 760))
            window.center()
            window.setFrameAutosaveName("OpenFuseMainWindow")
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        handleLaunchArguments()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.saveForTermination()
    }

    private func handleLaunchArguments() {
        let arguments = CommandLine.arguments
        let model = AppModel.shared
        if let captureUI = value(after: "--capture-ui", in: arguments) {
            let delay = value(after: "--ui-after", in: arguments).flatMap(Double.init) ?? 2.5
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                model.captureUI(to: URL(fileURLWithPath: captureUI))
            }
        }

        if arguments.contains("--show-add-source") {
            model.showAddSource = true
        }
        if arguments.contains("--webdav-browse-saved") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if let source = model.sources.first {
                    model.browse(source)
                }
                self.scheduleAutomation(model: model, arguments: arguments, reopen: {})
            }
            return
        }
        if arguments.contains("--resume-first") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if let record = model.recent.first {
                    model.resume(record)
                }
                self.scheduleAutomation(model: model, arguments: arguments, reopen: {})
            }
            return
        }
        let localPath = value(after: "--open", in: arguments)
        let webdavURL = value(after: "--webdav-url", in: arguments)
        guard localPath != nil || webdavURL != nil else {
            scheduleQuitOnly(arguments: arguments)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if let localPath {
                model.open(url: URL(fileURLWithPath: localPath))
                self.scheduleAutomation(model: model, arguments: arguments, reopen: {
                    model.open(url: URL(fileURLWithPath: localPath))
                })
                return
            }

            guard let webdavURL, let baseURL = URL(string: webdavURL) else {
                self.scheduleQuitOnly(arguments: arguments)
                return
            }
            let user = self.value(after: "--webdav-user", in: arguments)
                ?? ProcessInfo.processInfo.environment["OPENFUSE_WEBDAV_USER"] ?? ""
            let password = ProcessInfo.processInfo.environment["OPENFUSE_WEBDAV_PASSWORD"]
                ?? self.value(after: "--webdav-pass", in: arguments) ?? ""
            let name = self.value(after: "--webdav-name", in: arguments) ?? "WebDAV"
            let remotePath = self.value(after: "--webdav-path", in: arguments)
            let browseOnly = remotePath == nil || arguments.contains("--webdav-browse")

            Task { @MainActor in
                guard let source = await model.addSource(name: name, urlText: baseURL.absoluteString, username: user, password: password) else {
                    self.scheduleQuitOnly(arguments: arguments)
                    return
                }
                if browseOnly {
                    model.browse(source)
                } else if let remotePath {
                    await model.openRemote(source: source, path: remotePath)
                }
                self.scheduleAutomation(model: model, arguments: arguments, reopen: {
                    Task { @MainActor in await model.openRemote(source: source, path: remotePath ?? "") }
                })
            }
        }
    }

    private func scheduleAutomation(model: AppModel, arguments: [String], reopen: @escaping () -> Void) {
        if let seek = value(after: "--seek", in: arguments).flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                model.player?.seek(to: seek)
            }
        }
        if let subtitleTag = value(after: "--subtitle", in: arguments) {
            model.player?.selectSubtitle(language: subtitleTag, attempts: 10)
        }
        if let freezeAt = value(after: "--freeze-at", in: arguments).flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                model.player?.freeze(at: freezeAt)
            }
        }
        if arguments.contains("--fullscreen") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                model.player?.toggleFullScreen()
            }
        }
        if arguments.contains("--reopen-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                model.closePlayer()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.5) {
                reopen()
            }
        }
        if let capture = value(after: "--capture", in: arguments) {
            let captureAfter = value(after: "--capture-after", in: arguments).flatMap(Double.init) ?? 3
            DispatchQueue.main.asyncAfter(deadline: .now() + captureAfter) {
                model.player?.captureScreenshot(to: URL(fileURLWithPath: capture))
                if let report = self.value(after: "--report", in: arguments) {
                    model.writeTestReport(to: URL(fileURLWithPath: report))
                }
            }
        } else if let report = value(after: "--report", in: arguments) {
            let captureAfter = value(after: "--capture-after", in: arguments).flatMap(Double.init) ?? 3
            DispatchQueue.main.asyncAfter(deadline: .now() + captureAfter) {
                model.writeTestReport(to: URL(fileURLWithPath: report))
            }
        }
        if let quitAfter = value(after: "--quit-after", in: arguments).flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + quitAfter) {
                NSApp.terminate(nil)
            }
        }
    }

    private func scheduleQuitOnly(arguments: [String]) {
        if let quitAfter = value(after: "--quit-after", in: arguments).flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + quitAfter) {
                NSApp.terminate(nil)
            }
        }
    }

    private func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.count > index + 1 else { return nil }
        return arguments[index + 1]
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            switch model.route {
            case .home:
                HomeView()
            case .player:
                if let player = model.player {
                    PlayerView(player: player)
                } else {
                    HomeView()
                }
            case .browser(let source):
                WebDAVBrowserView(source: source)
            }
        }
        .background(Theme.background)
    }
}

enum Theme {
    static let background = Color(red: 0.043, green: 0.051, blue: 0.067)
    static let panel = Color(red: 0.082, green: 0.094, blue: 0.118)
    static let elevated = Color(red: 0.114, green: 0.129, blue: 0.157)
    static let accent = Color(red: 0.36, green: 0.78, blue: 0.98)
    static let warm = Color(red: 0.98, green: 0.72, blue: 0.25)
    static let text = Color(red: 0.93, green: 0.95, blue: 0.98)
    static let secondary = Color(red: 0.58, green: 0.63, blue: 0.70)
    static let stroke = Color.white.opacity(0.08)
}

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isDropTarget = false

    private let columns = [GridItem(.adaptive(minimum: 250, maximum: 340), spacing: 22)]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.background, Color(red: 0.055, green: 0.07, blue: 0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        if model.recent.isEmpty {
                            emptyState
                        } else {
                            continueWatching
                        }
                        if !model.sources.isEmpty {
                            networkSources
                        }
                        engineCard
                    }
                    .padding(.horizontal, 36)
                    .padding(.bottom, 32)
                }
            }
        }
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .background(Theme.accent.opacity(0.08).clipShape(RoundedRectangle(cornerRadius: 24)))
                    .padding(18)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
            handleDrop(providers)
        }
        .animation(.easeInOut(duration: 0.2), value: isDropTarget)
        .sheet(isPresented: $model.showAddSource) {
            AddSourceSheet()
                .environmentObject(model)
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.accent, Color(red: 0.45, green: 0.42, blue: 0.95)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.background)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text("OpenFuse")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text("本地播放 · Mac 首版")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.secondary)
            }

            Spacer()

            Button {
                model.showAddSource = true
            } label: {
                Label("添加来源", systemImage: "network")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.elevated, in: Capsule())
                    .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button {
                model.presentOpenPanel()
            } label: {
                Label("打开文件…", systemImage: "folder")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.elevated, in: Capsule())
                    .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("o", modifiers: .command)

            Button {
                // Settings live in M3; this placeholder is deliberately inert.
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 34, height: 34)
                    .background(Theme.elevated, in: Circle())
                    .overlay(Circle().stroke(Theme.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("设置（M3 接入）")
        }
        .padding(.horizontal, 36)
        .padding(.top, 28)
        .padding(.bottom, 26)
    }

    private var continueWatching: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("继续观看")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text("\(model.recent.count) 个条目")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                ForEach(model.recent) { record in
                    MediaCard(record: record) {
                        model.resume(record)
                    } onRemove: {
                        model.removeRecent(record)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("从这里开始")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.text)
            VStack(alignment: .leading, spacing: 14) {
                step(number: 1, title: "打开一个 MKV", detail: "支持本地 HEVC Main 10、E-AC-3 5.1 以及 ASS/SRT 外挂字幕。")
                step(number: 2, title: "播放与切轨", detail: "空格暂停，←/→ 快退快进 10 秒，字幕和音轨在控制栏切换。")
                step(number: 3, title: "退出后继续", detail: "关闭播放器会保存位置；再次打开同一文件时从上次位置继续。")
            }
            .padding(22)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.stroke, lineWidth: 1))

            Button {
                model.presentOpenPanel()
            } label: {
                Label("选择视频文件", systemImage: "play.rectangle.on.rectangle")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .foregroundStyle(Theme.background)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: 760, alignment: .leading)
    }

    private func step(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.background)
                .frame(width: 24, height: 24)
                .background(Theme.accent, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var networkSources: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("网络来源")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button {
                    model.showAddSource = true
                } label: {
                    Label("添加", systemImage: "plus")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
            }
            ForEach(model.sources) { source in
                HStack(spacing: 14) {
                    Image(systemName: "externaldrive.connected.to.line.below")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 38, height: 38)
                        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(source.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text(source.baseURL.absoluteString)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("浏览") {
                        model.browse(source)
                    }
                    .buttonStyle(.bordered)
                    Button {
                        model.removeSource(source)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(Theme.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("移除来源（不删除服务器文件）")
                }
                .padding(14)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
            }
        }
    }

    private var engineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("播放路径")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text("libmpv \(mpvVersion) · OpenGL 渲染 · VideoToolbox 硬解 · CoreAudio 输出")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.secondary)
            Text("M0 引擎对照与 M1 本地播放的验收记录见 Docs/ENGINE-DECISION.md 与 Docs/M1-ACCEPTANCE.md。")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondary.opacity(0.8))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
    }

    private var mpvVersion: String {
        let version = AppModel.shared.player?.engine.getPropertyString("mpv-version") ?? "v0.42.0"
        return version.replacingOccurrences(of: "mpv ", with: "")
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            var url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let value = item as? URL {
                url = value
            }
            if let url {
                Task { @MainActor in model.open(url: url) }
            }
        }
        return true
    }
}

struct MediaCard: View {
    let record: PlaybackRecord
    let onOpen: () -> Void
    let onRemove: () -> Void

    private var progress: Double {
        guard record.duration > 0 else { return 0 }
        return min(1, max(0, record.position / record.duration))
    }

    private var hue: Double {
        let hash = abs(record.mediaPath.hashValue % 360)
        return Double(hash) / 360.0
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hue: hue, saturation: 0.45, brightness: 0.35),
                                    Color(hue: hue + 0.08, saturation: 0.55, brightness: 0.18),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    HStack {
                        Spacer()
                        Image(systemName: record.isFinished ? "checkmark.circle.fill" : "play.circle.fill")
                            .font(.system(size: 38, weight: .regular))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(16)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.displayTitle ?? record.url.deletingPathExtension().lastPathComponent)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(record.isFinished ? "已看完" : "\(Timecode.short(record.position)) / \(Timecode.short(record.duration))")
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(16)
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay(alignment: .bottom) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.18))
                            Capsule().fill(Theme.accent)
                                .frame(width: geometry.size.width * (record.isFinished ? 1 : progress))
                        }
                    }
                    .frame(height: 3)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                }
                .overlay(alignment: .topLeading) {
                    Text(record.isFinished ? "已看" : "继续")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.45), in: Capsule())
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("打开", action: onOpen)
            Button("从播放记录中移除", role: .destructive, action: onRemove)
        }
    }
}

enum Timecode {
    static func short(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total / 60) % 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}
