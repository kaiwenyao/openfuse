import AVFoundation
import RealityKit
import SwiftUI
import UIKit

struct VisionImmersiveView: View {
    @EnvironmentObject private var playback: VisionImmersiveModel
    @EnvironmentObject private var model: MobileLibraryModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @State private var screenOffset = CGSize.zero
    @State private var screenScale: CGFloat = 1
    @State private var didAutoClose = false

    var body: some View {
        RealityView { content in
            addEnvironment(to: &content)
            addScreen(to: &content)
            addControls(to: &content)
        } update: { content in
            addEnvironment(to: &content)
            addScreen(to: &content)
            addControls(to: &content)
        }
        .gesture(
            TapGesture().targetedToAnyEntity().onEnded { value in
                switch value.entity.name {
                case "openfuse.control.close":
                    Task {
                        playback.finish(model: model)
                        await dismissImmersiveSpace()
                        openWindow(id: "main")
                    }
                case "openfuse.control.play":
                    playback.togglePlay()
                default:
                    break
                }
            }
        )
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
            openWindow(id: "main")
        }
        .onDisappear {
            playback.finish(model: model)
        }
    }

    private func addEnvironment(to content: inout RealityViewContent) {
        if let floor = content.entities.first(where: { $0.name == "openfuse.floor" }) as? ModelEntity {
            floor.position.y = -0.6 + Float(screenOffset.height * 0.5)
            return
        }
        let floor = ModelEntity(
            mesh: .generatePlane(width: 14, height: 14),
            materials: [SimpleMaterial(color: UIColor(white: 0.045, alpha: 1), roughness: 0.95, isMetallic: false)]
        )
        floor.name = "openfuse.floor"
        floor.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        floor.position = SIMD3<Float>(0, -0.6, -3)
        content.add(floor)

        let frame = ModelEntity(
            mesh: .generatePlane(width: 4.18, height: 2.42, cornerRadius: 0.06),
            materials: [SimpleMaterial(color: UIColor(white: 0.09, alpha: 1), roughness: 0.4, isMetallic: false)]
        )
        frame.name = "openfuse.frame"
        frame.position = SIMD3<Float>(0, 1.45, -3.04)
        content.add(frame)

        let starMaterial = UnlitMaterial(color: UIColor(white: 0.9, alpha: 1))
        for index in 0..<48 {
            let star = ModelEntity(
                mesh: .generateSphere(radius: 0.012),
                materials: [starMaterial]
            )
            let angle = Float(index) * 2.399963
            let radius = Float(5.5 + Double(index % 5) * 0.7)
            star.position = SIMD3<Float>(
                cos(angle) * radius,
                1.2 + sin(Float(index) * 1.7) * 2.2,
                sin(angle) * radius - 2
            )
            content.add(star)
        }
    }

    private func addControls(to content: inout RealityViewContent) {
        if let play = content.entities.first(where: { $0.name == "openfuse.control.play" }) as? ModelEntity {
            play.model?.materials = [SimpleMaterial(
                color: playback.isPlaying ? UIColor.systemOrange : UIColor.systemBlue,
                roughness: 0.3, isMetallic: false
            )]
        } else {
            let play = ModelEntity(
                mesh: .generateSphere(radius: 0.11),
                materials: [SimpleMaterial(color: UIColor.systemBlue, roughness: 0.3, isMetallic: false)]
            )
            play.name = "openfuse.control.play"
            play.position = SIMD3<Float>(-2.15, 2.72, -3.0)
            play.components.set(InputTargetComponent())
            play.generateCollisionShapes(recursive: true)
            content.add(play)

            let close = ModelEntity(
                mesh: .generateSphere(radius: 0.11),
                materials: [SimpleMaterial(color: UIColor.systemRed, roughness: 0.3, isMetallic: false)]
            )
            close.name = "openfuse.control.close"
            close.position = SIMD3<Float>(2.15, 2.72, -3.0)
            close.components.set(InputTargetComponent())
            close.generateCollisionShapes(recursive: true)
            content.add(close)
        }

        let progress = playback.duration > 0 ? min(1, max(0, playback.position / playback.duration)) : 0
        if let bar = content.entities.first(where: { $0.name == "openfuse.control.progress" }) as? ModelEntity {
            bar.scale.x = Float(max(0.001, progress))
        } else {
            let bar = ModelEntity(
                mesh: .generateBox(size: SIMD3<Float>(4.0, 0.025, 0.012)),
                materials: [SimpleMaterial(color: UIColor.systemYellow, roughness: 0.4, isMetallic: false)]
            )
            bar.name = "openfuse.control.progress"
            bar.position = SIMD3<Float>(-2.0, 0.30, -2.99)
            bar.scale.x = Float(max(0.001, progress))
            content.add(bar)
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
                Text(playback.spatialAudio)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
                        openWindow(id: "main")
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
