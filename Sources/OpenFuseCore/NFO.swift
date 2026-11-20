import Foundation

public struct NFOMetadata: Sendable {
    public var title: String?
    public var year: Int?
    public var overview: String?
    public var posterURL: URL?
    public var posterPath: String?
    /// Raw <poster>/<thumb> value. For remote NFOs this can be a relative
    /// filename that the caller resolves against the remote directory.
    public var posterReference: String?
}

/// Minimal Kodi/Jellyfin-compatible NFO reader. Supports movie.nfo,
/// <video>.nfo, tvshow.nfo and episode NFO files; unknown fields are ignored.
public enum NFOReader {
    public static func readMovie(videoURL: URL) -> NFOMetadata? {
        let folder = videoURL.deletingLastPathComponent()
        let base = videoURL.deletingPathExtension().lastPathComponent
        let candidates = [
            folder.appendingPathComponent(base + ".nfo"),
            folder.appendingPathComponent("movie.nfo"),
        ]
        for candidate in candidates {
            if let metadata = parse(candidate) { return metadata }
        }
        return nil
    }

    public static func readShow(showDirectory: URL) -> NFOMetadata? {
        parse(showDirectory.appendingPathComponent("tvshow.nfo"))
    }

    public static func readEpisode(videoURL: URL) -> NFOMetadata? {
        parse(videoURL.deletingPathExtension().appendingPathExtension("nfo"))
    }

    public static func parse(_ url: URL) -> NFOMetadata? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parse(data: data, baseURL: url.deletingLastPathComponent())
    }

    public static func parse(data: Data, baseURL: URL) -> NFOMetadata? {
        let parser = NFOParser(baseURL: baseURL)
        guard parser.parse(data) else { return nil }
        return parser.metadata
    }
}

private final class NFOParser: NSObject, XMLParserDelegate {
    private let baseURL: URL
    private(set) var metadata = NFOMetadata()
    private var text = ""
    private var currentElement = ""

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    func parse(_ data: Data) -> Bool {
        let parser = XMLParser(data: data)
        parser.delegate = self
        return parser.parse()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName.lowercased()
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.lowercased()
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { text = ""; return }
        switch name {
        case "title":
            if metadata.title == nil { metadata.title = value }
        case "year":
            if metadata.year == nil { metadata.year = Int(value.prefix(4)) }
        case "plot", "outline", "overview":
            if metadata.overview == nil { metadata.overview = value }
        case "poster", "thumb":
            if metadata.posterPath == nil { setPoster(value) }
        default:
            break
        }
        text = ""
    }

    private func setPoster(_ value: String) {
        metadata.posterReference = value
        if let url = URL(string: value), url.scheme != nil {
            metadata.posterURL = url
            return
        }
        let candidate = baseURL.appendingPathComponent(value)
        if FileManager.default.fileExists(atPath: candidate.path) {
            metadata.posterPath = candidate.path
        }
    }
}
