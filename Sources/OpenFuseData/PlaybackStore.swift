import Foundation

/// One viewing record. `position` is the resume point in seconds; once a file
/// crosses the finished threshold the record keeps a zero position and
/// `isFinished = true`, matching the distinction Infuse makes between
/// "继续观看" and "已看".
public struct PlaybackRecord: Codable, Hashable, Sendable, Identifiable {
    public var mediaPath: String
    public var fileSize: Int64
    public var duration: TimeInterval
    public var position: TimeInterval
    public var lastPlayedAt: Date
    public var isFinished: Bool
    public var playCount: Int
    public var preferredAudioTrackID: String?
    public var preferredSubtitleTrackID: String?
    public var displayTitle: String?
    public var sourceKind: String?
    public var sourceID: String?
    public var remotePath: String?
    public var remoteURL: String?

    public var id: String { mediaPath }
    public var url: URL {
        if let remoteURL, let url = URL(string: remoteURL) { return url }
        return URL(fileURLWithPath: mediaPath)
    }
    public var isRemote: Bool { sourceKind == "webdav" || sourceKind == "jellyfin" }

    public init(
        mediaPath: String,
        fileSize: Int64 = 0,
        duration: TimeInterval = 0,
        position: TimeInterval = 0,
        lastPlayedAt: Date = Date(),
        isFinished: Bool = false,
        playCount: Int = 0,
        preferredAudioTrackID: String? = nil,
        preferredSubtitleTrackID: String? = nil,
        displayTitle: String? = nil,
        sourceKind: String? = nil,
        sourceID: String? = nil,
        remotePath: String? = nil,
        remoteURL: String? = nil
    ) {
        self.mediaPath = mediaPath
        self.fileSize = fileSize
        self.duration = duration
        self.position = position
        self.lastPlayedAt = lastPlayedAt
        self.isFinished = isFinished
        self.playCount = playCount
        self.preferredAudioTrackID = preferredAudioTrackID
        self.preferredSubtitleTrackID = preferredSubtitleTrackID
        self.displayTitle = displayTitle
        self.sourceKind = sourceKind
        self.sourceID = sourceID
        self.remotePath = remotePath
        self.remoteURL = remoteURL
    }
}

public enum ResumePolicy {
    /// Below this, restarting from zero is less annoying than resuming.
    public static let minimumResumePosition: TimeInterval = 5
    /// Do not offer to resume within this many seconds of the end.
    public static let endGuard: TimeInterval = 10
    /// Fraction of duration that marks a file watched.
    public static let finishedFraction: Double = 0.95

    public static func isFinished(position: TimeInterval, duration: TimeInterval) -> Bool {
        guard duration > 0 else { return false }
        if position >= duration - 1 { return true }
        return position / duration >= finishedFraction
    }

    public static func resumePosition(for record: PlaybackRecord) -> TimeInterval? {
        guard !record.isFinished, record.duration > 0 else { return nil }
        guard record.position >= minimumResumePosition else { return nil }
        let scaledGuard = record.duration < 60 ? max(1, record.duration * 0.1) : endGuard
        guard record.position < record.duration - scaledGuard else { return nil }
        return record.position
    }
}

/// JSON-backed viewing store. SQLite arrives with the library index in M3; the
/// on-disk format is versioned so that migration is mechanical.
public final class PlaybackStore: @unchecked Sendable {
    public struct Snapshot: Codable, Sendable {
        public var version: Int = 1
        public var records: [String: PlaybackRecord] = [:]
    }

