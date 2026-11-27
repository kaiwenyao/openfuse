import Foundation

/// Persisted WebDAV source metadata. Passwords live in the Keychain, keyed by
/// the source id.
public final class SourceStore: @unchecked Sendable {
    public struct Snapshot: Codable, Sendable {
        public var version: Int = 1
        public var sources: [WebDAVSource] = []
    }

    private let fileURL: URL
    private var snapshot: Snapshot
    private let lock = NSLock()

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("sources.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder.openFuse.decode(Snapshot.self, from: data) {
            self.snapshot = decoded
        } else {
            self.snapshot = Snapshot()
        }
    }

    public var sources: [WebDAVSource] {
        lock.lock(); defer { lock.unlock() }
        return snapshot.sources
    }

    public func upsert(_ source: WebDAVSource) throws {
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

/// Result of adding a source.
///
/// The connection can succeed while a follow-up step still needs to be told to
/// the user — a Keychain write that failed leaves a source that only works for
/// this run. Returning the warning lets the form show it before it closes,
/// instead of relying on a shell-level message that a `dismiss()` swallows.
public struct SourceAddOutcome<Source> {
    public let source: Source
    public let warning: String?

    public init(source: Source, warning: String? = nil) {
        self.source = source
        self.warning = warning
    }

    public var hasWarning: Bool {
        guard let warning else { return false }
        return !warning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// What a source form does once `addSource` returns.
///
/// Kept out of the view so the three cases — close, show the failure in place,
/// or hold the form open with a warning the user must acknowledge — are directly
/// testable.
public enum SourceFormStep: Equatable, Sendable {
    case close
    case showError(String)
    case showWarning(String)

    public static func step<Source>(
        for outcome: SourceAddOutcome<Source>?,
        statusMessage: String?
    ) -> SourceFormStep {
        guard let outcome else {
            if let statusMessage, !statusMessage.isEmpty { return .showError(statusMessage) }
            return .showError("连接失败")
        }
        if let warning = outcome.warning, outcome.hasWarning { return .showWarning(warning) }
        return .close
    }
}
