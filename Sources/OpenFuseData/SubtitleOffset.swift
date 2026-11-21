import Foundation

/// Human-readable subtitle offset: positive means subtitles appear later.
public enum SubtitleOffsetText {
    public static func summary(_ seconds: Double) -> String {
        let value = (seconds * 10).rounded() / 10
        if abs(value) < 0.05 { return "同步（0 秒）" }
        let magnitude = String(format: "%.1f", abs(value))
            .replacingOccurrences(of: ".0", with: "")
        return value > 0 ? "延后 \(magnitude) 秒" : "提前 \(magnitude) 秒"
    }

    /// Accepts "1.5", "+1.5", "-1", "1,5", or a phrase containing a number.
    public static func parse(_ text: String) -> Double? {
        let normalized = text
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "＋", with: "+")
            .replacingOccurrences(of: "－", with: "-")
        guard let match = normalized.range(of: #"[+-]?\d+(?:\.\d+)?"#, options: .regularExpression) else {
            return nil
        }
        guard let value = Double(normalized[match]), value.isFinite else { return nil }
        return min(max(value, -600), 600)
    }
}

/// Per media + subtitle track offsets, stored separately from playback records
/// so existing playback.json files keep decoding unchanged.
public final class SubtitleOffsetStore: @unchecked Sendable {
    public struct Snapshot: Codable, Sendable {
        public var version: Int = 1
        public var offsets: [String: Double] = [:]
    }

    private let fileURL: URL
    private var snapshot: Snapshot
    private let lock = NSLock()

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("subtitle-offsets.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Snapshot.self, from: data) {
            self.snapshot = decoded
        } else {
            self.snapshot = Snapshot()
        }
    }

    public static func key(media: String, track: String) -> String {
        "\(media)|\(track)"
    }

    public func offset(media: String, track: String) -> Double {
        lock.lock(); defer { lock.unlock() }
        return snapshot.offsets[Self.key(media: media, track: track)] ?? 0
    }

    public func setOffset(_ value: Double, media: String, track: String) {
        lock.lock(); defer { lock.unlock() }
        let key = Self.key(media: media, track: track)
        if abs(value) < 0.0001 {
            snapshot.offsets.removeValue(forKey: key)
        } else {
            snapshot.offsets[key] = value
        }
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    public var allOffsets: [String: Double] {
        lock.lock(); defer { lock.unlock() }
        return snapshot.offsets
    }
}
