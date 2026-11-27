import AVKit
import OpenFuseData
import SwiftUI
import UniformTypeIdentifiers

struct MobileRootView: View {
    @EnvironmentObject private var model: MobileLibraryModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedWorkID: String?
    @State private var showImporter = false
    @State private var showAbout = false
    @State private var showSources = false
    @State private var autoplayItem: MobilePlaybackItem?

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                splitView
            } else {
                compactView
            }
        }
        .tint(.cyan)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                model.importVideo(from: url)
            }
        }
        .sheet(isPresented: $showAbout) {
            MobileAboutView()
        }
        .sheet(isPresented: $showSources) {
            MobileSourcesView()
                .environmentObject(model)
        }
        .task {
            MPVProbe.runIfRequested()
            if let raw = ProcessInfo.processInfo.environment["OPENFUSE_TEST_MPV_URL"], let url = URL(string: raw) {
                var headers: [String: String] = [:]
                if let header = ProcessInfo.processInfo.environment["OPENFUSE_TEST_MPV_HEADER"] {
                    let parts = header.split(separator: ":", maxSplits: 1).map(String.init)
                    if parts.count == 2 { headers[parts[0]] = parts[1].trimmingCharacters(in: .whitespaces) }
                }
                var sidecars: [SubtitleTrack] = []
                for key in ["OPENFUSE_TEST_MPV_SUB1", "OPENFUSE_TEST_MPV_SUB2"] {
                    if let raw = ProcessInfo.processInfo.environment[key], let subURL = URL(string: raw) {
                        let name = key.hasSuffix("1") ? "中文（简体） (ASS)" : "中文（繁體） (ASS)"
                        let language = key.hasSuffix("1") ? "zh-Hans" : "zh-Hant"
                        sidecars.append(SubtitleTrack(
                            id: "test-sub-\(key)", displayName: name, language: language,
                            format: SubtitleFormat(fileExtension: subURL.pathExtension),
                            source: .external, url: subURL
                        ))
                    }
                }
                autoplayItem = MobilePlaybackItem(
                    url: url,
                    title: ProcessInfo.processInfo.environment["OPENFUSE_TEST_MPV_TITLE"] ?? "WebDAV MKV",
                    subtitle: nil,
                    fingerprint: MediaFingerprint(path: url.absoluteString, fileSize: 0, modifiedAt: nil),
                    resumePosition: nil,
                    sourceKind: "webdav",
                    sourceID: "test",
                    remotePath: nil,
                    remoteURL: url.absoluteString,
                    httpHeaders: headers,
                    sidecarSubtitles: sidecars
                )
                return
            }
            if ProcessInfo.processInfo.environment["OPENFUSE_BROWSE_ACCEPTANCE"] == "1" {
                showSources = true
                return
            }
            await model.bootstrapTestSourcesIfRequested()
            guard model.autoplaySample, autoplayItem == nil else { return }
            let preferred = ProcessInfo.processInfo.environment["OPENFUSE_AUTOPLAY_SOURCE"] ?? ""
            var candidates = model.groups.filter {
                preferred.isEmpty ? $0.primary.sourceKind != "local" : $0.primary.sourceKind == preferred
            }
            if let title = ProcessInfo.processInfo.environment["OPENFUSE_AUTOPLAY_TITLE"], !title.isEmpty {
                candidates = candidates.filter { group in
                    group.works.contains { $0.title.localizedCaseInsensitiveContains(title) }
                }
            }
            guard let work = (candidates.first ?? model.groups.first)?.primary else { return }
            // Optional episode selector for acceptance runs: a title substring
            // ("初始的街道") or a 1-based episode number within the work.
            var chosenEpisode: LibraryEpisode?
            if let query = ProcessInfo.processInfo.environment["OPENFUSE_AUTOPLAY_EPISODE"], !query.isEmpty {
                let episodes = model.episodes(for: work.id)
                if let index = Int(query), index > 0, index <= episodes.count {
                    chosenEpisode = episodes[index - 1]
                } else {
                    chosenEpisode = episodes.first { episode in
                        episode.title.localizedCaseInsensitiveContains(query)
                            || (episode.episodeLabel ?? "").localizedCaseInsensitiveContains(query)
                    }
                }
            }
            autoplayItem = await model.playbackItemAsync(for: work, episode: chosenEpisode)

        }
        .fullScreenCover(item: $autoplayItem) { item in
            MobilePlayerView(item: item)
                .environmentObject(model)
        }
        .fullScreenCover(item: Binding(
            get: { model.browserPlayback },
            set: { model.browserPlayback = $0 }
        )) { item in
            MobilePlayerView(item: item)
                .environmentObject(model)
        }
    }

    private var compactView: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if !model.recent.isEmpty {
                        recentSection
                    }
                    librarySection
                    if let status = model.status {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    footer
                }
                .padding(20)
            }
            .background(Color.black.ignoresSafeArea())
            .toolbar { libraryToolbar }
            .navigationDestination(for: LibraryWork.self) { work in
                MobileDetailView(work: work)
                    .environmentObject(model)
            }
        }
    }

    private var splitView: some View {
        NavigationSplitView {
            List(selection: $selectedWorkID) {
                ForEach(model.groups) { group in
                    HStack(spacing: 10) {
                        MobilePoster(work: group.primary)
                            .frame(width: 42, height: 63)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.primary.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                            HStack(spacing: 5) {
                                if let year = group.primary.year { Text(String(year)) }
                                Text(group.primary.kind == .movie ? "电影" : "\(group.primary.episodeCount) 集")
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .tag(group.primary.id)
                }
            }
            .navigationTitle("OpenFuse")
            .toolbar { libraryToolbar }
            .overlay {
                if model.groups.isEmpty {
                    ContentUnavailableView("还没有媒体", systemImage: "rectangle.stack")
                }
            }
        } detail: {
            if let selectedWorkID, let work = model.works.first(where: { $0.id == selectedWorkID }) {
                MobileDetailView(work: work)
                    .environmentObject(model)
            } else {
                ContentUnavailableView(
                    "选择一部作品",
                    systemImage: "play.rectangle",
                    description: Text("从左侧媒体库选择电影或剧集。")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ToolbarContentBuilder
    private var libraryToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { showSources = true } label: {
                Label("媒体来源", systemImage: "server.rack")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showImporter = true } label: {
                Label("导入视频", systemImage: "square.and.arrow.down")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showAbout = true } label: {
                Image(systemName: "gearshape")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.cyan)
                Text("OpenFuse")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            Text("iPhone / iPad 首版 · 本地 MP4 播放与续播")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("继续观看")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(model.recent) { record in
                        if let work = model.works.first(where: { $0.title == record.displayTitle }) {
                            NavigationLink(value: work) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(record.displayTitle ?? "继续观看")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Text(record.isFinished ? "已看完" : "\(Int(record.position)) 秒")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 170, alignment: .leading)
                                .padding(12)
                                .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                }
            }
        }
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("媒体库")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text(model.countsText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if model.groups.isEmpty {
                ContentUnavailableView(
                    "还没有媒体",
                    systemImage: "rectangle.stack.badge.plus",
                    description: Text("导入 MP4/MOV，或等待后续版本接入 Jellyfin/WebDAV。")
                )
                .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 210), spacing: 16)], spacing: 20) {
                    ForEach(model.groups) { group in
                        NavigationLink(value: group.primary) {
                            MobileLibraryCard(group: group)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("移动端首版")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("libmpv 直放 MKV（HEVC / 外挂 ASS / E-AC-3 下混）· AVPlayer 播 HLS 与 MP4 · 字幕与音轨可在播放器里切换")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 10)
    }
}

private struct MobileLibraryCard: View {
    @EnvironmentObject private var model: MobileLibraryModel
    let group: LibraryGroup

    private var progress: Double? { model.progress(for: group.primary) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            MobilePoster(work: group.primary)
                .aspectRatio(2 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .bottom) {
                    if let progress {
                        GeometryReader { geo in
                            Rectangle()
                                .fill(.cyan)
                                .frame(width: geo.size.width * progress, height: 3)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                    }
                }
            Text(group.primary.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
            HStack(spacing: 5) {
                if let year = group.primary.year { Text(String(year)) }
                Text(group.primary.kind == .movie ? "电影" : "\(group.primary.episodeCount) 集")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

private struct MobilePoster: View {
    @EnvironmentObject private var model: MobileLibraryModel
    let work: LibraryWork

    var body: some View {
        Group {
            if let parsed = PosterRef.parse(work.poster), parsed.kind == "file",
               let image = UIImage(contentsOfFile: parsed.value) {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let url = model.posterURL(for: work) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else if let parsed = PosterRef.parse(work.poster), parsed.kind == "remote",
                      let url = URL(string: parsed.value) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipped()
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.10, green: 0.20, blue: 0.28), Color(red: 0.10, green: 0.10, blue: 0.14)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 8) {
                Image(systemName: work.kind == .movie ? "film" : "tv")
                    .font(.title2)
                Text(work.title)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .foregroundStyle(.white.opacity(0.8))
        }
    }
}

struct MobileDetailView: View {
    @EnvironmentObject private var model: MobileLibraryModel
    let work: LibraryWork
    @State private var selectedItem: MobilePlaybackItem?
    @State private var isLoadingRemote = false
    @State private var isLoadingItem = false
    @State private var remoteError: String?

    private var currentWork: LibraryWork { model.works.first { $0.id == work.id } ?? work }
    private var episodes: [LibraryEpisode] { model.episodes(for: currentWork.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    MobilePoster(work: currentWork)
                        .frame(width: 150, height: 225)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 8) {
                        Text(currentWork.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                        HStack(spacing: 8) {
                            if let year = currentWork.year { Text(String(year)) }
                            Text(currentWork.kind == .movie ? "电影" : "剧集")
                            Text(currentWork.sourceKind == "jellyfin" ? "Jellyfin" : (currentWork.sourceKind == "webdav" ? "WebDAV" : "本地"))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        if let overview = currentWork.overview, !overview.isEmpty {
                            Text(overview)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(5)
                        }
                        if model.playbackItem(for: currentWork) != nil || currentWork.sourceKind != "local" {
                            Button {
                                isLoadingItem = true
                                Task {
                                    selectedItem = await model.playbackItemAsync(for: currentWork)
                                    isLoadingItem = false
                                }
                            } label: {
                                let resume = model.resumePosition(for: currentWork)
                                Label(resume == nil ? "播放" : "从 \(Int(resume ?? 0)) 秒继续", systemImage: "play.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 10)
                                    .background(.cyan, in: Capsule())
                                    .foregroundStyle(.black)
                            }
                            .buttonStyle(.plain)
                        } else if currentWork.sourceKind == "jellyfin" {
                            Button {
                                isLoadingRemote = true
                                remoteError = nil
                                Task {
                                    if let item = await model.remotePlaybackItem(for: currentWork) {
                                        selectedItem = item
                                    } else {
                                        remoteError = "Jellyfin 未返回可播放流；检查服务器 HLS 转码或 libmpv。"
                                    }
                                    isLoadingRemote = false
                                }
                            } label: {
                                Label(isLoadingRemote ? "正在获取…" : "播放服务器版本", systemImage: "play.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 10)
                                    .background(.cyan, in: Capsule())
                                    .foregroundStyle(.black)
                            }
                            .buttonStyle(.plain)
                            .disabled(isLoadingRemote)
                            if let remoteError {
                                Text(remoteError).font(.caption).foregroundStyle(.orange)
                            }
                        } else if currentWork.sourceKind != "local" {
                            Text("WebDAV 仅 MP4/MOV 可播，MKV 待 libmpv。")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else {
                            Text("该条目没有 AVPlayer 可播放的本地文件")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                }

                if currentWork.kind == .series {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("剧集")
                            .font(.headline)
                            .foregroundStyle(.white)
                        ForEach(episodes) { episode in
                            HStack {
                                Text(episode.episodeLabel ?? "—")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                Text(episode.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                                Spacer()
                                if model.playbackItem(work: currentWork, episode: episode) != nil || currentWork.sourceKind != "local" {
                                    Button {
                                        isLoadingItem = true
                                        Task {
                                            selectedItem = await model.playbackItemAsync(for: currentWork, episode: episode)
                                            isLoadingItem = false
                                        }
                                    } label: {
                                        Image(systemName: "play.circle.fill")
                                            .font(.title3)
                                            .foregroundStyle(.cyan)
                                    }
                                }
                            }
                            .padding(10)
                            .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(currentWork.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedItem) { item in
            MobilePlayerView(item: item)
                .environmentObject(model)
        }
    }
}

