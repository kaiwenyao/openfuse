import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class LibraryStore: @unchecked Sendable {
    private var database: OpaquePointer?
    private let lock = NSLock()
    public let fileURL: URL

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("library.sqlite")
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(fileURL.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            throw NSError(domain: "LibraryStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法打开 library.sqlite"])
        }
        database = handle
        sqlite3_busy_timeout(handle, 3000)
        try execute(schema)
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    private var schema: String {
        """
        PRAGMA journal_mode=WAL;
        CREATE TABLE IF NOT EXISTS works (
          id TEXT PRIMARY KEY, kind TEXT NOT NULL, title TEXT NOT NULL, sort_title TEXT NOT NULL,
          year INTEGER, overview TEXT, poster TEXT, source_kind TEXT NOT NULL, source_id TEXT NOT NULL,
          server_id TEXT, added_at REAL NOT NULL, updated_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS seasons (
          id TEXT PRIMARY KEY, work_id TEXT NOT NULL, number INTEGER NOT NULL, title TEXT NOT NULL,
          poster TEXT, source_kind TEXT NOT NULL, source_id TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS episodes (
          id TEXT PRIMARY KEY, work_id TEXT NOT NULL, season_id TEXT, season_number INTEGER NOT NULL,
          episode_number INTEGER NOT NULL, title TEXT NOT NULL, overview TEXT, runtime REAL NOT NULL DEFAULT 0,
          poster TEXT, source_kind TEXT NOT NULL, source_id TEXT NOT NULL, server_id TEXT,
          remote_path TEXT, remote_variant TEXT, file_url TEXT
        );
        CREATE TABLE IF NOT EXISTS versions (
          id TEXT PRIMARY KEY, item_id TEXT NOT NULL, work_id TEXT NOT NULL, name TEXT NOT NULL,
          source_kind TEXT NOT NULL, source_id TEXT NOT NULL, remote_path TEXT, media_source_id TEXT,
          container TEXT, resolution TEXT, file_url TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_works_sort ON works(sort_title);
        CREATE INDEX IF NOT EXISTS idx_works_source ON works(source_kind, source_id);
        CREATE INDEX IF NOT EXISTS idx_episodes_work ON episodes(work_id);
        CREATE INDEX IF NOT EXISTS idx_seasons_work ON seasons(work_id);
        CREATE INDEX IF NOT EXISTS idx_versions_item ON versions(item_id);
        """
    }

    // MARK: - Writes

    public func replace(source: ScannedLibrary) throws {
        lock.lock(); defer { lock.unlock() }
        guard let database else { return }
        try execute("BEGIN IMMEDIATE;")
        do {
            try deleteSourceLocked(kind: source.sourceKind, sourceID: source.sourceID)
            let now = Date().timeIntervalSince1970
            let workSQL = """
            INSERT OR REPLACE INTO works
            (id, kind, title, sort_title, year, overview, poster, source_kind, source_id, server_id, added_at, updated_at)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
            """
            let seasonSQL = "INSERT OR REPLACE INTO seasons (id, work_id, number, title, poster, source_kind, source_id) VALUES (?,?,?,?,?,?,?)"
            let episodeSQL = """
            INSERT OR REPLACE INTO episodes
            (id, work_id, season_id, season_number, episode_number, title, overview, runtime, poster, source_kind, source_id, server_id, remote_path, remote_variant, file_url)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """
            let versionSQL = """
            INSERT OR REPLACE INTO versions
            (id, item_id, work_id, name, source_kind, source_id, remote_path, media_source_id, container, resolution, file_url)
            VALUES (?,?,?,?,?,?,?,?,?,?,?)
            """
            for work in source.works {
                try run(workSQL, [
                    .text(work.id), .text(work.kind.rawValue), .text(work.title), .text(work.sortTitle),
                    work.year.map { .int(Int64($0)) } ?? .null, .text(work.overview), .text(work.poster),
                    .text(work.sourceKind), .text(work.sourceID), .text(work.serverID),
                    .double(now), .double(now),
                ])
                if let movie = work.movie {
                    try insertEpisode(movie, workID: work.id, seasonID: nil, sourceKind: work.sourceKind, sourceID: work.sourceID, sql: episodeSQL)
                    for version in movie.versions {
                        try insertVersion(version, itemID: movie.id, workID: work.id, sourceKind: work.sourceKind, sourceID: work.sourceID, sql: versionSQL)
                    }
                }
                for season in work.seasons {
                    try run(seasonSQL, [
                        .text(season.id), .text(work.id), .int(Int64(season.number)), .text(season.title),
                        .text(season.poster), .text(work.sourceKind), .text(work.sourceID),
                    ])
                    for episode in season.episodes {
                        try insertEpisode(episode, workID: work.id, seasonID: season.id, sourceKind: work.sourceKind, sourceID: work.sourceID, sql: episodeSQL)
                        for version in episode.versions {
                            try insertVersion(version, itemID: episode.id, workID: work.id, sourceKind: work.sourceKind, sourceID: work.sourceID, sql: versionSQL)
                        }
                    }
                }
            }
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func insertEpisode(
        _ episode: ScannedEpisode,
        workID: String,
        seasonID: String?,
        sourceKind: String,
        sourceID: String,
        sql: String
    ) throws {
        try run(sql, [
            .text(episode.id), .text(workID), .text(seasonID), .int(Int64(episode.seasonNumber)),
            .int(Int64(episode.episodeNumber)), .text(episode.title), .text(episode.overview),
            .double(episode.runtime), .text(episode.poster), .text(sourceKind), .text(sourceID),
            .text(episode.serverID), .text(episode.remotePath), .text(episode.remoteVariant), .text(episode.fileURL),
        ])
    }

    private func insertVersion(
        _ version: ScannedVersion,
        itemID: String,
        workID: String,
        sourceKind: String,
        sourceID: String,
        sql: String
    ) throws {
        try run(sql, [
            .text(version.id), .text(itemID), .text(workID), .text(version.name), .text(sourceKind),
            .text(sourceID), .text(version.remotePath), .text(version.mediaSourceID), .text(version.container),
            .text(version.resolution), .text(version.fileURL),
        ])
    }

    public func removeSource(kind: String, sourceID: String) throws {
        lock.lock(); defer { lock.unlock() }
        try execute("BEGIN IMMEDIATE;")
        do {
            try deleteSourceLocked(kind: kind, sourceID: sourceID)
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func deleteSourceLocked(kind: String, sourceID: String) throws {
        try run("DELETE FROM versions WHERE source_kind=? AND source_id=?", [.text(kind), .text(sourceID)])
        try run("DELETE FROM episodes WHERE source_kind=? AND source_id=?", [.text(kind), .text(sourceID)])
        try run("DELETE FROM seasons WHERE source_kind=? AND source_id=?", [.text(kind), .text(sourceID)])
        try run("DELETE FROM works WHERE source_kind=? AND source_id=?", [.text(kind), .text(sourceID)])
    }

    // MARK: - Reads

    public func works(search: String? = nil) throws -> [LibraryWork] {
        lock.lock(); defer { lock.unlock() }
        var sql = """
        SELECT w.id, w.kind, w.title, w.sort_title, w.year, w.overview, w.poster, w.source_kind, w.source_id,
               w.server_id, w.added_at,
               (SELECT COUNT(*) FROM seasons s WHERE s.work_id=w.id) AS season_count,
               (SELECT COUNT(*) FROM episodes e WHERE e.work_id=w.id) AS episode_count
        FROM works w
        """
        var arguments: [SQLValue] = []
        if let search, !search.trimmingCharacters(in: .whitespaces).isEmpty {
            sql += " WHERE w.title LIKE ? OR w.overview LIKE ?"
            let pattern = "%\(search)%"
            arguments = [.text(pattern), .text(pattern)]
        }
        sql += " ORDER BY w.sort_title COLLATE NOCASE, w.year"
        return try query(sql, arguments) { row in
            LibraryWork(
                id: row.text(0) ?? "",
                kind: LibraryKind(rawValue: row.text(1) ?? "movie") ?? .movie,
                title: row.text(2) ?? "",
                sortTitle: row.text(3) ?? "",
                year: row.int(4),
                overview: row.text(5),
                poster: row.text(6),
                sourceKind: row.text(7) ?? "",
                sourceID: row.text(8) ?? "",
                serverID: row.text(9),
                seasonCount: row.int(11) ?? 0,
                episodeCount: row.int(12) ?? 0,
                addedAt: Date(timeIntervalSince1970: row.double(10) ?? 0)
            )
        }
    }

    public func seasons(workID: String) throws -> [LibrarySeason] {
        lock.lock(); defer { lock.unlock() }
        return try query(
            "SELECT id, work_id, number, title, poster FROM seasons WHERE work_id=? ORDER BY number",
            [.text(workID)]
        ) { row in
            LibrarySeason(
                id: row.text(0) ?? "",
                workID: row.text(1) ?? "",
                number: row.int(2) ?? 0,
                title: row.text(3) ?? "",
                poster: row.text(4)
            )
        }
    }

    public func episodes(workID: String, seasonID: String? = nil) throws -> [LibraryEpisode] {
        lock.lock(); defer { lock.unlock() }
        var sql = """
        SELECT id, work_id, season_id, season_number, episode_number, title, overview, runtime, poster,
               source_kind, source_id, server_id, remote_path, remote_variant, file_url
        FROM episodes WHERE work_id=?
        """
        var args: [SQLValue] = [.text(workID)]
        if let seasonID {
            sql += " AND season_id=?"
            args.append(.text(seasonID))
        }
        sql += " ORDER BY season_number, episode_number"
        return try query(sql, args) { row in
            LibraryEpisode(
                id: row.text(0) ?? "",
                workID: row.text(1) ?? "",
                seasonID: row.text(2),
                seasonNumber: row.int(3) ?? 0,
                episodeNumber: row.int(4) ?? 0,
                title: row.text(5) ?? "",
                overview: row.text(6),
                runtime: row.double(7) ?? 0,
                poster: row.text(8),
                sourceKind: row.text(9) ?? "",
                sourceID: row.text(10) ?? "",
                serverID: row.text(11),
                remotePath: row.text(12),
                remoteVariant: row.text(13),
                fileURL: row.text(14)
            )
        }
    }

    public func versions(itemID: String) throws -> [LibraryVersion] {
        lock.lock(); defer { lock.unlock() }
        return try query(
            """
            SELECT id, item_id, work_id, name, source_kind, source_id, remote_path, media_source_id,
                   container, resolution, file_url
            FROM versions WHERE item_id=? ORDER BY name
            """,
            [.text(itemID)]
        ) { row in
            LibraryVersion(
                id: row.text(0) ?? "",
                itemID: row.text(1) ?? "",
                workID: row.text(2) ?? "",
                name: row.text(3) ?? "",
                sourceKind: row.text(4) ?? "",
                sourceID: row.text(5) ?? "",
                remotePath: row.text(6),
                mediaSourceID: row.text(7),
                container: row.text(8),
                resolution: row.text(9),
                fileURL: row.text(10)
            )
        }
    }

    public func counts() throws -> (works: Int, episodes: Int) {
        lock.lock(); defer { lock.unlock() }
        let works = try query("SELECT COUNT(*) FROM works", []) { $0.int(0) ?? 0 }.first ?? 0
        let episodes = try query("SELECT COUNT(*) FROM episodes", []) { $0.int(0) ?? 0 }.first ?? 0
        return (works, episodes)
    }

    // MARK: - SQLite helpers

    private enum SQLValue {
        case text(String?)
        case int(Int64)
        case double(Double)
        case null
    }

    private struct Row {
        let statement: OpaquePointer
        func text(_ index: Int32) -> String? {
            guard sqlite3_column_type(statement, index) != SQLITE_NULL,
                  let pointer = sqlite3_column_text(statement, index) else { return nil }
            return String(cString: pointer)
        }
        func int(_ index: Int32) -> Int? {
            guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
            return Int(sqlite3_column_int64(statement, index))
        }
        func double(_ index: Int32) -> Double? {
            guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
            return sqlite3_column_double(statement, index)
        }
    }

    private func execute(_ sql: String) throws {
        guard let database else { return }
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(database, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "sqlite error"
            sqlite3_free(error)
            throw NSError(domain: "LibraryStore", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    @discardableResult
    private func run(_ sql: String, _ values: [SQLValue]) throws -> Int {
        guard let database else { return 0 }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw NSError(domain: "LibraryStore", code: 3, userInfo: [NSLocalizedDescriptionKey: "prepare failed: \(sql)"])
        }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .text(let text):
                if let text { sqlite3_bind_text(statement, index, text, -1, SQLITE_TRANSIENT) }
                else { sqlite3_bind_null(statement, index) }
            case .int(let number):
                sqlite3_bind_int64(statement, index, number)
            case .double(let number):
                sqlite3_bind_double(statement, index, number)
            case .null:
                sqlite3_bind_null(statement, index)
            }
        }
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw NSError(domain: "LibraryStore", code: 4, userInfo: [NSLocalizedDescriptionKey: "step failed: \(result)"])
        }
        return 0
    }

    private func query<T>(_ sql: String, _ values: [SQLValue], transform: (Row) -> T) throws -> [T] {
        guard let database else { return [] }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw NSError(domain: "LibraryStore", code: 5, userInfo: [NSLocalizedDescriptionKey: "prepare failed: \(sql)"])
        }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .text(let text):
                if let text { sqlite3_bind_text(statement, index, text, -1, SQLITE_TRANSIENT) }
                else { sqlite3_bind_null(statement, index) }
            case .int(let number):
                sqlite3_bind_int64(statement, index, number)
            case .double(let number):
                sqlite3_bind_double(statement, index, number)
            case .null:
                sqlite3_bind_null(statement, index)
            }
        }
        var result: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(transform(Row(statement: statement)))
        }
        return result
    }
}
