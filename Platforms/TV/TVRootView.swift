import AVKit
import OpenFuseData
import SwiftUI

struct TVRootView: View {
    @EnvironmentObject private var model: MobileLibraryModel
    @State private var selectedItem: MobilePlaybackItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Image(systemName: "play.rectangle.fill")
                            .foregroundStyle(.cyan)
                        Text("OpenFuse")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                        Spacer()
                        Text(model.countsText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if model.groups.isEmpty {
                        ContentUnavailableView(
                            "还没有媒体",
                            systemImage: "rectangle.stack.badge.plus",
                            description: Text("在 iPhone/iPad 版导入内容，或等待 iCloud 同步。")
                        )
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 320), spacing: 28)], spacing: 32) {
                            ForEach(model.groups) { group in
                                Button {
                                    selectedItem = model.playbackItem(for: group.primary)
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        TVPoster(work: group.primary)
                                            .aspectRatio(2 / 3, contentMode: .fit)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        Text(group.primary.title)
                                            .font(.headline)
                                            .lineLimit(2)
                                        Text(group.primary.kind == .movie ? "电影" : "\(group.primary.episodeCount) 集")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.card)
                            }
                        }
                    }
                    Text("Apple TV 首版：本地示例 MP4；服务器来源与 MKV/字幕待接入。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(40)
            }
            .background(Color.black.ignoresSafeArea())
        }
        .fullScreenCover(item: $selectedItem) { item in
            TVPlayerView(item: item)
                .environmentObject(model)
        }
    }
}

private struct TVPoster: View {
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
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

private struct TVPlayerView: View {
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
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
            .padding(30)
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
