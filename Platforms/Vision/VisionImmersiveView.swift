import AVFoundation
import RealityKit
import SwiftUI

struct VisionImmersiveView: View {
    @EnvironmentObject private var playback: VisionImmersiveModel
    @EnvironmentObject private var model: MobileLibraryModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var screenOffset = CGSize.zero
    @State private var screenScale: CGFloat = 1
    @State private var didAutoClose = false

    var body: some View {
        RealityView { content in
            addScreen(to: &content)
        } update: { content in
            addScreen(to: &content)
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    screenOffset = CGSize(
                        width: value.translation.width * 0.004,
                        height: -value.translation.height * 0.004
                    )
                }
        )
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    screenScale = min(max(value, 0.6), 2.0)
                }
        )
        .overlay(alignment: .bottom) {
            controls
                .padding(22)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
                .padding(.bottom, 30)
        }
        .task {
            guard !didAutoClose,
                  let seconds = ProcessInfo.processInfo.environment["OPENFUSE_IMMERSIVE_AUTOCLOSE"].flatMap(Double.init),
                  seconds > 0 else { return }
            didAutoClose = true
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            playback.finish(model: model)
            await dismissImmersiveSpace()
        }
        .onDisappear {
            playback.finish(model: model)
        }
    }

    private func addScreen(to content: inout RealityViewContent) {
        guard let player = playback.player else { return }
        let material = VideoMaterial(avPlayer: player)
        if let existing = content.entities.first(where: { $0.name == "openfuse.screen" }) as? ModelEntity {
            existing.model?.materials = [material]
            existing.position = SIMD3<Float>(
                Float(screenOffset.width), 1.45 + Float(screenOffset.height), -3.0
            )
            existing.scale = SIMD3<Float>(repeating: Float(screenScale))
            return
        }
        let screen = ModelEntity(
            mesh: .generatePlane(width: 4.0, height: 2.25, cornerRadius: 0.04),
            materials: [material]
        )
        screen.name = "openfuse.screen"
        screen.position = SIMD3<Float>(
            Float(screenOffset.width), 1.45 + Float(screenOffset.height), -3.0
        )
        screen.scale = SIMD3<Float>(repeating: Float(screenScale))
        content.add(screen)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            if let item = playback.item {
                Text(item.title)
                    .font(.headline)
            }
            HStack(spacing: 18) {
                Button {
                    playback.togglePlay()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .bold))
                }
                .buttonStyle(.plain)
                Text(timecode(playback.position))
                    .font(.system(size: 13, design: .monospaced))
                Slider(
                    value: Binding(
                        get: { playback.position },
                        set: { playback.seek(to: $0) }
                    ),
                    in: 0...max(playback.duration, 1)
                )
                .frame(width: 360)
                Text(timecode(playback.duration))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button {
                    Task {
                        playback.finish(model: model)
                        await dismissImmersiveSpace()
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func timecode(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let total = Int(seconds.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
