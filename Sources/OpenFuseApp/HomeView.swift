import AppKit
import OpenFuseCore
import SwiftUI

@main
struct OpenFuseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared
    @AppStorage(AppTheme.storageKey) private var appearance = AppTheme.light.rawValue

    /// The player is always dark: it draws on black and its AppKit menus,
    /// symbol buttons and the window titlebar all follow this appearance.
    /// Keeping it at the scene level is what makes the titlebar match the
    /// player in the (default) light theme.
    private var preferredColorScheme: ColorScheme? {
        if case .player = model.route { return .dark }
        return AppTheme(rawValue: appearance)?.colorScheme
    }

    var body: some Scene {
        WindowGroup("OpenFuse") {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(preferredColorScheme)
                .onAppear { AppTheme(rawValue: appearance)?.apply() }
                .onChange(of: appearance) { _, newValue in
                    AppTheme(rawValue: newValue)?.apply()
                }
                .frame(
                    minWidth: model.player == nil ? 980 : 320,
                    minHeight: model.player == nil ? 620 : 180
                )
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开文件…") {
                    model.presentOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .windowSize) {
                Divider()
                Button("最大化窗口") {
                    model.maximizePlayerWindow()
                }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(model.player == nil)

                Button {
                    model.toggleAlwaysOnTop()
                } label: {
                    if model.isAlwaysOnTop {
                        Label("总在最前", systemImage: "checkmark")
                    } else {
                        Text("总在最前")
                    }
                }
                .keyboardShortcut("t", modifiers: [.control, .command])
                .disabled(model.player == nil)

                Divider()
                Button("正常大小") { model.applyWindowScale(.normal) }
                    .keyboardShortcut("1", modifiers: .command)
                    .disabled(model.player == nil)
                Button("半屏大小") { model.applyWindowScale(.half) }
                    .keyboardShortcut("0", modifiers: .command)
                    .disabled(model.player == nil)
                Button("双倍大小") { model.applyWindowScale(.doubleSize) }
                    .keyboardShortcut("2", modifiers: .command)
                    .disabled(model.player == nil)
                Button("适合屏幕") { model.applyWindowScale(.fit) }
                    .keyboardShortcut("4", modifiers: .command)
                    .disabled(model.player == nil)
                Button("缩小窗口") { model.applyWindowScale(.smaller) }
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(model.player == nil)
                Button("放大窗口") { model.applyWindowScale(.bigger) }
                    .keyboardShortcut("=", modifiers: .command)
                    .disabled(model.player == nil)
            }
            CommandMenu("播放") {
                Button(model.player?.isPaused == true ? "继续播放" : "暂停") {
                    model.player?.togglePlayPause()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(model.player == nil)
                Button("快退 10 秒") { model.player?.skip(-10) }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                    .disabled(model.player == nil)
                Button("快进 10 秒") { model.player?.skip(10) }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                    .disabled(model.player == nil)
                Divider()
                Menu("字幕") {
                    Button {
                        model.player?.selectSubtitle(nil)
                    } label: {
                        if model.player?.selectedSubtitleID == nil {
                            Label("关闭字幕", systemImage: "checkmark")
                        } else {
                            Text("关闭字幕")
                        }
                    }
                    Divider()
                    ForEach(model.player?.subtitleTracks ?? []) { track in
                        Button {
                            model.player?.selectSubtitle(track)
                        } label: {
                            if model.player?.selectedSubtitleID == track.id {
                                Label(track.displayName, systemImage: "checkmark")
                            } else {
                                Text(track.displayName)
                            }
                        }
                    }
                    Divider()
                    Text("字幕偏移：\(model.player?.subtitleDelaySummary ?? "同步（0 秒）")")
                    Button("提前 0.1 秒") { model.player?.adjustSubtitleDelay(by: -0.1) }
                        .disabled(model.player?.selectedSubtitleID == nil)
                    Button("延后 0.1 秒") { model.player?.adjustSubtitleDelay(by: 0.1) }
                        .disabled(model.player?.selectedSubtitleID == nil)
                    Button("输入秒数…") { model.player?.beginSubtitleDelayInput() }
                        .disabled(model.player?.selectedSubtitleID == nil)
                    Button("重置为 0") { model.player?.resetSubtitleDelay() }
                        .disabled(model.player?.selectedSubtitleID == nil)
                }
                .disabled(model.player == nil)
                Menu("音轨") {
                    ForEach(model.player?.audioTracks ?? []) { track in
                        Button {
                            model.player?.selectAudio(track)
                        } label: {
                            if model.player?.selectedAudioID == track.id {
                                Label("\(track.displayName) · \(track.technicalLabel)", systemImage: "checkmark")
                            } else {
                                Text("\(track.displayName) · \(track.technicalLabel)")
                            }
                        }
                    }
                    Divider()
                    Menu("音频输出") {
                        ForEach(model.player?.audioDevices ?? []) { device in
                            Button {
                                model.player?.selectAudioDevice(device.id)
                            } label: {
                                if model.player?.selectedAudioDeviceID == device.id {
                                    Label("\(device.name)（\(device.outputChannels)ch）", systemImage: "checkmark")
                                } else {
                                    Text("\(device.name)（\(device.outputChannels)ch）")
                                }
                            }
                        }
                    }
                }
                .disabled(model.player == nil)
                Divider()
                Button("跳转到时间…") {
                    model.showSeekPrompt = true
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(model.player == nil)
                Button("返回来源") { model.closePlayer() }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                    .disabled(model.player == nil)
            }
            CommandMenu("验收") {
                Button("保存当前画面与播放报告") {
                    _ = model.savePlayerEvidence()
                }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(model.player == nil)
                Button("保存界面截图") {
                    _ = model.saveUIEvidence()
                }
                .keyboardShortcut("u", modifiers: [.command, .option])
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        PlaybackTrace.installHeartbeat()
        AppModel.shared.installWindowStateObservers()
        AppTheme.stored.apply()
        purgeLegacyTraktState()
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

    /// Clicking the Dock icon (or reopening) should surface the player window
    /// again without stealing focus repeatedly while another app is active.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, let window = sender.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Writes the final per-stage render percentiles to the timing log, so
        // an acceptance run covers the Cmd+Tab windows and not only the report
        // snapshot taken a few seconds after the first frame.
        RenderTiming.shared.logSummary()
        AppModel.shared.stopWindowRecording()
        AppModel.shared.saveForTermination()
    }

    /// Trakt 同步已完全移除；升级后清掉旧版本留下的偏好与 Keychain 凭据。
    private func purgeLegacyTraktState() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "openfuse.trakt.purged") else { return }
        defaults.removeObject(forKey: "openfuse.trakt.clientID")
        defaults.removeObject(forKey: "openfuse.trakt.baseURL")
        CredentialStore.delete(account: "trakt-token", service: "com.openfuse.trakt")
        CredentialStore.delete(account: "trakt-secret", service: "com.openfuse.trakt")
        defaults.set(true, forKey: "openfuse.trakt.purged")
    }

    private func handleLaunchArguments() {
        let arguments = CommandLine.arguments
        let model = AppModel.shared
        if let rawTheme = value(after: "--appearance", in: arguments),
           let theme = AppTheme(rawValue: rawTheme) {
            AppTheme.persist(theme)
        }
        if let captureUI = value(after: "--capture-ui", in: arguments) {
            let delayed = value(after: "--ui-after", in: arguments).flatMap(Double.init) ?? 2.5
            let preferKey = arguments.contains("--capture-sheet")
            DispatchQueue.main.asyncAfter(deadline: .now() + delayed) {
                model.captureUI(to: URL(fileURLWithPath: captureUI), preferKeyWindow: preferKey)
            }
        }
        if let captureWindow = value(after: "--capture-window", in: arguments) {
            let delayed = value(after: "--ui-after", in: arguments).flatMap(Double.init) ?? 2.5
            DispatchQueue.main.asyncAfter(deadline: .now() + delayed) {
                model.captureWindow(to: URL(fileURLWithPath: captureWindow))
            }
        }
        if let captureScreen = value(after: "--capture-screen", in: arguments) {
            let delayed = value(after: "--ui-after", in: arguments).flatMap(Double.init) ?? 2.5
            DispatchQueue.main.asyncAfter(deadline: .now() + delayed) {
                model.captureScreen(to: URL(fileURLWithPath: captureScreen))
            }
        }
        if let recordWindow = value(after: "--record-window", in: arguments) {
            let fps = value(after: "--record-fps", in: arguments).flatMap(Double.init) ?? 10
            let startAfter = value(after: "--record-after", in: arguments).flatMap(Double.init) ?? 1.0
            model.startWindowRecording(
                to: URL(fileURLWithPath: recordWindow),
                fps: fps,
                startAfter: startAfter
            )
        }
        if let recordScreen = value(after: "--record-screen", in: arguments) {
            let fps = value(after: "--record-fps", in: arguments).flatMap(Double.init) ?? 10
            let startAfter = value(after: "--record-after", in: arguments).flatMap(Double.init) ?? 1.0
            model.startWindowRecording(
                to: URL(fileURLWithPath: recordScreen),
                fps: fps,
                startAfter: startAfter,
                includePopovers: true
            )
        }

        if arguments.contains("--home") {
            if let sidebar = value(after: "--sidebar", in: arguments),
               let destination = SidebarDestination(rawValue: sidebar) {
                model.sidebarDestination = destination
            }
            model.route = .home
            scheduleAutomation(model: model, arguments: arguments, reopen: {})
            return
        }
        if arguments.contains("--show-add-source") {
            model.showAddSource = true
        }
        if arguments.contains("--show-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                model.showSettings = true
            }
        }
        if let newUser = value(after: "--jellyfin-switch-user", in: arguments) {
            let password = value(after: "--jellyfin-switch-password", in: arguments) ?? ""
            let wantedID = value(after: "--jellyfin-switch-source", in: arguments)
            Task { @MainActor in
                let source = wantedID.flatMap { id in
                    model.jellyfinSources.first { $0.id == id || $0.name == id }
                } ?? model.jellyfinSources.first
                guard let source else {
                    print("no jellyfin source")
                    self.scheduleQuitOnly(arguments: arguments)
                    return
                }
                _ = await model.switchJellyfinUser(source, username: newUser, password: password)
                if let report = self.value(after: "--library-report", in: arguments) {
                    model.writeLibraryReport(to: URL(fileURLWithPath: report))
                }
                print("jellyfin user switched to \(newUser)")
                self.scheduleQuitOnly(arguments: arguments)
            }
            return
        }
        if let removeRoot = value(after: "--remove-local-root", in: arguments) {
            Task { @MainActor in
                let path = URL(fileURLWithPath: removeRoot).standardizedFileURL.path
                if let root = model.localRoots.first(where: { $0.path == path }) {
                    model.removeLocalRoot(root)
                }
                if let report = self.value(after: "--library-report", in: arguments) {
                    model.writeLibraryReport(to: URL(fileURLWithPath: report))
                }
                self.scheduleQuitOnly(arguments: arguments)
            }
            return
        }
        if let scanLocal = value(after: "--scan-local", in: arguments) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if let cancelAfter = self.value(after: "--cancel-scan-after", in: arguments).flatMap(Double.init) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + cancelAfter) {
                        model.cancelScan()
                    }
                }
                Task { @MainActor in
                    await model.scanLocalFolder(URL(fileURLWithPath: scanLocal))
                    self.finishLibraryLaunch(model: model, arguments: arguments)
                }
            }
            return
        }
        if let playID = value(after: "--library-play", in: arguments) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let versionIndex = self.value(after: "--library-version", in: arguments).flatMap(Int.init)
                guard model.playLibraryEpisode(id: playID, versionIndex: versionIndex) else {
                    self.scheduleQuitOnly(arguments: arguments)
                    return
                }
                self.scheduleAutomation(model: model, arguments: arguments, reopen: {})
            }
            return
        }
        let hasRemoteOrLocalLaunch = arguments.contains("--jellyfin-url")
            || arguments.contains("--webdav-url") || arguments.contains("--plex-url")
            || arguments.contains("--emby-url") || arguments.contains("--smb-server")
            || arguments.contains("--open")
        if !hasRemoteOrLocalLaunch,
           arguments.contains("--library-work") || arguments.contains("--library-report")
            || arguments.contains("--library-search") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if let search = self.value(after: "--library-search", in: arguments) {
                    model.librarySearch = search
                }
                if let sort = self.value(after: "--library-sort", in: arguments),
                   let parsed = LibrarySort(rawValue: sort) {
                    model.librarySort = parsed
                }
                if let filter = self.value(after: "--library-filter", in: arguments) {
                    model.libraryKindFilter = filter == "movie" ? .movie : (filter == "series" ? .series : nil)
                }
                if let watch = self.value(after: "--library-watch", in: arguments),
                   let parsed = LibraryWatchFilter(rawValue: watch) {
                    model.libraryWatchFilter = parsed
                }
                if let resolution = self.value(after: "--library-resolution", in: arguments),
                   let parsed = LibraryResolutionFilter(rawValue: resolution) {
                    model.libraryResolutionFilter = parsed
                }
                if arguments.contains("--library-spoiler") {
                    UserDefaults.standard.set(true, forKey: "openfuse.spoilerProtection")
                }
                if let query = self.value(after: "--library-work", in: arguments),
                   let work = model.findWork(matching: query) {
                    if arguments.contains("--library-clear-override") {
                        model.clearOverride(workID: work.id)
                    } else if let targetQuery = self.value(after: "--library-merge", in: arguments),
                              let target = model.findWork(matching: targetQuery) {
                        model.mergeWork(work, into: target)
                    } else if arguments.contains("--library-split") {
                        model.splitWork(work)
                    } else if arguments.contains("--library-edit-title")
                                || arguments.contains("--library-edit-year")
                                || arguments.contains("--library-edit-overview")
                                || arguments.contains("--library-edit-poster") {
                        model.setOverride(
                            workID: work.id,
                            title: self.value(after: "--library-edit-title", in: arguments),
                            year: self.value(after: "--library-edit-year", in: arguments).flatMap(Int.init),
                            overview: self.value(after: "--library-edit-overview", in: arguments),
                            poster: self.value(after: "--library-edit-poster", in: arguments)
                        )
                    } else {
                        model.route = .library(work)
                    }
                }
                if let report = self.value(after: "--library-report", in: arguments) {
                    model.writeLibraryReport(to: URL(fileURLWithPath: report))
                }
                self.scheduleQuitOnly(arguments: arguments)
            }
            return
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
        if let smbServer = value(after: "--smb-server", in: arguments) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                let port = self.value(after: "--smb-port", in: arguments).flatMap(Int.init) ?? 445
                let share = self.value(after: "--smb-share", in: arguments) ?? ""
                let user = self.value(after: "--smb-user", in: arguments)
                    ?? ProcessInfo.processInfo.environment["OPENFUSE_SMB_USER"] ?? ""
                let password = self.value(after: "--smb-pass", in: arguments)
                    ?? ProcessInfo.processInfo.environment["OPENFUSE_SMB_PASSWORD"] ?? ""
                let name = self.value(after: "--smb-name", in: arguments) ?? "SMB"
                let base = self.value(after: "--smb-path", in: arguments) ?? ""
                Task { @MainActor in
                    let source = await model.addSMBSource(
                        name: name, server: smbServer, port: port, share: share,
                        username: user, password: password, basePath: base
                    )
                    if source != nil {
                        self.finishLibraryLaunch(model: model, arguments: arguments)
                    } else {
                        self.scheduleQuitOnly(arguments: arguments)
                    }
                }
            }
            return
        }
        if let plexURL = value(after: "--plex-url", in: arguments) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                let token = self.value(after: "--plex-token", in: arguments)
                    ?? ProcessInfo.processInfo.environment["OPENFUSE_PLEX_TOKEN"]
                    ?? ""
                let name = self.value(after: "--plex-name", in: arguments) ?? "Plex"
                Task { @MainActor in
                    let ok = await model.addPlexSource(name: name, urlText: plexURL, token: token)
                    if ok {
                        let playKey = self.value(after: "--plex-play", in: arguments)
                        if let playKey {
                            await model.playPlexMetadata(source: model.plexSources.last!, ratingKey: playKey)
                            self.scheduleAutomation(model: model, arguments: arguments, reopen: {})
                            return
                        }
                        if arguments.contains("--plex-browse") {
                            if let plexSource = model.plexSources.last {
                                model.browsePlex(plexSource)
                            }
                            self.scheduleQuitOnly(arguments: arguments)
                        } else {
                            self.finishLibraryLaunch(model: model, arguments: arguments)
                        }
                    } else {
                        self.scheduleQuitOnly(arguments: arguments)
                    }
                }
            }
            return
        }
        let embyURL = value(after: "--emby-url", in: arguments)
        if let jellyfinURL = value(after: "--jellyfin-url", in: arguments) ?? embyURL,
           let baseURL = URL(string: jellyfinURL) {
            let isEmby = embyURL != nil && self.value(after: "--jellyfin-url", in: arguments) == nil
            let serverKind = isEmby ? "emby" : "jellyfin"
            let user = self.value(after: "--jellyfin-user", in: arguments)
                ?? self.value(after: "--emby-user", in: arguments)
                ?? ProcessInfo.processInfo.environment[isEmby ? "OPENFUSE_EMBY_USER" : "OPENFUSE_JELLYFIN_USER"] ?? ""
            let password = ProcessInfo.processInfo.environment[isEmby ? "OPENFUSE_EMBY_PASSWORD" : "OPENFUSE_JELLYFIN_PASSWORD"]
                ?? self.value(after: "--jellyfin-pass", in: arguments)
                ?? self.value(after: "--emby-pass", in: arguments) ?? ""
            let name = self.value(after: "--jellyfin-name", in: arguments)
                ?? self.value(after: "--emby-name", in: arguments)
                ?? (isEmby ? "Emby" : "Jellyfin")
            let itemID = self.value(after: "--jellyfin-item", in: arguments)
            let mediaID = self.value(after: "--jellyfin-media", in: arguments)
            let detailID = self.value(after: "--jellyfin-detail", in: arguments)
            let detailEpisodeID = self.value(after: "--jellyfin-episode", in: arguments)
            let detailSeasonID = self.value(after: "--jellyfin-season", in: arguments)
            Task { @MainActor in
                guard let source = await model.addJellyfinSource(
                    name: name,
                    urlText: baseURL.absoluteString,
                    username: user,
                    password: password,
                    serverKind: serverKind
                ) else {
                    self.scheduleQuitOnly(arguments: arguments)
                    return
                }
                if arguments.contains("--jellyfin-scan") || arguments.contains("--emby-scan") {
                    await model.scanJellyfinSource(source)
                    self.finishLibraryLaunch(model: model, arguments: arguments)
                    return
                }
                if let detailID {
                    model.setJellyfinDetailSelection(
                        source: source,
                        detailItemID: detailID,
                        seasonID: detailSeasonID,
                        episodeID: detailEpisodeID,
                        mediaSourceID: mediaID
                    )
                    model.browseJellyfin(source)
                } else if let itemID, !arguments.contains("--jellyfin-browse") {
                    await model.openJellyfinItem(source: source, itemID: itemID, preferredMediaSourceID: mediaID)
                } else {
                    model.browseJellyfin(source)
                }
                self.scheduleAutomation(model: model, arguments: arguments, reopen: {
                    Task { @MainActor in
                        if let itemID {
                            await model.openJellyfinItem(source: source, itemID: itemID, preferredMediaSourceID: mediaID)
                        }
                    }
                })
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
                if arguments.contains("--webdav-scan") {
                    await model.scanWebDAVSource(source)
                    self.finishLibraryLaunch(model: model, arguments: arguments)
                    return
                }
                if browseOnly {
                    // Acceptance hook: start the browser deep in the tree so a
                    // screenshot can prove the breadcrumb only ever shows one
                    // segment per path element.
                    if let startPath = self.value(after: "--webdav-browse-path", in: arguments) {
                        model.setWebDAVPath(RemotePath.stack(startPath), for: source)
                    }
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

    private func finishLibraryLaunch(model: AppModel, arguments: [String]) {
        if let search = value(after: "--library-search", in: arguments) {
            model.librarySearch = search
        }
        if let sort = value(after: "--library-sort", in: arguments),
           let parsed = LibrarySort(rawValue: sort) {
            model.librarySort = parsed
        }
        if let filter = value(after: "--library-filter", in: arguments) {
            model.libraryKindFilter = filter == "movie" ? .movie : (filter == "series" ? .series : nil)
        }
        if let watch = value(after: "--library-watch", in: arguments),
           let parsed = LibraryWatchFilter(rawValue: watch) {
            model.libraryWatchFilter = parsed
        }
        if let resolution = value(after: "--library-resolution", in: arguments),
           let parsed = LibraryResolutionFilter(rawValue: resolution) {
            model.libraryResolutionFilter = parsed
        }
        if arguments.contains("--library-spoiler") {
            UserDefaults.standard.set(true, forKey: "openfuse.spoilerProtection")
        }
        if let query = value(after: "--library-work", in: arguments),
           let work = model.findWork(matching: query) {
            model.route = .library(work)
        }
        if let report = value(after: "--library-report", in: arguments) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                model.writeLibraryReport(to: URL(fileURLWithPath: report))
            }
        }
        scheduleQuitOnly(arguments: arguments)
    }

    private func scheduleAutomation(model: AppModel, arguments: [String], reopen: @escaping () -> Void) {
        if let sequence = value(after: "--resume-sequence", in: arguments) {
            let first = model.recent.first { ($0.displayTitle ?? "").contains("S01E08") }
            let second = model.recent.first { ($0.displayTitle ?? "").contains("S01E07") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                if let first { model.resume(first) }
            }
            if sequence == "double" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    if let first { model.resume(first) }
                }
            } else if sequence == "cancel-switch" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    model.cancelLoading()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    if let second { model.resume(second) }
                }
            }
        }

        // Acceptance hook: open another file while the first one is still
        // opening, i.e. the "pick a different episode during loading" case.
        if let switchPath = value(after: "--switch-to", in: arguments),
           let delay = value(after: "--switch-after", in: arguments).flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                model.open(url: URL(fileURLWithPath: switchPath))
            }
        }
        if arguments.contains("--folder-list") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                model.player?.showFolderList = true
            }
        }
        if let needle = value(after: "--folder-select", in: arguments) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                if let video = model.player?.folderVideos.first(where: { $0.fileName.contains(needle) }) {
                    model.player?.onSelectFolderVideo?(video)
                }
            }
        }
        if let needle = value(after: "--select-subtitle", in: arguments) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                if let track = model.player?.subtitleTracks.first(where: { $0.displayName.contains(needle) }) {
                    model.player?.selectSubtitle(track)
                }
            }
        }
        if let delay = value(after: "--sub-delay", in: arguments).flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
                model.player?.setSubtitleDelay(delay)
            }
        }
        if let seek = value(after: "--seek", in: arguments).flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                model.player?.seek(to: seek)
            }
        }
        if let subtitleTag = value(after: "--subtitle", in: arguments) {
            model.player?.selectSubtitle(language: subtitleTag, attempts: 10)
        }
        if let rescan = value(after: "--rescan-local", in: arguments) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                model.startLocalScan(URL(fileURLWithPath: rescan))
            }
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
                model.player?.finishSession()
                NSApp.terminate(nil)
            }
        }
    }

    private func scheduleQuitOnly(arguments: [String]) {
        if let quitAfter = value(after: "--quit-after", in: arguments).flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + quitAfter) {
                AppModel.shared.player?.finishSession()
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
                MainShellView { HomeView(destination: model.sidebarDestination) }
            case .player:
                if let player = model.player {
                    PlayerView(player: player)
                } else {
                    HomeView()
                }
            case .loading:
                PlayerLoadingView()
            case .browser(let source):
                MainShellView { WebDAVBrowserView(source: source) }
            case .jellyfinBrowser(let source):
                MainShellView { JellyfinBrowserView(source: source) }
            case .plexBrowser(let source):
                MainShellView { PlexBrowserView(source: source) }
            case .library(let work):
                MainShellView { LibraryDetailView(work: work) }
            }
        }
        .background(Theme.background)
        .sheet(isPresented: $model.showSeekPrompt) {
            SeekPromptSheet()
        }
    }
}

