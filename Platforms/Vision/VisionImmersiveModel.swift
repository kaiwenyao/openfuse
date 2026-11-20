import AVFoundation
import Foundation
import OpenFuseData

@MainActor
final class VisionImmersiveModel: ObservableObject {
    static let spaceID = "openfuse.immersive"

    @Published var item: MobilePlaybackItem?
    @Published var player: AVPlayer?
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying = false
    @Published var status: String?
    @Published var spatialAudio = "未配置"

    private var loader: AuthenticatedAssetLoader?
    private var observer: Any?
    private var hasFinished = false

    func prepare(item: MobilePlaybackItem, model: MobileLibraryModel) async {
        stopObserver()
        self.item = item
        hasFinished = false
        configureSpatialAudio()
        let (player, loader) = model.makePlayer(for: item)
        self.player = player
        self.loader = loader
        position = item.resumePosition ?? 0
        duration = 0
        isPlaying = false
        observer = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            guard let self, time.seconds.isFinite else { return }
            self.position = max(0, time.seconds)
            if let total = player.currentItem?.duration.seconds, total.isFinite, total > 0 {
                self.duration = total
            }
            self.isPlaying = player.rate > 0
        }
        let asset = AVURLAsset(url: item.url)
        if let loaded = try? await asset.load(.duration) {
            duration = loaded.seconds
        }
        if let resume = item.resumePosition {
            await player.seek(to: CMTime(seconds: resume, preferredTimescale: 600))
        }
        player.play()
        isPlaying = true
        status = nil
    }

    func togglePlay() {
        guard let player else { return }
        if player.rate > 0 {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        let target = min(max(0, seconds), max(duration, seconds))
        Task {
            await player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        }
        position = target
    }

    func finish(model: MobileLibraryModel) {
        guard !hasFinished, let player, let item else { return }
        hasFinished = true
        let total = duration > 0 ? duration : (player.currentItem?.duration.seconds ?? 0)
        let current = player.currentTime().seconds
        if current.isFinite, total.isFinite, total > 0 {
            let finished = ResumePolicy.isFinished(position: current, duration: total)
            model.recordProgress(
                item: item,
                duration: total,
                position: finished ? 0 : current,
                finished: finished
            )
        }
        player.pause()
        stopObserver()
    }

    private func configureSpatialAudio() {
        #if os(visionOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setIntendedSpatialExperience(
                .headTracked(soundStageSize: .medium, anchoringStrategy: .front)
            )
            try session.setActive(true)
            spatialAudio = "head-tracked · medium"
        } catch {
            spatialAudio = "空间音频不可用：\(error.localizedDescription)"
        }
        #endif
    }

    private func stopObserver() {
        if let observer, let player {
            player.removeTimeObserver(observer)
        }
        observer = nil
    }
}