    private let fileURL: URL
    private var snapshot: Snapshot
    private var isDirty = false
    private let lock = NSLock()

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("playback.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder.openFuse.decode(Snapshot.self, from: data) {
            self.snapshot = decoded
        } else {
            self.snapshot = Snapshot()
        }
    }

    public func record(forPath path: String) -> PlaybackRecord? {
        lock.lock(); defer { lock.unlock() }
        return snapshot.records[path]
    }

    public func allRecords() -> [PlaybackRecord] {
        lock.lock(); defer { lock.unlock() }
        return snapshot.records.values.sorted { $0.lastPlayedAt > $1.lastPlayedAt }
    }

    public func recentlyPlayed(limit: Int = 20) -> [PlaybackRecord] {
        Array(allRecords().prefix(limit))
    }

    /// Merge remote records with local state. Newer lastPlayedAt wins; local
    /// wins ties so an in-flight local pause is not clobbered.
    @discardableResult
    public func merge(records: [PlaybackRecord]) throws -> Int {
        lock.lock(); defer { lock.unlock() }
        var changed = 0
        for record in records {
            if let local = snapshot.records[record.mediaPath] {
                guard record.lastPlayedAt > local.lastPlayedAt else { continue }
            }
            snapshot.records[record.mediaPath] = record
            changed += 1
        }
        if changed > 0 { isDirty = true; try flushLocked() }
        return changed
    }

    /// Persist a progress update. A finished position wins over an older
    /// unfinished one, but an explicitly unfinished update (user restarted)
    /// clears the finished flag.
    @discardableResult
    public func update(
        fingerprint: MediaFingerprint,
        duration: TimeInterval,
        position: TimeInterval,
        displayTitle: String? = nil,
        audioTrackID: String? = nil,
        subtitleTrackID: String? = nil,
        finished: Bool? = nil,
        sourceKind: String? = nil,
        sourceID: String? = nil,
        remotePath: String? = nil,
        remoteURL: String? = nil
    ) -> PlaybackRecord {
        lock.lock(); defer { lock.unlock() }
        let key = fingerprint.resumeKey
        var record = snapshot.records[key] ?? PlaybackRecord(mediaPath: key)
        record.fileSize = fingerprint.fileSize
        record.duration = max(duration, record.duration)
        record.lastPlayedAt = Date()
        if let displayTitle { record.displayTitle = displayTitle }
        if let audioTrackID { record.preferredAudioTrackID = audioTrackID }
        if let subtitleTrackID { record.preferredSubtitleTrackID = subtitleTrackID }
        if let sourceKind { record.sourceKind = sourceKind }
        if let sourceID { record.sourceID = sourceID }
        if let remotePath { record.remotePath = remotePath }
        if let remoteURL { record.remoteURL = remoteURL }

        let resolvedFinished = finished ?? ResumePolicy.isFinished(position: position, duration: record.duration)
        if resolvedFinished {
            record.isFinished = true
            record.position = 0
            record.playCount += 1
        } else {
            record.isFinished = false
            record.position = max(0, position)
        }
        snapshot.records[key] = record
        isDirty = true
        try? flushLocked()
        return record
    }

    public func markUnwatched(path: String) {
        lock.lock(); defer { lock.unlock() }
        guard var record = snapshot.records[path] else { return }
        record.isFinished = false
        record.position = 0
        record.lastPlayedAt = Date()
        snapshot.records[path] = record
        isDirty = true
        try? flushLocked()
    }

    public func remove(path: String) {
        lock.lock(); defer { lock.unlock() }
        snapshot.records.removeValue(forKey: path)
        isDirty = true
        try? flushLocked()
    }

    public func flush() throws {
        lock.lock(); defer { lock.unlock() }
        try flushLocked()
    }

    private func flushLocked() throws {
        guard isDirty else { return }
        let data = try JSONEncoder.openFuse.encode(snapshot)
        let temporary = fileURL.appendingPathExtension("tmp")
        try data.write(to: temporary, options: .atomic)
        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporary)
        isDirty = false
    }

    public var storageURL: URL {
        lock.lock(); defer { lock.unlock() }
        return fileURL
    }
}

extension JSONEncoder {
    public static var openFuse: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.openFuseISO.string(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    public static var openFuse: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = ISO8601DateFormatter.openFuseFractional.date(from: value) { return date }
            if let date = ISO8601DateFormatter.openFusePlain.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "invalid ISO8601 date: \(value)")
        }
        return decoder
    }
}

private extension ISO8601DateFormatter {
    static let openFuseFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    static let openFusePlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private extension JSONEncoder {
    static let openFuseISO: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
