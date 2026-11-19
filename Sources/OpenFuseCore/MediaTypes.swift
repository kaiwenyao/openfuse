import Foundation

/// Identifies one concrete playable file. Local files are identified by their
/// resolved path plus size/mtime so that a replaced file is not mistaken for
/// the old one when validating cached metadata. The path is also the resume
/// key, mirroring Infuse's behaviour of keeping progress attached to the file.
public struct MediaFingerprint: Codable, Hashable, Sendable {
    public var path: String
    public var fileSize: Int64
    public var modifiedAt: Date?

    public init(path: String, fileSize: Int64, modifiedAt: Date?) {
        self.path = path
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
    }

    public init(url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        self.path = url.resolvingSymlinksInPath().path
        self.fileSize = Int64((attributes[.size] as? NSNumber)?.int64Value ?? 0)
        self.modifiedAt = attributes[.modificationDate] as? Date
    }

    /// Resume key. Deliberately ignores size and mtime: replacing a file at the
    /// same path should keep the user's position, exactly like a file browser.
    public var resumeKey: String { path }

    public var url: URL { URL(fileURLWithPath: path) }
}

public enum SubtitleFormat: String, Codable, Sendable {
    case ass, ssa, srt, vtt, pgs, sup, vobsub, unknown

    public init(fileExtension: String) {
        self = SubtitleFormat(rawValue: fileExtension.lowercased()) ?? .unknown
    }

    public var displayName: String {
        switch self {
        case .ass, .ssa: return "ASS"
        case .srt: return "SRT"
        case .vtt: return "WebVTT"
        case .pgs, .sup: return "PGS"
        case .vobsub: return "VobSub"
        case .unknown: return "字幕"
        }
    }

    public var isText: Bool {
        switch self {
        case .ass, .ssa, .srt, .vtt: return true
        default: return false
        }
    }
}

/// A subtitle track as the UI presents it: external sidecar, embedded track or
/// a track reported by a media server. `id` is stable for a given file so that
/// the user's selection survives relaunching the app.
public struct SubtitleTrack: Codable, Hashable, Identifiable, Sendable {
    public enum Source: String, Codable, Sendable {
        case external
        case embedded
        case server
        case downloaded
    }

    public var id: String
    public var displayName: String
    /// Normalised BCP-47-ish tag: zh-Hans, zh-Hant, zh, ja, en, und.
    public var language: String?
    public var format: SubtitleFormat
    public var source: Source
    public var url: URL?
    public var isForced: Bool
    /// Engine-assigned identifier (mpv sid / AVMediaSelectionOption id) once loaded.
    public var engineID: Int64?

    public init(
        id: String,
        displayName: String,
        language: String?,
        format: SubtitleFormat,
        source: Source,
        url: URL? = nil,
        isForced: Bool = false,
        engineID: Int64? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.language = language
        self.format = format
        self.source = source
        self.url = url
        self.isForced = isForced
        self.engineID = engineID
    }
}

public struct AudioTrack: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var language: String?
    public var codec: String?
    public var channels: Int?
    public var isDefault: Bool
    public var engineID: Int64?

    public init(
        id: String,
        displayName: String,
        language: String?,
        codec: String?,
        channels: Int?,
        isDefault: Bool,
        engineID: Int64? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.language = language
        self.codec = codec
        self.channels = channels
        self.isDefault = isDefault
        self.engineID = engineID
    }

    /// "E-AC-3 5.1" style label, the string Infuse shows in its audio menu.
    public var technicalLabel: String {
        var parts: [String] = []
        if let codec, !codec.isEmpty { parts.append(AudioCodecLabel.display(codec)) }
        if let channels, channels > 0 {
            parts.append(Self.channelLabel(channels))
        }
        return parts.joined(separator: " ")
    }

    public static func channelLabel(_ channels: Int) -> String {
        switch channels {
        case 1: return "单声道"
        case 2: return "立体声"
        case 6: return "5.1"
        case 8: return "7.1"
        default: return "\(channels) 声道"
        }
    }
}


public enum AudioCodecLabel {
    public static func display(_ codec: String) -> String {
        switch codec.lowercased() {
        case "eac3": return "E-AC-3"
        case "ac3": return "AC-3"
        case "truehd": return "TrueHD"
        case "dts", "dts-hd", "dtshd": return "DTS"
        case "aac": return "AAC"
        case "flac": return "FLAC"
        case "opus": return "Opus"
        case "pcm_s16le", "pcm_s24le", "pcm": return "PCM"
        case "mp3": return "MP3"
        default: return codec.uppercased()
        }
    }
}
