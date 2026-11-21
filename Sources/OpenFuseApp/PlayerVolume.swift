import OpenFuseCore
import SwiftUI

/// Speaker button + 0–100 % system `Slider` in the floating panel. Both the
/// slider, the arrow keys and the HUD share `PlayerModel.volume`.
struct VolumeControl: View {
    @ObservedObject var player: PlayerModel
    var compact = false

    var body: some View {
        HStack(spacing: 6) {
            Button {
                player.toggleMute()
            } label: {
                Image(systemName: iconName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(player.volume > 0 ? "静音" : "取消静音")
            .accessibilityLabel(player.volume > 0 ? "静音" : "取消静音")

            // A 320 pt window keeps the panel for play, timeline and subtitles;
            // the slider moves to the audio menu there.
            if !compact {
                Slider(
                    value: Binding(
                        get: { player.volume },
                        set: { player.setVolume($0) }
                    ),
                    in: 0...100
                )
                .controlSize(.mini)
                .tint(.white)
                .frame(width: 72)
                .help("音量 \(Int(player.volume.rounded()))%")
                .accessibilityLabel("音量")
            }
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
