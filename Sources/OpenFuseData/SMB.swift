#if os(macOS)
import CSMB2
import CryptoKit
import Foundation

public struct SMBSource: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var server: String
    public var port: Int
    public var share: String
    public var username: String
    public var basePath: String

    public init(
        id: String? = nil,
        name: String,
        server: String,
        port: Int = 445,
        share: String,
        username: String,
        basePath: String = ""
    ) {
        self.id = id ?? Self.makeID(server: server, share: share, username: username)
        self.name = name
        self.server = server
        self.port = port
        self.share = share
        self.username = username
        self.basePath = basePath
    }

    public static func makeID(server: String, share: String, username: String) -> String {
        let material = "smb|\(username)@\(server)/\(share)"
        let digest = SHA256.hash(data: Data(material.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    public var rootPath: String {
        let trimmed = basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? "/" : "/" + trimmed
    }
}

public struct SMBEntry: Hashable, Sendable {
    public var name: String
    public var path: String
    public var isDirectory: Bool
    public var size: Int64
    public var modifiedAt: Date?
}

public enum SMBError: LocalizedError, Sendable {
    case context
    case parseURL(String)
    case operation(String)

    public var errorDescription: String? {
        switch self {
        case .context: return "SMB 初始化失败"
        case .parseURL(let message): return "SMB 地址解析失败：\(message)"
        case .operation(let message): return "SMB 操作失败：\(message)"
        }
    }
}

public final class SMBClient: @unchecked Sendable {
    public let source: SMBSource
    private let password: String
    private var context: OpaquePointer?
    private var handles: [String: OpaquePointer] = [:]
    private let lock = NSLock()

    public init(source: SMBSource, password: String) {
        self.source = source
        self.password = password
    }

    deinit {
        for (_, handle) in handles {
            if let context { _ = smb2_close(context, handle) }
        }
        if let context {
            smb2_destroy_context(context)
        }
    }

    private func connectedContext() throws -> OpaquePointer {
        lock.lock(); defer { lock.unlock() }
        if let context { return context }
        guard let context = smb2_init_context() else { throw SMBError.context }
        smb2_set_timeout(context, 20)
        var urlPath = "smb://"
        if !source.username.isEmpty {
            urlPath += source.username + "@"
        }
        urlPath += "\(source.server):\(source.port)/\(source.share)/"
        guard let parsed = smb2_parse_url(context, urlPath) else {
            let message = String(cString: smb2_get_error(context))
            smb2_destroy_context(context)
            throw SMBError.parseURL(message)
        }
        let server = parsed.pointee.server.map { String(cString: $0) } ?? source.server
        let share = parsed.pointee.share.map { String(cString: $0) } ?? source.share
        smb2_set_user(context, source.username)
        smb2_set_password(context, password)
        let result = smb2_connect_share(context, server, share, source.username)
        smb2_destroy_url(parsed)
        guard result == 0 else {
            let message = String(cString: smb2_get_error(context))
            smb2_destroy_context(context)
            throw SMBError.operation(message)
        }
        self.context = context
        return context
    }

    public func list(path: String? = nil) throws -> [SMBEntry] {
        let context = try connectedContext()
        lock.lock(); defer { lock.unlock() }
        let smbPath = Self.normalized(path ?? source.rootPath)
        guard let directory = smb2_opendir(context, smbPath) else {
            throw SMBError.operation(String(cString: smb2_get_error(context)))
        }
        defer { smb2_closedir(context, directory) }
        var entries: [SMBEntry] = []
        while let entry = smb2_readdir(context, directory) {
            let name = String(cString: entry.pointee.name)
            guard name != ".", name != ".." else { continue }
            let isDirectory = entry.pointee.st.smb2_type == SMB2_TYPE_DIRECTORY
            let modified = entry.pointee.st.smb2_mtime > 0
                ? Date(timeIntervalSince1970: TimeInterval(entry.pointee.st.smb2_mtime))
                : nil
            entries.append(
                SMBEntry(
                    name: name,
                    path: Self.join(smbPath, name),
                    isDirectory: isDirectory,
                    size: Int64(entry.pointee.st.smb2_size),
                    modifiedAt: modified
                )
            )
        }
        return entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func handleLocked(_ smbPath: String, context: OpaquePointer) throws -> OpaquePointer {
        if let handle = handles[smbPath] { return handle }
        guard let handle = smb2_open(context, smbPath, 0) else {
            throw SMBError.operation(String(cString: smb2_get_error(context)))
        }
        handles[smbPath] = handle
        return handle
    }

    public func reconnect() {
        lock.lock(); defer { lock.unlock() }
        if let context {
            for (_, handle) in handles {
                _ = smb2_close(context, handle)
            }
            smb2_destroy_context(context)
        }
        handles.removeAll()
        context = nil
    }

    public func closeHandles() {
        lock.lock(); defer { lock.unlock() }
        guard let context else { handles.removeAll(); return }
        for (_, handle) in handles {
            _ = smb2_close(context, handle)
        }
        handles.removeAll()
    }

    public func size(path: String) throws -> Int64 {
        let context = try connectedContext()
        lock.lock(); defer { lock.unlock() }
        let smbPath = Self.normalized(path)
        var stat = smb2_stat_64()
        guard smb2_stat(context, smbPath, &stat) == 0 else {
            throw SMBError.operation(String(cString: smb2_get_error(context)))
        }
        return Int64(stat.smb2_size)
    }

    public func fetch(path: String) throws -> Data {
        let context = try connectedContext()
        lock.lock(); defer { lock.unlock() }
        let smbPath = Self.normalized(path)
        var stat = smb2_stat_64()
        let expected = smb2_stat(context, smbPath, &stat) == 0 ? Int64(stat.smb2_size) : -1
        let handle = try handleLocked(smbPath, context: context)
        var data = Data()
        var offset: UInt64 = 0
        let chunkSize: UInt32 = 64 * 1024
        var buffer = [UInt8](repeating: 0, count: Int(chunkSize))
        while true {
            let count = buffer.withUnsafeMutableBytes { raw in
                smb2_pread(context, handle, raw.baseAddress!.assumingMemoryBound(to: UInt8.self), chunkSize, offset)
            }
            if count < 0 {
                // impacket/libsmb2 can report a malformed EOF error after the
                // final byte; accept a complete file by stat size.
                if expected >= 0, data.count >= Int(expected) { break }
                throw SMBError.operation(String(cString: smb2_get_error(context)))
            }
            if count == 0 { break }
            data.append(buffer, count: Int(count))
            offset += UInt64(count)
            if expected >= 0, data.count >= Int(expected) { break }
        }
        return data
    }

    public func read(path: String, offset: Int64, length: Int) throws -> Data {
        let context = try connectedContext()
        lock.lock(); defer { lock.unlock() }
        let smbPath = Self.normalized(path)
        let handle = try handleLocked(smbPath, context: context)
        var result = Data()
        var position = offset
        var remaining = max(0, length)
        while remaining > 0 {
            let chunk = min(remaining, 1 << 20)
            var buffer = [UInt8](repeating: 0, count: chunk)
            let count = buffer.withUnsafeMutableBytes { raw in
                smb2_pread(
                    context, handle,
                    raw.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    UInt32(chunk), UInt64(position)
                )
            }
            guard count >= 0 else {
                throw SMBError.operation(String(cString: smb2_get_error(context)))
            }
            if count == 0 { break }
            result.append(contentsOf: buffer.prefix(Int(count)))
            position += Int64(count)
            remaining -= Int(count)
            if Int(count) < chunk {
                // Short read can happen near EOF or with server chunk limits;
                // keep requesting until EOF/complete instead of returning early.
                continue
            }
        }
        return result
    }

    private static func normalized(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? "/" : "/" + trimmed
    }

    private static func join(_ base: String, _ name: String) -> String {
        if base == "/" { return "/" + name }
        return base + "/" + name
    }
}

public final class SMBSourceStore: @unchecked Sendable {
    private struct Snapshot: Codable {
        var version: Int = 1
        var sources: [SMBSource] = []
    }

    private let fileURL: URL
    private var snapshot: Snapshot
    private let lock = NSLock()

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("smb-sources.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder.openFuse.decode(Snapshot.self, from: data) {
            self.snapshot = decoded
        } else {
            self.snapshot = Snapshot()
        }
    }

    public var sources: [SMBSource] {
        lock.lock(); defer { lock.unlock() }
        return snapshot.sources
    }

    public func upsert(_ source: SMBSource) throws {
        lock.lock(); defer { lock.unlock() }
        if let index = snapshot.sources.firstIndex(where: { $0.id == source.id }) {
            snapshot.sources[index] = source
        } else {
            snapshot.sources.append(source)
        }
        try flushLocked()
    }

    public func remove(id: String) throws {
        lock.lock(); defer { lock.unlock() }
        snapshot.sources.removeAll { $0.id == id }
        try flushLocked()
    }

    private func flushLocked() throws {
        let data = try JSONEncoder.openFuse.encode(snapshot)
        let temporary = fileURL.appendingPathExtension("tmp")
        try data.write(to: temporary, options: .atomic)
        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporary)
    }
}

public enum SMBLibraryScanner {
    public static func scan(
        source: SMBSource,
        client: SMBClient,
        posterCacheDirectory: URL? = nil,
        token: ScanCancellationToken? = nil,
        progress: ((Int) -> Void)? = nil
    ) throws -> ScannedLibrary {
        var queue = [source.rootPath]
        var candidates: [LibraryScanner.FileCandidate] = []
        var visited = 0
        var failedPaths: [String] = []
        var downloadedPosters = 0
        var showNFOByDirectory: [String: NFOMetadata] = [:]
        var showPosterByDirectory: [String: String] = [:]
        if let posterCacheDirectory {
            try? FileManager.default.createDirectory(at: posterCacheDirectory, withIntermediateDirectories: true)
        }

        func cachePoster(_ remotePath: String) -> String? {
            guard let posterCacheDirectory, downloadedPosters < 300 else { return nil }
            let ext = (remotePath as NSString).pathExtension.lowercased()
            let suffix = ["jpg", "jpeg", "png", "webp"].contains(ext) ? ext : "jpg"
            let target = posterCacheDirectory.appendingPathComponent(LibraryID.hash(remotePath) + "." + suffix)
            if FileManager.default.fileExists(atPath: target.path) {
                downloadedPosters += 1
                return target.path
            }
            guard let data = try? client.fetch(path: remotePath), !data.isEmpty else { return nil }
            try? data.write(to: target, options: .atomic)
            downloadedPosters += 1
            return target.path
        }

        func listDirectory(_ path: String) throws -> [SMBEntry] {
            do {
                return try client.list(path: path)
            } catch {
                client.reconnect()
                return try client.list(path: path)
            }
        }

        func fetchWithRetry(_ path: String) -> Data? {
            if let data = try? client.fetch(path: path) { return data }
            client.reconnect()
            return try? client.fetch(path: path)
        }

        func videoInfo(_ entry: SMBEntry) -> (resolution: String?, dynamicRange: String?)? {
            let ext = (entry.name as NSString).pathExtension.lowercased()
            guard entry.size > 1024 else { return nil }
            if ["mkv", "webm"].contains(ext) {
                let length = Int(min(2_000_000, entry.size))
                guard let data = try? client.read(path: entry.path, offset: 0, length: length),
                      let info = MatroskaProbe.parse(data) else { return nil }
                return (info.resolution, info.dynamicRange)
            }
            if ["mp4", "m4v", "mov"].contains(ext) {
                let headLength = Int(min(4_000_000, entry.size))
                if let data = try? client.read(path: entry.path, offset: 0, length: headLength),
                   let info = MP4Probe.parse(data) {
                    return (info.resolution, info.dynamicRange)
                }
                if entry.size > 4_000_000 {
                    let tailLength = Int(min(8_000_000, entry.size))
                    if let data = try? client.read(
                        path: entry.path, offset: entry.size - Int64(tailLength), length: tailLength
                    ), let info = MP4Probe.parse(data) {
                        return (info.resolution, info.dynamicRange)
                    }
                }
            }
            return nil
        }

        func contentFingerprint(_ entry: SMBEntry) -> String? {
            guard entry.size > 0 else { return nil }
            let chunk = Int64(ContentFingerprint.chunkSize)
            let firstLength = Int(min(chunk, entry.size))
            guard let first = try? client.read(path: entry.path, offset: 0, length: firstLength),
                  !first.isEmpty else { return nil }
            var last: Data?
            if entry.size > chunk {
                last = try? client.read(path: entry.path, offset: entry.size - chunk, length: Int(chunk))
            }
            return ContentFingerprint.key(size: entry.size, first: first, last: last)
        }

        while !queue.isEmpty {
            if token?.isCancelled == true { throw LibraryScanError.cancelled }
            let directory = queue.removeFirst()
            let entries: [SMBEntry]
            do {
                entries = try listDirectory(directory)
            } catch {
                failedPaths.append(directory)
                continue
            }
            progress?(visited)
            for entry in entries where entry.isDirectory {
                queue.append(entry.path)
            }

            let directoryKey = directory
            var movieNFO: NFOMetadata?
            var showNFO: NFOMetadata?
            var nfoByBase: [String: NFOMetadata] = [:]
            var posterByBase: [String: String] = [:]
            var directoryPoster: String?

            for entry in entries where !entry.isDirectory {
                let ext = (entry.name as NSString).pathExtension.lowercased()
                let base = (entry.name as NSString).deletingPathExtension.lowercased()
                if ext == "nfo", let data = fetchWithRetry(entry.path) {
                    let metadata = NFOReader.parse(
                        data: data,
                        baseURL: URL(fileURLWithPath: "/smb/" + entry.path.deletingLeadingSlash)
                    )
                    if let metadata {
                        if base == "tvshow" { showNFO = metadata }
                        else if base == "movie" { movieNFO = metadata }
                        else { nfoByBase[base] = metadata }
                    }
                } else if ["jpg", "jpeg", "png", "webp"].contains(ext) {
                    if ["poster", "folder", "cover"].contains(base) {
                        directoryPoster = cachePoster(entry.path) ?? directoryPoster
                    }
                    posterByBase[base] = entry.path
                }
            }

            if let showNFO {
                showNFOByDirectory[directory] = showNFO
            }
            if let directoryPoster {
                showPosterByDirectory[directory] = directoryPoster
            }

            func showContext(for start: String) -> (metadata: NFOMetadata, directory: String)? {
                var current = start
                while !current.isEmpty, current != "/" {
                    if let metadata = showNFOByDirectory[current] {
                        return (metadata, current)
                    }
                    current = (current as NSString).deletingLastPathComponent
                }
                return nil
            }

            for entry in entries where !entry.isDirectory {
                guard LibraryScanner.videoExtensions.contains(
                    (entry.name as NSString).pathExtension.lowercased()
                ) else { continue }
                visited += 1
                let base = (entry.name as NSString).deletingPathExtension
                let lowerBase = base.lowercased()
                let nfo = nfoByBase[lowerBase] ?? movieNFO
                let context = showContext(for: directory)
                let effectiveShowNFO = context?.metadata
                let showDirectory = context?.directory ?? directory
                var posterPath = directoryPoster ?? showPosterByDirectory[showDirectory]
                var posterURL: String?
                if let reference = nfo?.posterReference ?? effectiveShowNFO?.posterReference, !reference.isEmpty {
                    if reference.hasPrefix("http://") || reference.hasPrefix("https://") {
                        posterURL = reference
                    } else {
                        let baseDirectory = nfo != nil ? directory : showDirectory
                        let remotePoster = baseDirectory + "/" + reference
                        if let cached = cachePoster(remotePoster) {
                            posterPath = cached
                        } else {
                            posterURL = "smb://\(source.server)/\(source.share)\(remotePoster)"
                        }
                    }
                } else if let remote = posterByBase[lowerBase] ?? directoryPoster {
                    posterPath = cachePoster(remote) ?? posterPath
                }
                let header = videoInfo(entry)
                candidates.append(
                    LibraryScanner.FileCandidate(
                        relativePath: entry.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                        name: entry.name,
                        fileURL: nil,
                        remotePath: entry.path,
                        posterPath: posterPath,
                        posterURL: posterURL,
                        nfo: nfo,
                        showNFO: effectiveShowNFO,
                        modifiedAt: entry.modifiedAt,
                        resolution: header?.resolution,
                        dynamicRange: header?.dynamicRange,
                        contentKey: contentFingerprint(entry)
                    )
                )
            }
            _ = directoryKey
        }
        guard !candidates.isEmpty else { throw LibraryScanError.noMedia }
        return LibraryScanner.buildLibrary(
            candidates: candidates,
            sourceKind: "smb",
            sourceID: source.id,
            sourceName: source.name,
            failedPaths: failedPaths
        )
    }
}

#endif


private extension String {
    var deletingLeadingSlash: String {
        hasPrefix("/") ? String(dropFirst()) : self
    }
}
