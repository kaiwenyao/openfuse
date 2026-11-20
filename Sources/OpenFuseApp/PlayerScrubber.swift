import OpenFuseCore
import SwiftUI

/// Custom progress bar for the player.
///
/// Replaces `Slider` for three reasons:
/// 1. `Slider` draws its unfilled track with `labelColor`-derived colours, so on
///    the black player surface in the (default) light app theme the unplayed
///    part was invisible.
/// 2. `Slider` re-lays out an AppKit control on every playhead tick; the
///    scrubber now observes only `PlaybackClock`.
/// 3. It can show the demuxer cache (`buffered`) the same way IINA's slider
///    does, which makes stutter diagnosis visible.
struct PlayerScrubber: View {
    @ObservedObject var clock: PlaybackClock
    let duration: Double
    @Binding var dragValue: Double?
    var onScrubBegan: () -> Void
    var onScrubEnded: (Double) -> Void

    private let trackHeight: CGFloat = 4
    private let knobSize: CGFloat = 11

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let played = fraction(dragValue ?? clock.position, width: width)
            let buffered = fraction(clock.buffered, width: width)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.20))
                    .frame(height: trackHeight)
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.34))
                    .frame(width: width * buffered, height: trackHeight)
                Capsule(style: .continuous)
                    .fill(Theme.accent)
                    .frame(width: width * played, height: trackHeight)
                Circle()
                    .fill(Color.white)
                    .frame(width: knobSize, height: knobSize)
                    .offset(x: offset(for: played, width: width))
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            }
            .frame(width: width, height: 22, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard duration > 0 else { return }
                        if dragValue == nil {
                            onScrubBegan()
                        }
                        dragValue = seconds(at: value.location.x, width: width)
                    }
                    .onEnded { value in
                        guard duration > 0 else { return }
                        let target = seconds(at: value.location.x, width: width)
                        dragValue = nil
                        onScrubEnded(target)
                    }
            )
            .animation(nil, value: duration)
        }
        .frame(height: 22)
        .help("拖动定位")
    }

    private func fraction(_ seconds: Double, width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(min(max(seconds / duration, 0), 1))
    }

    private func offset(for played: CGFloat, width: CGFloat) -> CGFloat {
        min(max(width * played - knobSize / 2, 0), max(width - knobSize, 0))
    }

    private func seconds(at x: CGFloat, width: CGFloat) -> Double {
        guard duration > 0 else { return 0 }
        let ratio = min(max(x / width, 0), 1)
        return Double(ratio) * duration
    }
}

/// Timecode + scrubber row. Kept as its own view because it is the only part
/// of the chrome that observes the 10 Hz playhead: the labels must re-render
/// when `clock.position` changes, while the rest of the control bar must not.
struct PlayerTimeRow: View {
    @ObservedObject var clock: PlaybackClock
    let duration: Double
    @Binding var dragValue: Double?
    var onScrubBegan: () -> Void
    var onScrubEnded: (Double) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(Timecode.short(dragValue ?? clock.position))
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 62, alignment: .trailing)

            PlayerScrubber(
                clock: clock,
                duration: duration,
                dragValue: $dragValue,
                onScrubBegan: onScrubBegan,
                onScrubEnded: onScrubEnded
            )

            Text(duration > 0 ? Timecode.short(duration) : "--:--")
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 62, alignment: .leading)
        }
    }
}
