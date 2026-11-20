import CloudKit
import Foundation

public protocol ProgressSyncTransport: Sendable {
    func fetchAll() async throws -> [PlaybackRecord]
    func push(_ records: [PlaybackRecord]) async throws
}

/// File-backed transport used by tests and local two-device simulation.
public final class LocalProgressTransport: ProgressSyncTransport, @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func fetchAll() async throws -> [PlaybackRecord] {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder.openFuse.decode([PlaybackRecord].self, from: data)) ?? []
    }

    public func push(_ records: [PlaybackRecord]) async throws {
        lock.lock(); defer { lock.unlock() }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.openFuse.encode(records)
        try data.write(to: fileURL, options: .atomic)
    }
}

public enum ProgressSyncError: LocalizedError {
    case cloudKitUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .cloudKitUnavailable(let message): return "CloudKit 不可用：\(message)"
        }
    }
}

/// CloudKit private database transport. A signed app with the iCloud container
/// entitlement is required; without it operations fail and callers fall back to
/// local-only playback. The record shape matches the local PlaybackRecord.
public final class CloudKitProgressTransport: ProgressSyncTransport, @unchecked Sendable {
    public static let recordType = "PlaybackProgress"
    private let container: CKContainer
    private let database: CKDatabase

    public init(containerIdentifier: String) {
        self.container = CKContainer(identifier: containerIdentifier)
        self.database = container.privateCloudDatabase
    }

    public func fetchAll() async throws -> [PlaybackRecord] {
        let status = try await container.accountStatus()
        guard status == .available else {
            throw ProgressSyncError.cloudKitUnavailable("account status \(status.rawValue)")
        }
        let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
        var records: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        repeat {
            let result: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
            if let cursor {
                result = try await database.records(continuingMatchFrom: cursor)
            } else {
                result = try await database.records(matching: query)
            }
            for (_, value) in result.matchResults {
                if case .success(let record) = value { records.append(record) }
            }
            cursor = result.queryCursor
        } while cursor != nil
        return records.compactMap(Self.playbackRecord(from:))
    }

    public func push(_ records: [PlaybackRecord]) async throws {
        let cloudRecords = records.map(Self.cloudRecord(from:))
        _ = try await database.modifyRecords(saving: cloudRecords, deleting: [])
    }

    private static func recordID(for mediaPath: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "progress-" + LibraryID.hash(mediaPath))
    }

    private static func cloudRecord(from record: PlaybackRecord) -> CKRecord {
        let cloud = CKRecord(recordType: recordType, recordID: recordID(for: record.mediaPath))
        cloud["mediaPath"] = record.mediaPath as CKRecordValue
        cloud["fileSize"] = record.fileSize as CKRecordValue
        cloud["duration"] = record.duration as CKRecordValue
        cloud["position"] = record.position as CKRecordValue
        cloud["lastPlayedAt"] = record.lastPlayedAt as CKRecordValue
        cloud["isFinished"] = (record.isFinished ? 1 : 0) as CKRecordValue
        cloud["playCount"] = record.playCount as CKRecordValue
        if let value = record.displayTitle { cloud["displayTitle"] = value as CKRecordValue }
        if let value = record.sourceKind { cloud["sourceKind"] = value as CKRecordValue }
        if let value = record.sourceID { cloud["sourceID"] = value as CKRecordValue }
        if let value = record.remotePath { cloud["remotePath"] = value as CKRecordValue }
        if let value = record.remoteURL { cloud["remoteURL"] = value as CKRecordValue }
        return cloud
    }

    private static func playbackRecord(from cloud: CKRecord) -> PlaybackRecord? {
        guard let mediaPath = cloud["mediaPath"] as? String,
              let duration = cloud["duration"] as? Double,
              let position = cloud["position"] as? Double,
              let lastPlayedAt = cloud["lastPlayedAt"] as? Date else { return nil }
        return PlaybackRecord(
            mediaPath: mediaPath,
            fileSize: cloud["fileSize"] as? Int64 ?? 0,
            duration: duration,
            position: position,
            lastPlayedAt: lastPlayedAt,
            isFinished: (cloud["isFinished"] as? Int64 ?? 0) != 0,
            playCount: Int(cloud["playCount"] as? Int64 ?? 0),
            displayTitle: cloud["displayTitle"] as? String,
            sourceKind: cloud["sourceKind"] as? String,
            sourceID: cloud["sourceID"] as? String,
            remotePath: cloud["remotePath"] as? String,
            remoteURL: cloud["remoteURL"] as? String
        )
    }
}

public struct ProgressSyncResult: Sendable {
    public var remoteCount: Int
    public var localCount: Int
    public var changed: Int
}

public actor ProgressSyncService {
    private let store: PlaybackStore
    private let transport: ProgressSyncTransport

    public init(store: PlaybackStore, transport: ProgressSyncTransport) {
        self.store = store
        self.transport = transport
    }

    public func sync() async throws -> ProgressSyncResult {
        let remote = try await transport.fetchAll()
        let changed = try store.merge(records: remote)
        let local = store.allRecords()
        try await transport.push(local)
        return ProgressSyncResult(remoteCount: remote.count, localCount: local.count, changed: changed)
    }
}
