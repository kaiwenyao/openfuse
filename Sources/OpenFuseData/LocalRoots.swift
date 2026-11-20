import Foundation

public struct LocalRoot: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var path: String
    public var name: String

    public init(path: String, name: String) {
        self.path = path
        self.name = name
        self.id = "local-" + LibraryID.hash(path).replacingOccurrences(of: "local-", with: "")
    }
}

public final class LocalRootStore: @unchecked Sendable {
    private struct Snapshot: Codable {
        var version: Int = 1
        var roots: [LocalRoot] = []
    }

    private let fileURL: URL
    private var snapshot: Snapshot
    private let lock = NSLock()

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("local-roots.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder.openFuse.decode(Snapshot.self, from: data) {
            snapshot = decoded
        } else {
            snapshot = Snapshot()
        }
    }

    public var roots: [LocalRoot] {
        lock.lock(); defer { lock.unlock() }
        return snapshot.roots
    }

    @discardableResult
    public func upsert(path: String, name: String) throws -> LocalRoot {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        let root = LocalRoot(path: standardized, name: name)
        lock.lock(); defer { lock.unlock() }
        if let index = snapshot.roots.firstIndex(where: { $0.id == root.id }) {
            snapshot.roots[index] = root
        } else {
            snapshot.roots.append(root)
        }
        snapshot.roots.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        try flushLocked()
        return root
    }

    public func remove(id: String) throws {
        lock.lock(); defer { lock.unlock() }
        snapshot.roots.removeAll { $0.id == id }
        try flushLocked()
    }

    private func flushLocked() throws {
        let data = try JSONEncoder.openFuse.encode(snapshot)
        let temporary = fileURL.appendingPathExtension("tmp")
        try data.write(to: temporary, options: .atomic)
        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporary)
    }
}