struct SeekPromptSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("跳转到时间")
                .font(.system(size: 17, weight: .semibold))
            Text("输入 mm:ss、h:mm:ss 或秒数，例如 05:00。")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            TextField("时间", text: $model.seekPromptText, prompt: Text("05:00"))
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("跳转") { model.performSeekPrompt() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 360)
        .background(Theme.background)
    }
}

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    var destination: SidebarDestination = .home
    @AppStorage("openfuse.spoilerProtection") private var spoilerProtection = false
    @State private var isDropTarget = false
    @State private var showAllHistory = false
    @State private var recentThumbnails: [String: URL] = [:]
    @State private var showAddJellyfin = false
    @State private var showAddPlex = false
    @State private var showAddSMB = false

    private let columns = [GridItem(.adaptive(minimum: 250, maximum: 340), spacing: 22)]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.background, Theme.backgroundAlt],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                pageHeader
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        switch destination {
                        case .home:
                            if model.recent.isEmpty { emptyState } else { continueWatching }
                        case .library:
                            mediaLibrary
                        case .files:
                            if !model.sources.isEmpty { networkSources }
                            if !model.jellyfinSources.isEmpty { jellyfinSourcesSection }
                            if !model.plexSources.isEmpty { plexSourcesSection }
                            if !model.smbSources.isEmpty { smbSourcesSection }
                            if model.sources.isEmpty && model.jellyfinSources.isEmpty
                                && model.plexSources.isEmpty && model.smbSources.isEmpty {
                                emptyState
                            }
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
        .sheet(isPresented: $showAddJellyfin) {
            AddJellyfinSheet()
                .environmentObject(model)
        }
        .sheet(isPresented: $showAddPlex) {
            AddPlexSheet()
                .environmentObject(model)
        }
        .sheet(isPresented: $showAddSMB) {
            AddSMBSheet()
                .environmentObject(model)
        }
    }

    private var pageHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(destination.title)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(destinationSubtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer()
            if destination == .files {
                Button {
                    showAddSourceSheet()
                } label: {
                    Label("添加来源", systemImage: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Theme.accent.opacity(0.14), in: Capsule())
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                scanMenu
            } else if destination == .library {
                scanMenu
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 26)
        .padding(.bottom, 22)
    }

    private var destinationSubtitle: String {
        switch destination {
        case .home: return "最近观看 · 最多 4 项"
        case .library: return "按作品浏览、搜索和筛选"
        case .files: return "已连接的媒体来源"
        }
    }

    private var scanMenu: some View {
        Menu {
            Button("添加并扫描文件夹…") { chooseFolderToScan() }
            if !model.localRoots.isEmpty {
                Button("扫描全部本地根目录（\(model.localRoots.count)）") { model.scanAllLocalRoots() }
            }
            if !model.sources.isEmpty {
                Divider()
                ForEach(model.sources) { source in
                    Button("扫描 WebDAV：\(source.name)") { model.startWebDAVScan(source) }
                }
            }
            if !model.jellyfinSources.isEmpty {
                Divider()
                ForEach(model.jellyfinSources) { source in
                    Button("扫描 Jellyfin：\(source.name)") { model.startJellyfinScan(source) }
                }
            }
        } label: {
            Label("扫描", systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.elevated, in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func showAddSourceSheet() {
        model.showAddSource = true
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

            Menu {
                Button("添加并扫描文件夹…") { chooseFolderToScan() }
                if !model.localRoots.isEmpty {
                    Button("扫描全部本地根目录（\(model.localRoots.count)）") {
                        model.scanAllLocalRoots()
                    }
                    Menu("移除本地根目录") {
                        ForEach(model.localRoots) { root in
                            Button(root.name) { model.removeLocalRoot(root) }
                        }
                    }
                }
                if !model.jellyfinSources.isEmpty {
                    Divider()
                    ForEach(model.jellyfinSources) { source in
                        Button("扫描 Jellyfin：\(source.name)") {
                            model.startJellyfinScan(source)
                        }
                    }
                }
                if !model.plexSources.isEmpty {
                    ForEach(model.plexSources) { source in
                        Button("扫描 Plex：\(source.name)") {
                            Task { await model.scanPlexSource(source) }
                        }
                    }
                }
                if !model.smbSources.isEmpty {
                    ForEach(model.smbSources) { source in
                        Button("扫描 SMB：\(source.name)") {
                            Task { await model.scanSMBSource(source) }
                        }
                    }
                }
                if !model.sources.isEmpty {
                    Divider()
                    ForEach(model.sources) { source in
                        Button("扫描 WebDAV：\(source.name)") {
                            model.startWebDAVScan(source)
                        }
                    }
                }
            } label: {
                Label("扫描", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.elevated, in: Capsule())
                    .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

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
                showAddJellyfin = true
            } label: {
                Label("Jellyfin", systemImage: "play.tv")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.elevated, in: Capsule())
                    .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            Button {
                showAddPlex = true
            } label: {
                Label("Plex", systemImage: "play.rectangle.on.rectangle")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.elevated, in: Capsule())
                    .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            Button {
                showAddSMB = true
            } label: {
                Label("SMB", systemImage: "externaldrive.connected.to.line.below")
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
                model.showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 34, height: 34)
                    .background(Theme.elevated, in: Circle())
                    .overlay(Circle().stroke(Theme.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("设置")
        }
        .padding(.horizontal, 36)
        .padding(.top, 28)
        .padding(.bottom, 26)
    }

    private var visibleRecent: [PlaybackRecord] {
        ContinueWatching.visible(model.recent, limit: ContinueWatching.defaultLimit)
    }

    private var continueWatching: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("继续观看")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text("\(visibleRecent.count) 个继续观看")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                Button("查看全部") { showAllHistory = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                ForEach(visibleRecent) { record in
                    MediaCard(record: record, thumbnailURL: recentThumbnails[record.id]) {
                        model.resume(record)
                    } onRemove: {
                        model.removeRecent(record)
                    }
                }
            }
        }
        .task(id: visibleRecent.map(\.id).joined(separator: "|")) {
            var loaded: [String: URL] = [:]
            for record in visibleRecent {
                if let url = await model.recentThumbnailURL(for: record) {
                    loaded[record.id] = url
                } else if await model.loadRecentMetadata(for: record) != nil,
                          let url = await model.recentThumbnailURL(for: record) {
                    loaded[record.id] = url
                }
            }
            recentThumbnails = loaded
        }
        .sheet(isPresented: $showAllHistory) {
            RecentHistorySheet(records: ContinueWatching.history(model.recent)) { record in
                showAllHistory = false
                model.resume(record)
            } onRemove: { record in
                model.removeRecent(record)
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

    private var mediaLibrary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text("媒体库")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("\(model.libraryWorkCount) 个作品 · \(model.libraryEpisodeCount) 集")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondary)
                Spacer()
                Menu {
                    Section("类型") {
                        Button("全部") { model.libraryKindFilter = nil }
                        Button("电影") { model.libraryKindFilter = .movie }
                        Button("剧集") { model.libraryKindFilter = .series }
                    }
                    Section("观看状态") {
                        ForEach(LibraryWatchFilter.allCases) { filter in
                            Button(filter.label) { model.libraryWatchFilter = filter }
                        }
                    }
                    Section("画质") {
                        ForEach(LibraryResolutionFilter.allCases) { filter in
                            Button(filter.label) { model.libraryResolutionFilter = filter }
                        }
                    }
                    Divider()
                    Toggle("防剧透", isOn: $spoilerProtection)
                } label: {
                    Label("筛选", systemImage: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Menu {
                    ForEach(LibrarySort.allCases) { sort in
                        Button {
                            model.librarySort = sort
                        } label: {
                            if model.librarySort == sort {
                                Label(sort.label, systemImage: "checkmark")
                            } else {
                                Text(sort.label)
                            }
                        }
                    }
                } label: {
                    Label(model.librarySort.label, systemImage: "arrow.up.arrow.down")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                TextField("搜索片名", text: $model.librarySearch)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                if model.isScanningLibrary {
                    ProgressView().controlSize(.small)
                    Text("\(model.scanProgress) 项")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.secondary)
                    Button("取消") { model.cancelScan() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.red.opacity(0.85))
                }
            }

            if model.libraryWorks.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(Theme.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("还没建立媒体库")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text("扫描本地文件夹、Jellyfin 或 WebDAV 来源，按电影/剧/季/集浏览。")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Button("扫描文件夹…") { chooseFolderToScan() }
                        .buttonStyle(.bordered)
                }
                .padding(16)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)],
                    alignment: .leading,
                    spacing: 22
                ) {
                    ForEach(model.visibleLibraryGroups) { group in
                        LibraryCard(group: group)
                    }
                }
            }

            if let status = model.libraryStatus {
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
            }
        }
    }

    private func chooseFolderToScan() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "扫描"
        panel.message = "选择包含电影或剧集文件夹的目录"
        if panel.runModal() == .OK, let url = panel.url {
            model.startLocalScan(url)
        }
    }

    private var jellyfinSourcesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Jellyfin")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button {
                    showAddJellyfin = true
                } label: {
                    Label("添加", systemImage: "plus")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
            }
            ForEach(model.jellyfinSources) { source in
                HStack(spacing: 14) {
                    Image(systemName: "play.tv.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.warm)
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
                    Button("扫描") {
                        model.startJellyfinScan(source)
                    }
                    .buttonStyle(.bordered)
                    Button("浏览") { model.browseJellyfin(source) }
                        .buttonStyle(.bordered)
                    Button {
                        model.removeJellyfinSource(source)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(Theme.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("移除来源（不删除服务器内容）")
                }
                .padding(14)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
            }
        }
    }

    private var plexSourcesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Plex")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button {
                    showAddPlex = true
                } label: {
                    Label("添加", systemImage: "plus")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
            }
            ForEach(model.plexSources) { source in
                HStack(spacing: 14) {
                    Image(systemName: "play.rectangle.on.rectangle.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.warm)
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
                    Button("浏览") { model.browsePlex(source) }
                        .buttonStyle(.bordered)
                    Button("扫描") {
                        Task { await model.scanPlexSource(source) }
                    }
                    .buttonStyle(.bordered)
                    Button {
                        model.removePlexSource(source)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(Theme.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
            }
        }
    }

    private var smbSourcesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("SMB")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button {
                    showAddSMB = true
                } label: {
                    Label("添加", systemImage: "plus")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
            }
            ForEach(model.smbSources) { source in
                HStack(spacing: 14) {
                    Image(systemName: "externaldrive.connected.to.line.below")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.warm)
                        .frame(width: 38, height: 38)
                        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(source.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                        Text("smb://\(source.server):\(source.port)/\(source.share)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Button("扫描") { Task { await model.scanSMBSource(source) } }
                        .buttonStyle(.bordered)
                    Button {
                        model.removeSMBSource(source)
                    } label: {
                        Image(systemName: "trash").foregroundStyle(Theme.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
            }
        }
    }

    private var networkSources: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("网络来源").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.text)
                Spacer()
                Button { model.showAddSource = true } label: {
                    Label("添加", systemImage: "plus").font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(Theme.accent)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 340), spacing: 16)], alignment: .leading, spacing: 16) {
                ForEach(model.sources) { source in
                    Button { model.browse(source) } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "externaldrive.connected.to.line.below")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 40, height: 40)
                                    .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 9))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Theme.secondary)
                            }
                            Text(source.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                            Text(source.baseURL.absoluteString)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(Theme.secondary).lineLimit(1)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, minHeight: 124, alignment: .leading)
                        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("扫描") { model.startWebDAVScan(source) }
                        Button("浏览") { model.browse(source) }
                        Button("移除来源", role: .destructive) { model.removeSource(source) }
                    }
                }
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
    var thumbnailURL: URL? = nil
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
                    if let thumbnailURL {
                        AsyncImage(url: thumbnailURL) { phase in
                            if case .success(let image) = phase {
                                image.resizable().scaledToFill()
                            } else {
                                Color.clear
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                    }
                    LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
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
                            .padding(.trailing, 56)
                        Text(record.isFinished
                             ? "已看完"
                             : [record.episodeLabel, "\(Timecode.short(record.position)) / \(Timecode.short(record.duration))"]
                                .compactMap { $0 }.joined(separator: " · "))
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

struct RecentHistorySheet: View {
    let records: [PlaybackRecord]
    var onOpen: (PlaybackRecord) -> Void
    var onRemove: (PlaybackRecord) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("播放历史")
                        .font(.system(size: 18, weight: .semibold))
                    Text("\(records.count) 条记录")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondary)
                }
                Spacer()
                Button("关闭") { dismiss() }
            }
            .padding(18)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(records) { record in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(record.displayTitle ?? record.url.deletingPathExtension().lastPathComponent)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(2)
                                HStack(spacing: 8) {
                                    if record.isFinished {
                                        Text("已看完")
                                    } else {
                                        Text("\(Timecode.short(record.position)) / \(Timecode.short(record.duration))")
                                    }
                                    Text(record.lastPlayedAt.formatted(date: .abbreviated, time: .shortened))
                                }
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(Theme.secondary)
                            }
                            Spacer()
                            Button("播放") { onOpen(record) }
                                .buttonStyle(.plain)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                            Button {
                                onRemove(record)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        Divider().overlay(Theme.stroke.opacity(0.5))
                    }
                }
            }
        }
        .frame(width: 620, height: 520)
        .background(Theme.background)
    }
}

