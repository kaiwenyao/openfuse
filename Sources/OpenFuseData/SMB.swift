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
    private let lock = NSLock()

    public init(source: SMBSource, password: String) {
        self.source = source
        self.password = password
    }

    deinit {
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

    public func fetch(path: String) throws -> Data {
        let context = try connectedContext()
        lock.lock(); defer { lock.unlock() }
        let smbPath = Self.normalized(path)
        var stat = smb2_stat_64()
        let expected = smb2_stat(context, smbPath, &stat) == 0 ? Int64(stat.smb2_size) : -1
        guard let handle = smb2_open(context, smbPath, 0) else {
            throw SMBError.operation(String(cString: smb2_get_error(context)))
        }
        defer { _ = smb2_close(context, handle) }
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
        guard let handle = smb2_open(context, smbPath, 0) else {
            throw SMBError.operation(String(cString: smb2_get_error(context)))
        }
        defer { _ = smb2_close(context, handle) }
        var buffer = [UInt8](repeating: 0, count: max(0, length))
        let count = buffer.withUnsafeMutableBytes { raw in
            smb2_pread(context, handle, raw.baseAddress!.assumingMemoryBound(to: UInt8.self), UInt32(length), UInt64(offset))
        }
        guard count >= 0 else {
            throw SMBError.operation(String(cString: smb2_get_error(context)))
        }
        return Data(buffer.prefix(Int(count)))
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
        token: ScanCancellationToken? = nil,
        progress: ((Int) -> Void)? = nil
    ) throws -> ScannedLibrary {
        var queue = [source.rootPath]
        var candidates: [LibraryScanner.FileCandidate] = []
        var visited = 0
        var failedPaths: [String] = []
        while !queue.isEmpty {
            if token?.isCancelled == true { throw LibraryScanError.cancelled }
            let directory = queue.removeFirst()
            let entries: [SMBEntry]
            do {
                entries = try client.list(path: directory)
            } catch {
                failedPaths.append(directory)
                continue
            }
            progress?(visited)
            for entry in entries where entry.isDirectory {
                queue.append(entry.path)
            }
            for entry in entries where !entry.isDirectory {
                guard LibraryScanner.videoExtensions.contains(
                    (entry.name as NSString).pathExtension.lowercased()
                ) else { continue }
                visited += 1
                candidates.append(
                    LibraryScanner.FileCandidate(
                        relativePath: entry.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                        name: entry.name,
                        fileURL: nil,
                        remotePath: entry.path,
                        posterPath: nil,
                        posterURL: nil,
                        nfo: nil,
                        showNFO: nil,
                        modifiedAt: entry.modifiedAt,
                        resolution: nil
                    )
                )
            }
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
