import AppKit
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
    let thumbnails: ThumbnailProvider
    @Binding var dragValue: Double?
    var onScrubBegan: () -> Void
    var onScrubEnded: (Double) -> Void

    private struct Hover: Equatable {
        let x: CGFloat
        let time: Double
        let bucket: Int
    }

    @State private var hover: Hover?
    @State private var previewImage: NSImage?
    @State private var previewLoading = false
    @State private var previewFailed = false
    @State private var previewTask: Task<Void, Never>?
    @State private var hoverBeganAt = CFAbsoluteTimeGetCurrent()
    @State private var autoHovered = false

    private let trackHeight: CGFloat = 4
    private let knobSize: CGFloat = 11
    private let previewWidth: CGFloat = 168

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let played = fraction(dragValue ?? clock.position, width: width)
            let ranges = bufferedRanges

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.20))
                    .frame(height: trackHeight)
                // Cached spans reported by mpv's demuxer cache, highlighted under
                // the played portion (seekable ranges, so a remote file that was
                // seeked can show more than one span).
                ForEach(Array(ranges.enumerated()), id: \.offset) { _, range in
                    let start = fraction(range.start, width: width)
                    let end = fraction(range.end, width: width)
                    Capsule(style: .continuous)
                        .fill(Theme.accent.opacity(0.42))
                        .frame(width: max(0, width * (end - start)), height: trackHeight)
                        .offset(x: width * start)
                }
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
            .overlay(alignment: .topLeading) {
                if let hover, duration > 0 {
                    ThumbnailPreview(
                        image: previewImage,
                        time: hover.time,
                        loading: previewLoading,
                        failed: previewFailed
                    )
                    .frame(width: previewWidth)
                    .offset(
                        x: ThumbnailMath.previewOrigin(
                            hoverX: hover.x,
                            width: width,
                            previewWidth: previewWidth
                        ),
                        y: -126
                    )
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
            .onAppear {
                guard ProcessInfo.processInfo.environment["OPENFUSE_HOVER_SCRUBBER"] == "1",
                      !autoHovered else { return }
                autoHovered = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    updateHover(x: width * 0.25, width: width)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    updateHover(x: width * 0.70, width: width)
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    updateHover(x: point.x, width: width)
                case .ended:
                    endHover()
                }
            }
        }
        .frame(height: 22)
        .help("拖动定位")
        .onDisappear { endHover() }
    }

    private func updateHover(x: CGFloat, width: CGFloat) {
        if ProcessInfo.processInfo.environment["OPENFUSE_DEBUG_THUMBS"] == "1" {
            print("[thumb] hover x=\(x) width=\(width) duration=\(duration)")
        }
        guard duration > 0 else { return }
        let time = ThumbnailMath.hoverTime(x: x, width: width, duration: duration)
        let bucket = ThumbnailMath.bucket(for: time)
        let clampedX = min(max(x, 0), width)
        let changedBucket = hover?.bucket != bucket
        hover = Hover(x: clampedX, time: time, bucket: bucket)
        guard changedBucket else { return }

        previewTask?.cancel()
        previewImage = nil
        previewLoading = true
        previewFailed = false
        hoverBeganAt = CFAbsoluteTimeGetCurrent()
        let debug = ProcessInfo.processInfo.environment["OPENFUSE_DEBUG_THUMBS"] == "1"
        previewTask = Task { @MainActor in
            if let cached = thumbnails.cachedImage(for: time) {
                guard !Task.isCancelled, hover?.bucket == bucket else { return }
                previewImage = cached
                previewLoading = false
                if debug { print("[thumb] event=memory bucket=\(bucket) ms=\(Int((CFAbsoluteTimeGetCurrent() - hoverBeganAt) * 1000))") }
                return
            }
            if let disk = await thumbnails.cachedOrDiskImage(for: time) {
                guard !Task.isCancelled, hover?.bucket == bucket else { return }
                previewImage = disk
                previewLoading = false
                if debug { print("[thumb] event=disk bucket=\(bucket) ms=\(Int((CFAbsoluteTimeGetCurrent() - hoverBeganAt) * 1000))") }
                return
            }
            // Only uncached frames wait for the debounce; memory/disk hits show
            // immediately even during a fast sweep.
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            if debug { print("[thumb] event=decode-start bucket=\(bucket)") }
            let image = await thumbnails.image(for: time)
            guard !Task.isCancelled, hover?.bucket == bucket else { return }
            previewImage = image
            previewLoading = false
            previewFailed = image == nil
            if debug { print("[thumb] event=shown bucket=\(bucket) source=\(thumbnails.lastSource) ms=\(Int((CFAbsoluteTimeGetCurrent() - hoverBeganAt) * 1000))") }
        }
    }

    private func endHover() {
        if ProcessInfo.processInfo.environment["OPENFUSE_DEBUG_THUMBS"] == "1" {
            print("[thumb] hover ended")
        }
        previewTask?.cancel()
        previewTask = nil
        hover = nil
        previewImage = nil
        previewLoading = false
        previewFailed = false
    }

    /// Cache spans clamped to the timeline. Falls back to the single cache end
    /// when mpv has not reported `seekable-ranges` yet.
    private var bufferedRanges: [BufferedRange] {
        if !clock.bufferedRanges.isEmpty {
            return clock.bufferedRanges
        }
        guard clock.buffered > 0, duration > 0 else { return [] }
        return [BufferedRange(start: 0, end: min(clock.buffered, duration))]
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
    let thumbnails: ThumbnailProvider
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
                thumbnails: thumbnails,
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


/// Floating hover preview: thumbnail (320×180 PNG scaled to 168×94.5) plus the
/// timecode under the cursor.
private struct ThumbnailPreview: View {
    let image: NSImage?
    let time: Double
    let loading: Bool
    let failed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Color.black.opacity(0.9)
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if loading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else if failed {
                    Text("无缩略图")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .frame(width: 168, height: 94.5)
            .clipped()

            HStack(spacing: 6) {
                Text(Timecode.short(time))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.86))
        }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 8, y: 3)
    }
}
