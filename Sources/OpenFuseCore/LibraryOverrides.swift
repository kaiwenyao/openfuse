import Foundation

public struct LibraryOverride: Codable, Hashable, Sendable {
    public var workID: String
    public var title: String?
    public var year: Int?
    public var overview: String?
    public var poster: String?
    public var updatedAt: Date

    public init(
        workID: String,
        title: String? = nil,
        year: Int? = nil,
        overview: String? = nil,
        poster: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.workID = workID
        self.title = title
        self.year = year
        self.overview = overview
        self.poster = poster
        self.updatedAt = updatedAt
    }
}

public final class LibraryOverrideStore: @unchecked Sendable {
    private struct Snapshot: Codable {
        var version: Int = 1
        var overrides: [LibraryOverride] = []
    }

    private let fileURL: URL
    private var snapshot: Snapshot
    private let lock = NSLock()

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("library-overrides.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder.openFuse.decode(Snapshot.self, from: data) {
            self.snapshot = decoded
        } else {
            self.snapshot = Snapshot()
        }
    }

    public var all: [String: LibraryOverride] {
        lock.lock(); defer { lock.unlock() }
        return Dictionary(uniqueKeysWithValues: snapshot.overrides.map { ($0.workID, $0) })
    }

    public func upsert(_ override: LibraryOverride) throws {
        lock.lock(); defer { lock.unlock() }
        if let index = snapshot.overrides.firstIndex(where: { $0.workID == override.workID }) {
            snapshot.overrides[index] = override
        } else {
            snapshot.overrides.append(override)
        }
        try flushLocked()
    }

    public func remove(workID: String) throws {
        lock.lock(); defer { lock.unlock() }
        snapshot.overrides.removeAll { $0.workID == workID }
        try flushLocked()
    }

    private func flushLocked() throws {
        let data = try JSONEncoder.openFuse.encode(snapshot)
        let temporary = fileURL.appendingPathExtension("tmp")
        try data.write(to: temporary, options: .atomic)
        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporary)
    }
}

public extension LibraryOverride {
    func apply(to work: LibraryWork) -> LibraryWork {
        var result = work
        if let title, !title.isEmpty {
            result.title = title
            result.sortTitle = title
        }
        if let year { result.year = year }
        if let overview, !overview.isEmpty { result.overview = overview }
        if let poster, !poster.isEmpty { result.poster = poster }
        return result
    }
}
