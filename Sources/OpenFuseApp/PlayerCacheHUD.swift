import OpenFuseCore
import SwiftUI

/// Centered loading/buffering HUD, modelled on IINA's `BufferIndicatorView`:
/// a spinner, "Buffering… N%" while `paused-for-cache`, and a detail line with
/// the forward cache size and the download speed (`fw-bytes` /
/// `raw-input-rate`). While the file is still opening it shows "Opening…"
/// instead of a percentage.
struct PlayerCacheHUD: View {
    @ObservedObject var player: PlayerModel

    var body: some View {
        if player.isBuffering || player.isOpening || player.isNetworkStalled || player.isReconnecting {
            VStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            )
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    private var title: String {
        if player.isReconnecting {
            return "正在重新连接…"
        }
        if player.isNetworkStalled {
            return "连接中断，重试播放"
        }
        if player.isBuffering {
            let percent = min(max(player.bufferingPercent, 0), 100)
            return percent > 0 ? "缓冲中 \(percent)%" : "缓冲中…"
        }
        return "正在打开…"
    }

    private var detail: String? {
        // Local files never show a network speed measurement.
        guard player.isNetworkSource else { return nil }
        guard player.hasSpeedSample else { return "测速中…" }
        var pieces: [String] = []
        if player.cacheBytes > 0 {
            pieces.append(Self.byteCount(player.cacheBytes))
        }
        pieces.append(player.cacheSpeed >= 1 ? Self.speed(player.cacheSpeed) : "0 B/s")
        return pieces.joined(separator: " · ")
    }

    private static func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .binary)
    }

    private static func speed(_ bytesPerSecond: Double) -> String {
        let value = ByteCountFormatter.string(fromByteCount: Int64(max(0, bytesPerSecond)), countStyle: .binary)
        return "\(value)/s"
    }
}
