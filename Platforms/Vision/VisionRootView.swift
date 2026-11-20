import AVKit
import OpenFuseData
import SwiftUI

struct VisionRootView: View {
    @EnvironmentObject private var model: MobileLibraryModel
    @State private var selectedWork: LibraryWork?

    var body: some View {
        NavigationSplitView {
            List(model.groups, selection: Binding(
                get: { selectedWork?.id },
                set: { id in selectedWork = model.groups.first { $0.primary.id == id }?.primary }
            )) { group in
                HStack(spacing: 10) {
                    VisionPoster(work: group.primary)
                        .frame(width: 48, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.primary.title).font(.headline)
                        Text(group.primary.kind == .movie ? "电影" : "\(group.primary.episodeCount) 集")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tag(group.primary.id)
            }
            .navigationTitle("OpenFuse")
            .overlay {
                if model.groups.isEmpty { ContentUnavailableView("还没有媒体", systemImage: "rectangle.stack") }
            }
        } detail: {
            if let selectedWork {
                VisionDetailView(work: selectedWork)
                    .environmentObject(model)
            } else {
                ContentUnavailableView(
                    "选择一部作品",
                    systemImage: "play.rectangle",
                    description: Text("Vision Pro 首版复用本地示例与媒体库；空间布局与沉浸式播放待后续。")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

private struct VisionPoster: View {
    let work: LibraryWork

    var body: some View {
        Group {
            if let parsed = PosterRef.parse(work.poster), parsed.kind == "file",
               let image = UIImage(contentsOfFile: parsed.value) {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let parsed = PosterRef.parse(work.poster), parsed.kind == "remote",
                      let url = URL(string: parsed.value) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase { image.resizable().scaledToFill() } else { placeholder }
                }
            } else {
                placeholder
            }
        }
        .clipped()
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.10, green: 0.20, blue: 0.28), Color(red: 0.08, green: 0.08, blue: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: work.kind == .movie ? "film" : "tv")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

private struct VisionDetailView: View {
    @EnvironmentObject private var model: MobileLibraryModel
    let work: LibraryWork
    @State private var item: MobilePlaybackItem?

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 28) {
                VisionPoster(work: work)
                    .frame(width: 220, height: 330)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 12) {
                    Text(work.title)
                        .font(.largeTitle.weight(.bold))
                    HStack(spacing: 8) {
                        if let year = work.year { Text(String(year)) }
                        Text(work.kind == .movie ? "电影" : "剧集")
                        Text(work.sourceKind)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    if let overview = work.overview {
                        Text(overview)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(6)
                    }
                    if let item = model.playbackItem(for: work) {
                        Button {
                            self.item = item
                        } label: {
                            Label(item.resumePosition == nil ? "播放" : "从 \(Int(item.resumePosition ?? 0)) 秒继续", systemImage: "play.fill")
                                .font(.headline)
                                .padding(.horizontal, 22)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Text("该来源在 Vision Pro 首版不可直接播放；远程/服务器播放待接入。")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
            }
            .padding(36)
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(item: $item) { item in
            VisionPlayerView(item: item)
                .environmentObject(model)
        }
    }
}

private struct VisionPlayerView: View {
    @EnvironmentObject private var model: MobileLibraryModel
    @Environment(\.dismiss) private var dismiss
    let item: MobilePlaybackItem
    @State private var player: AVPlayer?
    @State private var resourceLoader: AuthenticatedAssetLoader?
    @State private var observer: Any?
    @State private var duration: TimeInterval = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player).ignoresSafeArea()
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
            .padding(24)
        }
        .onAppear {
            let (player, loader) = model.makePlayer(for: item)
            self.player = player
            self.resourceLoader = loader
            observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { time in
                if time.seconds.isFinite, time.seconds > 0 { duration = max(duration, time.seconds) }
            }
            Task {
                let asset = AVURLAsset(url: item.url)
                if let loaded = try? await asset.load(.duration) { duration = loaded.seconds }
                if let resume = item.resumePosition {
                    await player.seek(to: CMTime(seconds: resume, preferredTimescale: 600))
                }
                player.play()
            }
        }
        .onDisappear {
            if let player {
                let position = player.currentTime().seconds
                let total = duration > 0 ? duration : (player.currentItem?.duration.seconds ?? 0)
                if position.isFinite, total.isFinite, total > 0 {
                    let finished = ResumePolicy.isFinished(position: position, duration: total)
                    model.recordProgress(item: item, duration: total, position: finished ? 0 : position, finished: finished)
                }
                player.pause()
                if let observer { player.removeTimeObserver(observer) }
            }
            resourceLoader = nil
        }
    }
}