enum Timecode {
    static func long(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total / 60) % 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d 分钟", max(1, total / 60))
    }

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


struct AddPlexSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = "Plex"
    @State private var url = "http://127.0.0.1:32400"
    @State private var token = ""
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("添加 Plex")
                .font(.system(size: 18, weight: .semibold))
            Text("输入服务器地址与 X-Plex-Token；token 只保存在 Keychain。")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondary)
            Form {
                TextField("名称", text: $name)
                TextField("服务器地址", text: $url)
                SecureField("X-Plex-Token", text: $token)
            }
            .formStyle(.grouped)
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button(saving ? "添加中…" : "添加并扫描") {
                    saving = true
                    Task {
                        let ok = await model.addPlexSource(name: name, urlText: url, token: token)
                        saving = false
                        if ok { dismiss() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(saving || token.isEmpty || url.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 520)
        .background(Theme.background)
    }
}


struct AddSMBSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = "SMB"
    @State private var server = "127.0.0.1"
    @State private var port = "445"
    @State private var share = ""
    @State private var username = ""
    @State private var password = ""
    @State private var basePath = ""
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("添加 SMB")
                .font(.system(size: 18, weight: .semibold))
            Text("SMB2/3 来源；密码只保存在 Keychain。首次播放会把文件缓存到本地。")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondary)
            Form {
                TextField("名称", text: $name)
                TextField("服务器", text: $server)
                TextField("端口", text: $port)
                TextField("共享名", text: $share)
                TextField("用户名", text: $username)
                SecureField("密码", text: $password)
                TextField("子目录（可选）", text: $basePath)
            }
            .formStyle(.grouped)
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button(saving ? "连接中…" : "连接并扫描") {
                    saving = true
                    Task {
                        let source = await model.addSMBSource(
                            name: name,
                            server: server,
                            port: Int(port) ?? 445,
                            share: share,
                            username: username,
                            password: password,
                            basePath: basePath
                        )
                        saving = false
                        if source != nil { dismiss() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(saving || share.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 540)
        .background(Theme.background)
    }
}
