import OpenFuseCore
import SwiftUI

/// Speaker button + 0–100 % slider in the player control bar. Both the slider,
/// the arrow keys and the HUD share `PlayerModel.volume`.
struct VolumeControl: View {
    @ObservedObject var player: PlayerModel

    var body: some View {
        HStack(spacing: 6) {
            Button {
                player.toggleMute()
            } label: {
                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)
            }
            .buttonStyle(.plain)
            .help(player.volume > 0 ? "静音" : "取消静音")

            VolumeSlider(value: player.volume) { player.setVolume($0) }
                .frame(width: 64, height: 18)
                .help("音量 \(Int(player.volume.rounded()))%")
        }
    }

    private var iconName: String {
        switch player.volume {
        case 0: return "speaker.slash.fill"
        case ..<34: return "speaker.wave.1.fill"
        case ..<67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}

private struct VolumeSlider: View {
    let value: Double
    var onChange: (Double) -> Void
    @State private var dragValue: Double?

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let percent = (dragValue ?? value) / 100
            let knob: CGFloat = 9
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.22))
                    .frame(height: 4)
                Capsule()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: width * percent, height: 4)
                Circle()
                    .fill(Color.white)
                    .frame(width: knob, height: knob)
                    .offset(x: min(max(width * percent - knob / 2, 0), width - knob))
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            }
            .frame(width: width, height: 18)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let ratio = min(max(gesture.location.x / width, 0), 1)
                        dragValue = ratio * 100
                        onChange(dragValue ?? value)
                    }
                    .onEnded { gesture in
                        let ratio = min(max(gesture.location.x / width, 0), 1)
                        dragValue = nil
                        onChange(ratio * 100)
                    }
            )
        }
    }
}

/// Small transient HUD shown after a volume change.
struct PlayerVolumeHUD: View {
    @ObservedObject var player: PlayerModel

    var body: some View {
        if player.showVolumeHUD {
            HStack(spacing: 9) {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
                Text("\(Int(player.volume.rounded()))%")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.72), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 1))
            .foregroundStyle(.white)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    private var iconName: String {
        switch player.volume {
        case 0: return "speaker.slash.fill"
        case ..<34: return "speaker.wave.1.fill"
        case ..<67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}
