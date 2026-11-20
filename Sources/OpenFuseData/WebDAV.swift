import Foundation
import CryptoKit

public struct WebDAVSource: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var baseURL: URL
    public var username: String

    public init(id: String? = nil, name: String, baseURL: URL, username: String) {
        self.id = id ?? Self.makeID(baseURL: baseURL, username: username)
        self.name = name
        self.baseURL = baseURL
        self.username = username
    }

    public static func makeID(baseURL: URL, username: String) -> String {
        let material = "\(username)@\(baseURL.absoluteString)"
        let digest = SHA256.hash(data: Data(material.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(16))
    }

    /// URL with a trailing slash, used as the root for relative paths.
    public var normalizedBaseURL: URL {
        var string = baseURL.absoluteString
        if !string.hasSuffix("/") { string += "/" }
        return URL(string: string) ?? baseURL
    }
}

public struct RemoteEntry: Codable, Hashable, Identifiable, Sendable {
    public var path: String
    public var name: String
    public var url: URL
    public var isDirectory: Bool
    public var size: Int64
    public var contentType: String?
    public var modifiedAt: Date?
    public var etag: String?

    public var id: String { path }
    public var fileExtension: String { (name as NSString).pathExtension.lowercased() }

    public var isPlayableVideo: Bool {
        let ext = fileExtension
        return ["mkv", "mp4", "m4v", "mov", "ts", "m2ts", "webm", "avi", "flv", "wmv", "iso", "mpg", "mpeg"].contains(ext)
    }

    public init(
        path: String,
        name: String,
        url: URL,
        isDirectory: Bool,
        size: Int64 = 0,
        contentType: String? = nil,
        modifiedAt: Date? = nil,
        etag: String? = nil
    ) {
        self.path = path
        self.name = name
        self.url = url
        self.isDirectory = isDirectory
        self.size = size
        self.contentType = contentType
        self.modifiedAt = modifiedAt
        self.etag = etag
    }
}

public enum WebDAVError: LocalizedError, Sendable {
    case invalidURL
    case unauthorized
    case notFound
    case httpStatus(Int)
    case invalidResponse(String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "来源地址无效"
        case .unauthorized: return "用户名或密码不正确"
        case .notFound: return "路径不存在"
        case .httpStatus(let code): return "服务器返回 HTTP \(code)"
        case .invalidResponse(let message): return "服务器响应无法解析：\(message)"
        case .network(let message): return "网络错误：\(message)"
        }
    }
}

