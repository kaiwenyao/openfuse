import AVKit
import OpenFuseData
import SwiftUI
import UniformTypeIdentifiers

struct MobileRootView: View {
    @EnvironmentObject private var model: MobileLibraryModel
    @State private var showImporter = false
    @State private var showAbout = false
    @State private var showSources = false

    var body: some View {
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSources = true
                    } label: {
                        Label("媒体来源", systemImage: "server.rack")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showImporter = true
                    } label: {
                        Label("导入视频", systemImage: "square.and.arrow.down")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAbout = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
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
            .navigationDestination(for: LibraryWork.self) { work in
                MobileDetailView(work: work)
                    .environmentObject(model)
            }
        }
        .tint(.cyan)
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
            Text("AVPlayer · 本地 MP4/MOV · Jellyfin/WebDAV 可扫描 · 远程播放/MKV/字幕待接入")
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
                        if let item = model.playbackItem(for: currentWork) {
                            Button {
                                selectedItem = item
                            } label: {
                                Label(item.resumePosition == nil ? "播放" : "从 \(Int(item.resumePosition ?? 0)) 秒继续", systemImage: "play.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 10)
                                    .background(.cyan, in: Capsule())
                                    .foregroundStyle(.black)
                            }
                            .buttonStyle(.plain)
                        } else if currentWork.sourceKind != "local" {
                            Text("服务器来源已入库；移动端远程播放需要转码/鉴权代理，待接入。")
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
                                if let item = model.playbackItem(work: currentWork, episode: episode) {
                                    Button {
                                        selectedItem = item
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

