import Foundation

/// Human-readable subtitle offset: positive means subtitles appear later.
public enum SubtitleOffsetText {
    /// `MPVEngine.setSubtitleDelay(_:)` hands mpv three decimals, so the
    /// effective offset lives on a millisecond grid. Menus, the edit field,
    /// the stored value and the value sent to mpv all share this grid.
    private static let precisionScale: Double = 1000
    private static let limit: Double = 600

    /// Rounds to the millisecond precision mpv actually applies, clamps to the
    /// existing ±600 second range, and collapses values that round to zero
    /// (including negative zero) so they are not shown as a direction.
    public static func normalized(_ seconds: Double) -> Double {
        guard seconds.isFinite else { return 0 }
        let rounded = (seconds * precisionScale).rounded() / precisionScale
        let clamped = min(max(rounded, -limit), limit)
        return clamped == 0 ? 0 : clamped
    }

    /// Decimal seconds without padded zeros: 0.04 -> "0.04", 2.0 -> "2".
    /// The text is also what the edit field is prefilled with, and parsing it
    /// back preserves the effective offset.
    public static func valueText(_ seconds: Double) -> String {
        let value = normalized(seconds)
        let magnitude = abs(value)
        guard magnitude > 0 else { return "0" }
        var digits = String(
            format: "%.3f",
            locale: Locale(identifier: "en_US_POSIX"),
            magnitude
        )
        while digits.hasSuffix("0") { digits.removeLast() }
        if digits.hasSuffix(".") { digits.removeLast() }
        return value < 0 ? "-" + digits : digits
    }

    /// Menu and sheet text for the effective offset. Only a zero effective
    /// offset reads as "同步（0 秒）".
    public static func summary(_ seconds: Double) -> String {
        let value = normalized(seconds)
        if value == 0 { return "同步（0 秒）" }
        let magnitude = valueText(abs(value))
        return value > 0 ? "延后 \(magnitude) 秒" : "提前 \(magnitude) 秒"
    }

    /// Accepts exactly one signed decimal in seconds: "1.5", "+1.5", "-1",
    /// "−0.1" (U+2212), "－0.1" (full width), "＋1", "1,5", ".1", and the
    /// menu phrases "延后 2 秒" / "提前 0.1 秒". A direction word applies only
    /// when no sign is typed, so "提前 0.1 秒" becomes -0.1 instead of +0.1.
    ///
    /// The match is anchored: partial matches such as "abc 5", "5abc" or
    /// "-.1.2" are rejected rather than silently extracting a different
    /// number, which is how U+2212 used to lose its sign.
    public static func parse(_ text: String) -> Double? {
        var working = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !working.isEmpty else { return nil }

        var direction: Double = 0
        for (prefix, sign) in [("提前", -1.0), ("延后", 1.0)] where working.hasPrefix(prefix) {
            direction = sign
            working.removeFirst(prefix.count)
            working = working.trimmingCharacters(in: .whitespaces)
            if working.hasPrefix("：") || working.hasPrefix(":") {
                working.removeFirst()
                working = working.trimmingCharacters(in: .whitespaces)
            }
            break
        }

        let normalized = normalizeCharacters(working)
        let fullRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        guard let match = numericPattern.firstMatch(in: normalized, range: fullRange) else {
            return nil
        }

        func group(_ index: Int) -> String? {
            let groupRange = match.range(at: index)
            guard groupRange.location != NSNotFound,
                  let range = Range(groupRange, in: normalized) else { return nil }
            return String(normalized[range])
        }

        let sign = group(1) ?? ""
        guard var digits = group(2) else { return nil }
        // Contradictory input ("提前 +0.1") is rejected instead of silently
        // resolving to a positive offset.
        if direction != 0, !sign.isEmpty, (direction < 0) != (sign == "-") {
            return nil
        }
        if digits.hasPrefix(".") { digits = "0" + digits }
        if digits.hasSuffix(".") { digits.removeLast() }
        guard var value = Double(digits), value.isFinite else { return nil }

        if sign == "-" {
            value = -value
        } else if sign.isEmpty, direction != 0 {
            value *= direction
        }
        return min(max(value, -limit), limit)
    }

    /// One signed number with an optional unit ("秒", "s", "sec"). Anything
    /// before or after the number makes the whole input invalid.
    private static let numericPattern: NSRegularExpression = {
        let pattern = #"^([+\-]?)(\d+(?:\.\d*)?|\.\d+)\s*(?:秒|s|sec)?$"#
        return try! NSRegularExpression(pattern: pattern)
    }()

    /// Folds the minus/plus/dot/decimal variants users paste from subtitles or
    /// non-Latin keyboards into the ASCII forms the pattern understands.
    private static func normalizeCharacters(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "−", "－", "﹣":
                result.append("-")
            case "＋":
                result.append("+")
            case "，":
                result.append(",")
            case "．":
                result.append(".")
            default:
                if character.unicodeScalars.count == 1,
                   let scalar = character.unicodeScalars.first,
                   (0xFF10...0xFF19).contains(scalar.value) {
                    result.append(Character(Unicode.Scalar(scalar.value - 0xFF10 + 0x30)!))
                } else {
                    result.append(character)
                }
            }
        }
        return result.replacingOccurrences(of: ",", with: ".")
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
        return SubtitleOffsetText.normalized(snapshot.offsets[Self.key(media: media, track: track)] ?? 0)
    }

    public func setOffset(_ value: Double, media: String, track: String) {
        lock.lock(); defer { lock.unlock() }
        let key = Self.key(media: media, track: track)
        let value = SubtitleOffsetText.normalized(value)
        if value == 0 {
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
