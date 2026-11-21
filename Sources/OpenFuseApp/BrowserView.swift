import AppKit
import OpenFuseCore
import SwiftUI

struct WebDAVBrowserView: View {
    @EnvironmentObject private var model: AppModel
    let source: WebDAVSource

    @State private var nav = RemotePathState()
    @State private var entries: [RemoteEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var opening: String?
    /// Identifies the in-flight listing so a slow response for a directory the
    /// user already left cannot overwrite the newer one.
    @State private var loadToken = UUID()
    @State private var directoryMetadata: DirectoryMetadata?
    @State private var metadataLoading = false
    @State private var showMetadataDetail = false
    @State private var showMatchEditor = false
    @State private var matchTitle = ""
    @State private var matchYear = ""

    private var pathStack: [String] { nav.stack }
    private var currentPath: String { nav.path }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.stroke)
            content
        }
        .background(Theme.background.ignoresSafeArea())
        .onAppear {
            nav = RemotePathState(stack: model.webdavPath(for: source))
            model.setWebDAVPath(nav.stack, for: source)
        }
        .onChange(of: nav.stack) { _, newValue in
            model.setWebDAVPath(newValue, for: source)
        }
        .task(id: currentPath) {
            await load(path: currentPath)
        }
        .sheet(isPresented: $showMatchEditor) {
            matchEditor
        }
        .overlay {
            if showMetadataDetail, let directoryMetadata {
                ZStack {
                    Color.black.opacity(0.28)
                        .ignoresSafeArea()
                        .onTapGesture { showMetadataDetail = false }
                    DirectoryDetailPanel(
                        metadata: directoryMetadata,
                        onClose: { showMetadataDetail = false }
                    )
                    .frame(width: 680, height: 600)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button {
                // Going back only shrinks the canonical stack, so it is always
                // safe even while a listing loads; `.task(id:)` cancels the old
                // request and the load token discards a late response.
                if !nav.up() {
                    model.route = .home
                }
            } label: {
                Image(systemName: nav.isRoot ? "xmark" : "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(Theme.elevated, in: Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(source.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(source.baseURL.absoluteString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
            }

            HStack(spacing: 6) {
                Button {
                    nav.reset()
                } label: {
                    Text(source.name)
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondary)

                ForEach(Array(pathStack.indices.dropFirst()), id: \.self) { index in
                    Text("/").foregroundStyle(Theme.secondary.opacity(0.6))
                    Button {
                        nav.jump(to: index)
                    } label: {
                        Text(RemotePath.displayName(pathStack[index]))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(index == pathStack.count - 1 ? Theme.text : Theme.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.panel, in: Capsule())
            .lineLimit(1)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)

            Button {
                guard !isLoading else { return }
                Task { await load(path: currentPath) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(Theme.elevated, in: Circle())
            }
            .buttonStyle(.plain)
            .help("刷新")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && entries.isEmpty {
            Spacer()
            ProgressView("正在读取目录…")
                .foregroundStyle(Theme.secondary)
            Spacer()
        } else if let errorMessage, entries.isEmpty {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.secondary)
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                Button("重试") {
                    Task { await load(path: currentPath) }
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        } else if entries.isEmpty {
            Spacer()
            Text("这个目录是空的")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
            Spacer()
        } else {
            VStack(spacing: 0) {
                if let metadata = directoryMetadata {
                    DirectoryMetadataHeader(
                        metadata: metadata,
                        loading: metadataLoading,
                        onDetail: { showMetadataDetail = true },
                        onRefresh: { openMatchEditor() }
                    )
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 6)
                } else if metadataLoading, hasVideos {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在匹配影视资料…")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                } else if hasVideos {
                    HStack {
                        Text("未匹配到影视资料，单击仍可播放")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondary)
                        Spacer()
                        Button("重新匹配") { openMatchEditor() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 8)
                }

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            row(entry)
                            Divider().overlay(Theme.stroke.opacity(0.5))
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func row(_ entry: RemoteEntry) -> some View {
        Button {
            if entry.isDirectory {
                openFolder(entry)
            } else if entry.isPlayableVideo {
                opening = entry.path
                Task {
                    await model.openRemote(source: source, entry: entry, siblings: entries)
                    opening = nil
                }
            }
        } label: {
            HStack(spacing: 12) {
                if entry.isPlayableVideo, let episode = metadataEpisode(for: entry),
                   let still = episode.stillURL ?? directoryMetadata?.work.posterURL {
                    AsyncImage(url: URL(string: still)) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 5).fill(Theme.elevated)
                    }
                    .frame(width: 80, height: 45)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    entryIcon(entry)
                }
                VStack(alignment: .leading, spacing: 3) {
                    if let episode = metadataEpisode(for: entry) {
                        Text("\(episode.label) — \(episode.title)")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                    } else if entry.isPlayableVideo, let work = metadataWork(for: entry) {
                        Text(work.title)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                    } else {
                        Text(entry.name)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(entry.isDirectory || entry.isPlayableVideo ? Theme.text : Theme.secondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 8) {
                        if entry.isDirectory {
                            Text("文件夹")
                        } else if let episode = metadataEpisode(for: entry), let overview = episode.overview, !overview.isEmpty {
                            Text(overview).lineLimit(1)
                            if let resolution = VideoNaming.parse(fileName: entry.name, parentFolder: currentPath).resolution {
                                Text(resolution)
                            }
                        } else if let work = metadataWork(for: entry), let overview = work.overview, !overview.isEmpty {
                            Text(overview).lineLimit(1)
                            if let year = work.year { Text(String(year)) }
                        } else {
                            Text(byteString(entry.size))
                            if let modified = entry.modifiedAt {
                                Text(modified.formatted(date: .abbreviated, time: .shortened))
                            }
                        }
                        if !entry.isDirectory && !entry.isPlayableVideo {
                            Text(entry.fileExtension.uppercased())
                        }
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.secondary.opacity(0.85))
                }
                Spacer()
                if opening == entry.path {
                    ProgressView().controlSize(.small)
                } else if entry.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                } else if entry.isPlayableVideo {
                    Image(systemName: "play.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading || (!entry.isDirectory && !entry.isPlayableVideo))
        .opacity(isLoading && entry.isDirectory ? 0.55 : 1)
    }

    /// Entering a folder is a single canonical transition. Clicks that land
    /// while the previous PROPFIND is still running are dropped, and repeating
    /// the same path is a no-op, so the breadcrumb can never accumulate
    /// duplicate segments.
    private func openFolder(_ entry: RemoteEntry) {
        guard nav.enter(entry.path, busy: isLoading || opening != nil) else { return }
    }

    private func byteString(_ size: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private func load(path: String) async {
        let token = UUID()
        loadToken = token
        isLoading = true
        errorMessage = nil
        do {
            let listing = try await model.loadDirectory(source: source, path: path)
            guard loadToken == token else { return }
            entries = listing
        } catch {
            guard loadToken == token else { return }
            errorMessage = error.localizedDescription
            entries = []
        }
        guard loadToken == token else { return }
        isLoading = false
        directoryMetadata = nil
        if hasVideos {
            metadataLoading = true
            Task {
                let metadata = await model.loadDirectoryMetadata(source: source, path: path, entries: entries)
                guard loadToken == token else { return }
                directoryMetadata = metadata
                metadataLoading = false
                if let metadata,
                   ProcessInfo.processInfo.environment["OPENFUSE_DEBUG_METADATA"] == "1" {
                    let dir = AppModel.shared.acceptanceDirectory()
                    if let data = try? JSONEncoder.openFuse.encode(metadata) {
                        try? data.write(to: dir.appendingPathComponent("metadata.json"), options: .atomic)
                    }
                }
                if metadata != nil,
                   ProcessInfo.processInfo.environment["OPENFUSE_SHOW_METADATA_DETAIL"] == "1" {
                    showMetadataDetail = true
                }
            }
        } else {
            metadataLoading = false
        }
    }

    private var hasVideos: Bool {
        entries.contains { !$0.isDirectory && $0.isPlayableVideo }
    }

    private func metadataWork(for entry: RemoteEntry) -> DirectoryWorkMetadata? {
        guard let directoryMetadata else { return nil }
        if directoryMetadata.movieWorks?.isEmpty == false {
            return directoryMetadata.work(for: entry.path)
        }
        return nil
    }

    private func metadataEpisode(for entry: RemoteEntry) -> DirectoryEpisodeMetadata? {
        guard entry.isPlayableVideo, let directoryMetadata else { return nil }
        let parsed = VideoNaming.parse(fileName: entry.name, parentFolder: currentPath)
        guard let season = parsed.season, let episode = parsed.episode else { return nil }
        return directoryMetadata.episode(season: season, number: episode)
    }

    private func openMatchEditor() {
        matchTitle = directoryMetadata?.work.title ?? (currentPath as NSString).lastPathComponent
        matchYear = directoryMetadata?.work.year.map(String.init) ?? ""
        showMatchEditor = true
    }

    private var matchEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("重新匹配影视资料")
                .font(.system(size: 17, weight: .semibold))
            Text("输入正确的片名与年份；保存后会清除本目录缓存并重新匹配，选择会按来源和目录持久化。")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("片名", text: $matchTitle)
            TextField("年份（可选）", text: $matchYear)
            HStack {
                Spacer()
                Button("取消") { showMatchEditor = false }
                Button("保存并重新匹配") {
                    let year = Int(matchYear.trimmingCharacters(in: .whitespaces))
                    model.setDirectoryMatch(source: source, path: currentPath, title: matchTitle, year: year)
                    showMatchEditor = false
                    Task { await refreshMetadata() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(matchTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
        .background(Theme.background)
    }

    private func refreshMetadata() async {
        metadataLoading = true
        directoryMetadata = await model.refreshDirectoryMetadata(source: source, path: currentPath, entries: entries)
        metadataLoading = false
    }
}

private struct DirectoryMetadataHeader: View {
    let metadata: DirectoryMetadata
    let loading: Bool
    var onDetail: () -> Void
    var onRefresh: () -> Void

    var body: some View {
        let multiMovie = (metadata.movieWorks?.count ?? 0) > 1
        HStack(alignment: .top, spacing: 14) {
            if !multiMovie, let poster = metadata.work.posterURL, let url = URL(string: poster) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8).fill(Theme.elevated)
                }
                .frame(width: 62, height: 93)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(multiMovie ? "影片文件夹" : metadata.work.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    if !multiMovie, let year = metadata.work.year {
                        Text(String(year))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondary)
                    }
                }
                if !multiMovie, !metadata.work.allRatings.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(metadata.work.allRatings, id: \.self) { rating in
                            Text(rating)
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Theme.elevated, in: Capsule())
                                .foregroundStyle(Theme.text)
                        }
                    }
                }
                if !multiMovie, let overview = metadata.work.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 10) {
                    if !multiMovie {
                        Button(metadata.work.kind == .movie ? "影片详情" : "剧集详情") { onDetail() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    }
                    Button {
                        onRefresh()
                    } label: {
                        if loading { ProgressView().controlSize(.small) } else { Text("刷新资料") }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                    .disabled(loading)
                    Spacer()
                    Text("\(multiMovie ? "\(metadata.movieWorks?.count ?? 0) 部影片" : (metadata.work.kind == .movie ? "影片" : "剧集")) · \(metadata.matchNote ?? metadata.sourceLabel)")
                        .font(.system(size: 10))
                        .foregroundStyle(metadata.matchState == "networkFailure" || metadata.matchState == "noCandidates"
                                         ? Color.orange.opacity(0.85)
                                         : Theme.secondary.opacity(0.7))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.stroke, lineWidth: 1))
    }
}

@ViewBuilder
private func entryIcon(_ entry: RemoteEntry) -> some View {
    if entry.isDirectory {
        Image(systemName: "folder.fill").foregroundStyle(Theme.accent)
    } else if entry.isPlayableVideo {
        Image(systemName: "film.fill").foregroundStyle(Theme.warm)
    } else if SubtitleCatalog.subtitleExtensions.contains(entry.fileExtension) {
        Image(systemName: "captions.bubble.fill").foregroundStyle(Theme.secondary)
    } else {
        Image(systemName: "doc.fill").foregroundStyle(Theme.secondary)
    }
}

struct AddSourceSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var url = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var sessionOnly = CredentialStore.defaultMode == .session

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("添加 WebDAV 来源")
                        .font(.system(size: 18, weight: .semibold))
                    Text("OpenList、Nextcloud、群晖等提供 WebDAV 的服务均可。密码默认存入本机 Keychain，不会写入明文文件。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }
            }

            Form {
                TextField("名称", text: $name, prompt: Text("例如：OpenList"))
                TextField("服务器地址", text: $url, prompt: Text("https://example.com:5244/dav/"))
                    .textContentType(.URL)
                TextField("用户名", text: $username)
                SecureField("密码", text: $password)
                Toggle("仅本次会话（不写入 Keychain，退出后需重新输入）", isOn: $sessionOnly)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.red)
            }

            HStack {
                Text("示例：OpenList 的 WebDAV 根路径通常是 /dav/，百度网盘目录会按原结构显示。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                if isBusy {
                    ProgressView().controlSize(.small)
                }
                Button("连接并保存") {
                    Task { await submit() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isBusy || url.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 560)
        .background(Theme.background)
    }

    private func submit() async {
        isBusy = true
        errorMessage = nil
        let source = await model.addSource(
            name: name,
            urlText: url,
            username: username,
            password: password,
            rememberInKeychain: !sessionOnly
        )
        isBusy = false
        if source != nil {
            dismiss()
        } else {
            errorMessage = model.statusMessage ?? "连接失败"
        }
    }
}


private struct DirectoryDetailPanel: View {
    let metadata: DirectoryMetadata
    var onClose: () -> Void

    var body: some View {
        let multiMovie = (metadata.movieWorks?.count ?? 0) > 1
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(metadata.work.kind == .movie ? "影片详情" : "剧集详情")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("关闭") { onClose() }
            }
            .padding(18)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        if let poster = metadata.work.posterURL, let url = URL(string: poster) {
                            AsyncImage(url: url) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 10).fill(Theme.elevated)
                            }
                            .frame(width: 120, height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text(metadata.work.title)
                                .font(.system(size: 20, weight: .semibold))
                            HStack(spacing: 8) {
                                if let year = metadata.work.year {
                                    Text(String(year)).foregroundStyle(Theme.secondary)
                                }
                                Text(metadata.work.kind == .movie ? "电影" : "电视剧")
                                    .foregroundStyle(Theme.secondary)
                            }
                            .font(.system(size: 12))
                            if !multiMovie, !metadata.work.allRatings.isEmpty {
                                HStack(spacing: 6) {
                                    ForEach(metadata.work.allRatings, id: \.self) { rating in
                                        Text(rating)
                                            .font(.system(size: 10.5, weight: .semibold))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Theme.elevated, in: Capsule())
                                    }
                                }
                            }
                            if let imdbID = metadata.work.imdbID {
                                Text("IMDb ID \(imdbID)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(Theme.secondary.opacity(0.7))
                            }
                            if !multiMovie, let overview = metadata.work.overview, !overview.isEmpty {
                                Text(overview)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }

                    if !metadata.episodes.isEmpty {
                        Text("剧集")
                            .font(.system(size: 14, weight: .semibold))
                        LazyVStack(spacing: 10) {
                            ForEach(metadata.episodes.sorted { ($0.season, $0.number) < ($1.season, $1.number) }, id: \.key) { episode in
                                HStack(alignment: .top, spacing: 10) {
                                    if let still = episode.stillURL, let url = URL(string: still) {
                                        AsyncImage(url: url) { image in
                                            image.resizable().aspectRatio(contentMode: .fill)
                                        } placeholder: {
                                            RoundedRectangle(cornerRadius: 6).fill(Theme.elevated)
                                        }
                                        .frame(width: 96, height: 54)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("\(episode.label) — \(episode.title)")
                                            .font(.system(size: 12.5, weight: .medium))
                                        if let overview = episode.overview, !overview.isEmpty {
                                            Text(overview)
                                                .font(.system(size: 10.5))
                                                .foregroundStyle(Theme.secondary)
                                                .lineLimit(2)
                                        }
                                        if let rating = episode.rating {
                                            Text("TMDB \(String(format: "%.1f", rating))/10")
                                                .font(.system(size: 9.5, weight: .semibold))
                                                .foregroundStyle(Theme.secondary)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                }
                .padding(18)
            }
        }
        .background(Theme.background)
    }
}
