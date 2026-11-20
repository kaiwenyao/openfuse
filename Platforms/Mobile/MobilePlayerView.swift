import AVKit
import OpenFuseData
import SwiftUI

struct MobilePlayerView: View {
    @EnvironmentObject private var model: MobileLibraryModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    let item: MobilePlaybackItem

    @State private var player: AVPlayer?
    @State private var resourceLoader: AuthenticatedAssetLoader?
    @State private var timeObserver: Any?
    @State private var lastPosition: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var errorText: String?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView().tint(.white)
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .padding(10)
                    .background(.black.opacity(0.6), in: Circle())
                    .foregroundStyle(.white)
            }
            .padding(16)
            if let errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .padding()
                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 60)
            }
        }
        .onAppear { setupPlayer() }
        .onDisappear {
            saveProgress()
            player?.pause()
            if let timeObserver, let player {
                player.removeTimeObserver(timeObserver)
            }
            timeObserver = nil
            resourceLoader = nil
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { saveProgress() }
        }
    }

    private func setupPlayer() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            errorText = "音频会话失败：\(error.localizedDescription)"
        }

        let (player, loader) = model.makePlayer(for: item)
        self.player = player
        self.resourceLoader = loader
        duration = 0
        lastPosition = 0
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 600),
            queue: .main
        ) { time in
            lastPosition = max(0, time.seconds.isFinite ? time.seconds : 0)
            if let itemDuration = player.currentItem?.duration.seconds,
               itemDuration.isFinite, itemDuration > 0 {
                duration = itemDuration
            }
        }

        Task {
            let asset = AVURLAsset(url: item.url)
            if let loaded = try? await asset.load(.duration) {
                duration = loaded.seconds
            }
            if let resume = item.resumePosition, resume > 0 {
                await player.seek(to: CMTime(seconds: resume, preferredTimescale: 600))
            }
            player.play()
        }
    }

    private func saveProgress() {
        guard let player else { return }
        let position = player.currentTime().seconds
        guard position.isFinite else { return }
        let currentDuration = duration > 0 ? duration : (player.currentItem?.duration.seconds ?? 0)
        guard currentDuration.isFinite, currentDuration > 0 else { return }
        let finished = ResumePolicy.isFinished(position: position, duration: currentDuration)
        model.recordProgress(
            item: item,
            duration: currentDuration,
            position: finished ? 0 : position,
            finished: finished
        )
    }
}
