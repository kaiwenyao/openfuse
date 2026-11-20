import Foundation

public struct SubtitleCue: Hashable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String
}

public enum SubtitleParser {
    public static func parse(url: URL) throws -> [SubtitleCue] {
        let data = try Data(contentsOf: url)
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        switch url.pathExtension.lowercased() {
        case "ass", "ssa":
            return parseASS(text)
        case "vtt":
            return parseSRTLike(text, separator: ".")
        default:
            return parseSRTLike(text, separator: ",")
        }
    }

    static func parseSRTLike(_ text: String, separator: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        let blocks = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
        for block in blocks {
            let lines = block.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard let timeLine = lines.first(where: { $0.contains("-->") }) else { continue }
            let parts = timeLine.components(separatedBy: "-->")
            guard parts.count == 2,
                  let start = parseTime(parts[0], separator: separator),
                  let end = parseTime(parts[1], separator: separator) else { continue }
            let body = lines.drop(while: { $0 != timeLine }).dropFirst().joined(separator: "\n")
            let cleaned = clean(body)
            guard !cleaned.isEmpty else { continue }
            cues.append(SubtitleCue(start: start, end: end, text: cleaned))
        }
        return cues.sorted { $0.start < $1.start }
    }

    static func parseASS(_ text: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        for line in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            guard line.hasPrefix("Dialogue:") else { continue }
            let payload = line.dropFirst("Dialogue:".count).trimmingCharacters(in: .whitespaces)
            let fields = payload.split(separator: ",", maxSplits: 9, omittingEmptySubsequences: false)
            guard fields.count == 10,
                  let start = parseTime(String(fields[1]), separator: "."),
                  let end = parseTime(String(fields[2]), separator: ".") else { continue }
            let body = String(fields[9])
                .replacingOccurrences(of: "\\N", with: "\n")
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\h", with: " ")
            let cleaned = clean(body)
            guard !cleaned.isEmpty else { continue }
            cues.append(SubtitleCue(start: start, end: end, text: cleaned))
        }
        return cues.sorted { $0.start < $1.start }
    }

    static func parseTime(_ raw: String, separator: String) -> TimeInterval? {
        var value = raw.trimmingCharacters(in: .whitespaces)
        if let space = value.firstIndex(of: " ") { value = String(value[..<space]) }
        value = value.replacingOccurrences(of: ",", with: separator)
        let parts = value.components(separatedBy: ":")
        guard parts.count == 3 else { return nil }
        let secondsPart = parts[2].replacingOccurrences(of: ",", with: ".")
        guard let hours = Double(parts[0]), let minutes = Double(parts[1]), let seconds = Double(secondsPart) else {
            return nil
        }
        return hours * 3600 + minutes * 60 + seconds
    }

    static func clean(_ text: String) -> String {
        var value = text
        value = value.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\{\\[^}]*\}"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\{[^}]*\}"#, with: "", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