/// Basic-auth WebDAV client. PROPFIND enumerates one directory; GET is used by
/// probes and tests, while libmpv performs the actual ranged streaming.
public actor WebDAVClient {
    public let source: WebDAVSource
    private let password: String
    private let session: URLSession

    public init(source: WebDAVSource, password: String) {
        self.source = source
        self.password = password
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["Accept": "application/xml, text/xml, */*"]
        self.session = URLSession(configuration: configuration)
    }

    public nonisolated var basicAuthorizationHeader: String? {
        guard !source.username.isEmpty || !password.isEmpty else { return nil }
        let token = Data("\(source.username):\(password)".utf8).base64EncodedString()
        return "Basic \(token)"
    }

    public nonisolated func url(for path: String, isDirectory: Bool = false) -> URL {
        var url = source.normalizedBaseURL
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            url.appendPathComponent(String(component), isDirectory: false)
        }
        if isDirectory, !url.absoluteString.hasSuffix("/") {
            url.appendPathComponent("")
        }
        return url
    }

    private func request(url: URL, method: String, body: Data? = nil, depth: String? = nil, range: String? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if !password.isEmpty || !source.username.isEmpty {
            let token = Data("\(source.username):\(password)".utf8).base64EncodedString()
            request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        }
        if let depth { request.setValue(depth, forHTTPHeaderField: "Depth") }
        if let range { request.setValue(range, forHTTPHeaderField: "Range") }
        if method == "PROPFIND" {
            request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    public func list(path: String = "") async throws -> [RemoteEntry] {
        let directoryURL = url(for: path, isDirectory: true)
        let body = Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <d:propfind xmlns:d="DAV:">
          <d:prop>
            <d:displayname/>
            <d:resourcetype/>
            <d:getcontentlength/>
            <d:getcontenttype/>
            <d:getlastmodified/>
            <d:getetag/>
          </d:prop>
        </d:propfind>
        """.utf8)
        let request = request(url: directoryURL, method: "PROPFIND", body: body, depth: "1")
        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else {
            throw WebDAVError.invalidResponse("非 HTTP 响应")
        }
        guard http.statusCode == 207 || http.statusCode == 200 else {
            throw mapStatus(http.statusCode)
        }
        let parser = WebDAVMultistatusParser()
        guard parser.parse(data) else {
            throw WebDAVError.invalidResponse("PROPFIND XML 解析失败")
        }
        return entries(from: parser.responses, requestedPath: path, directoryURL: directoryURL)
    }

    public func fetch(path: String, range: Range<Int64>? = nil) async throws -> (Data, HTTPURLResponse) {
        let fileURL = url(for: path)
        let rangeHeader = range.map { "bytes=\($0.lowerBound)-\($0.upperBound - 1)" }
        let request = request(url: fileURL, method: "GET", range: rangeHeader)
        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else {
            throw WebDAVError.invalidResponse("非 HTTP 响应")
        }
        guard http.statusCode == 200 || http.statusCode == 206 else {
            throw mapStatus(http.statusCode)
        }
        return (data, http)
    }

    public func stat(path: String) async throws -> RemoteEntry? {
        let fileURL = url(for: path)
        let body = Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <d:propfind xmlns:d="DAV:"><d:allprop/></d:propfind>
        """.utf8)
        let request = request(url: fileURL, method: "PROPFIND", body: body, depth: "0")
        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else { return nil }
        guard http.statusCode == 207 || http.statusCode == 200 else { throw mapStatus(http.statusCode) }
        let parser = WebDAVMultistatusParser()
        guard parser.parse(data) else { return nil }
        return entries(from: parser.responses, requestedPath: path, directoryURL: fileURL).first
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                throw mapStatus(http.statusCode)
            }
            return (data, response)
        } catch let error as WebDAVError {
            throw error
        } catch {
            throw WebDAVError.network(error.localizedDescription)
        }
    }

    private func mapStatus(_ code: Int) -> WebDAVError {
        switch code {
        case 401, 403: return .unauthorized
        case 404: return .notFound
        default: return .httpStatus(code)
        }
    }

    private func entries(from responses: [ParsedWebDAVResponse], requestedPath: String, directoryURL: URL) -> [RemoteEntry] {
        let basePath = source.normalizedBaseURL.path
        var result: [RemoteEntry] = []
        for response in responses {
            guard var hrefPath = Self.decodePath(response.href) else { continue }
            if hrefPath.hasPrefix(basePath) {
                hrefPath = String(hrefPath.dropFirst(basePath.count))
            }
            var relative = hrefPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if relative.isEmpty { continue }
            if let queryIndex = relative.firstIndex(of: "?") { relative = String(relative[..<queryIndex]) }
            let name = response.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? (relative as NSString).lastPathComponent
            let entryURL = url(for: relative, isDirectory: response.isCollection)
            result.append(
                RemoteEntry(
                    path: relative,
                    name: name,
                    url: entryURL,
                    isDirectory: response.isCollection,
                    size: response.contentLength ?? 0,
                    contentType: response.contentType,
                    modifiedAt: response.modifiedAt,
                    etag: response.etag
                )
            )
        }
        return result.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory && !rhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    static func decodePath(_ href: String) -> String? {
        var value = href
        if let url = URL(string: href), url.scheme != nil {
            value = url.path
        }
        return value.removingPercentEncoding ?? value
    }

    /// Discover external subtitles that sit next to a remote video and share
    /// its base name. Uses the same matching rules as local sidecars.
    public nonisolated static func subtitleTracks(for video: RemoteEntry, siblings: [RemoteEntry]) -> [SubtitleTrack] {
        let videoBase = (video.name as NSString).deletingPathExtension
        var tracks: [SubtitleTrack] = []
        for sibling in siblings where !sibling.isDirectory {
            guard SubtitleCatalog.subtitleExtensions.contains(sibling.fileExtension) else { continue }
            guard sibling.path != video.path else { continue }
            let siblingBase = (sibling.name as NSString).deletingPathExtension
            guard let match = SubtitleCatalog.matchSubtitleName(siblingBase, videoBase: videoBase) else { continue }
            let language = match.language ?? LanguageTag.infer(from: siblingBase)
            let format = SubtitleFormat(fileExtension: sibling.fileExtension)
            tracks.append(
                SubtitleTrack(
                    id: "remote:" + sibling.path,
                    displayName: SubtitleLabel.make(language: language, format: format, forced: match.forced, includeFormat: true),
                    language: language,
                    format: format,
                    source: .external,
                    url: sibling.url,
                    isForced: match.forced
                )
            )
        }
        return tracks.sorted { lhs, rhs in
            let left = LanguageTag.sortRank(lhs.language)
            let right = LanguageTag.sortRank(rhs.language)
            if left != right { return left < right }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }
}

struct ParsedWebDAVResponse {
    var href: String = ""
    var displayName: String?
    var isCollection = false
    var contentLength: Int64?
    var contentType: String?
    var modifiedAt: Date?
    var etag: String?
}

final class WebDAVMultistatusParser: NSObject, XMLParserDelegate {
    private(set) var responses: [ParsedWebDAVResponse] = []
    private var current: ParsedWebDAVResponse?
    private var text = ""
    private var inResourceType = false

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
        text = ""
        let name = Self.localName(elementName)
        switch name {
        case "response":
            current = ParsedWebDAVResponse()
        case "resourcetype":
            inResourceType = true
        case "collection":
            if inResourceType { current?.isCollection = true }
        default:
            break
        }
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
        let name = Self.localName(elementName)
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "href":
            current?.href = value
        case "displayname":
            current?.displayName = value
        case "getcontentlength":
            current?.contentLength = Int64(value)
        case "getcontenttype":
            current?.contentType = value
        case "getlastmodified":
            current?.modifiedAt = Self.parseHTTPDate(value)
        case "getetag":
            current?.etag = value
        case "resourcetype":
            inResourceType = false
        case "response":
            if let current, !current.href.isEmpty {
                responses.append(current)
            }
            current = nil
        default:
            break
        }
        text = ""
    }

    static func localName(_ element: String) -> String {
        (element.split(separator: ":").last.map(String.init) ?? element).lowercased()
    }

    static func parseHTTPDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: value) { return date }
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter.date(from: value)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
