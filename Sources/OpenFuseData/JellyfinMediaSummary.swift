import Foundation

/// Formats the selected Jellyfin MediaSource for the detail page. Every value is
/// optional: unknown fields are omitted rather than rendered as "—".
public struct JellyfinMediaSummary: Sendable {
    public var source: JellyfinMediaSource
    public var video: JellyfinMediaStream?
    public var audio: JellyfinMediaStream?
    public var subtitles: [JellyfinMediaStream]

    public init(source: JellyfinMediaSource) {
        self.source = source
        let streams = source.mediaStreams ?? []
        self.video = streams.first { $0.type.caseInsensitiveCompare("Video") == .orderedSame }
        let audios = streams.filter { $0.type.caseInsensitiveCompare("Audio") == .orderedSame }
        self.audio = audios.first { $0.isDefault == true } ?? audios.first
        self.subtitles = streams.filter { $0.type.caseInsensitiveCompare("Subtitle") == .orderedSame }
    }

    /// One line for the play button: size · codec · resolution · audio · bitrate · fps.
    public var shortLine: String {
        var parts: [String] = []
        if let size = source.size, let text = Self.formatSize(size) { parts.append(text) }
        if let codec = video?.codec, !codec.isEmpty { parts.append(codec.uppercased()) }
        if let width = video?.width, let height = video?.height, width > 0, height > 0 {
            parts.append("\(width)×\(height)")
        }
        if let audioText = audioText { parts.append(audioText) }
        if let bitrate = source.bitrate, let text = Self.formatBitrate(bitrate) { parts.append(text) }
        if let fps = video?.frameRate, let text = Self.formatFrameRate(fps) { parts.append(text) }
        return parts.joined(separator: " · ")
    }

    public var audioText: String? {
        guard let audio else { return nil }
        var value = (audio.codec ?? "").uppercased()
        if let layout = Self.channelLayout(channels: audio.channels, layout: audio.channelLayout) {
            value += value.isEmpty ? layout : " \(layout)"
        }
        return value.isEmpty ? nil : value
    }

    /// Expanded lines: container, profile, bit depth, HDR/SDR, languages and
    /// subtitle formats. Total and video-only bitrate are separate entries.
    public var detailLines: [(String, String)] {
        var lines: [(String, String)] = []
        if let container = source.container, !container.isEmpty {
            lines.append(("容器", container.uppercased()))
        }
        if let video {
            var codec = (video.codec ?? "").uppercased()
            if let profile = video.profile, !profile.isEmpty {
                codec += codec.isEmpty ? profile : " \(profile)"
            }
            if !codec.isEmpty { lines.append(("视频编码", codec)) }
            if let depth = video.bitDepth { lines.append(("位深", "\(depth)-bit")) }
            let range = video.videoRangeType ?? video.videoRange ?? video.colorTransfer
            if let range, !range.isEmpty {
                lines.append(("动态范围", range.uppercased()))
            }
            if let videoRate = video.bitRate, let text = Self.formatBitrate(videoRate),
               source.bitrate != video.bitRate {
                lines.append(("视频码率", text))
            }
        }
        if let bitrate = source.bitrate, let text = Self.formatBitrate(bitrate) {
            lines.append(("总码率", text))
        }
        if let audio {
            var value = (audio.codec ?? "").uppercased()
            if let layout = Self.channelLayout(channels: audio.channels, layout: audio.channelLayout) {
                value += value.isEmpty ? layout : " \(layout)"
            }
            if let language = audio.language, !language.isEmpty {
                value += value.isEmpty ? language : " · \(language.uppercased())"
            }
            if !value.isEmpty { lines.append(("音轨", value)) }
        }
        if !subtitles.isEmpty {
            let formats = subtitles.map { stream -> String in
                var value = (stream.codec ?? "").uppercased()
                if let language = stream.language, !language.isEmpty {
                    value += value.isEmpty ? language : " · \(language.uppercased())"
                }
                return value
            }.filter { !$0.isEmpty }
            if !formats.isEmpty { lines.append(("字幕", formats.joined(separator: " / "))) }
        }
        return lines
    }

    // MARK: - Formatting

    public static func formatSize(_ bytes: Int64) -> String? {
        guard bytes > 0 else { return nil }
        if bytes >= 1_000_000_000 {
            return String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
        }
        if bytes >= 1_000_000 {
            return String(format: "%.1f MB", Double(bytes) / 1_000_000)
        }
        return String(format: "%.0f KB", Double(bytes) / 1_000)
    }

    public static func formatBitrate(_ bitsPerSecond: Int64) -> String? {
        guard bitsPerSecond > 0 else { return nil }
        if bitsPerSecond >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(bitsPerSecond) / 1_000_000)
        }
        return String(format: "%.0f kbps", Double(bitsPerSecond) / 1_000)
    }

    public static func formatFrameRate(_ fps: Double) -> String? {
        guard fps > 0 else { return nil }
        var text = String(format: "%.3f", fps)
        while text.contains("."), text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return "\(text) fps"
    }

    public static func channelLayout(channels: Int?, layout: String?) -> String? {
        if let layout, !layout.isEmpty { return layout }
        guard let channels, channels > 0 else { return nil }
        switch channels {
        case 1: return "1.0"
        case 2: return "2.0"
        case 6: return "5.1"
        case 8: return "7.1"
        default: return "\(channels)ch"
        }
    }
}
