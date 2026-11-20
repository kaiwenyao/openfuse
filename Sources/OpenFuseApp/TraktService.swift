import Foundation
import OpenFuseCore

/// Minimal Trakt scrobbler configured from the environment:
/// OPENFUSE_TRAKT_BASE_URL, OPENFUSE_TRAKT_CLIENT_ID, OPENFUSE_TRAKT_TOKEN.
@MainActor
final class TraktService {
    static let shared = TraktService()

    private var client: TraktClient?
    private var match: (ids: TraktIDs, query: TraktQuery)?
    private var pendingQuery: TraktQuery?
    private var activeTitle: String?
    private var pendingProgress: Double = 0
    private var lastSentAt = Date.distantPast
    private var isStopped = true
    private(set) var lastAction: String?

    var isConfigured: Bool { client != nil }

    private init() {
        let environment = ProcessInfo.processInfo.environment
        guard let clientID = environment["OPENFUSE_TRAKT_CLIENT_ID"], !clientID.isEmpty,
              let token = environment["OPENFUSE_TRAKT_TOKEN"], !token.isEmpty else { return }
        let base = environment["OPENFUSE_TRAKT_BASE_URL"].flatMap(URL.init(string:))
            ?? URL(string: "https://api.trakt.tv")!
        let secret = environment["OPENFUSE_TRAKT_CLIENT_SECRET"] ?? ""
        client = TraktClient(config: TraktConfig(baseURL: base, clientID: clientID, clientSecret: secret), token: token)
    }

    func history() async -> [TraktHistoryItem] {
        guard let client else { return [] }
        return (try? await client.history()) ?? []
    }

    func prepare(_ query: TraktQuery) {
        pendingQuery = query
    }

    func start(title: String, progress: Double) {
        guard let client else { return }
        let query = pendingQuery ?? TraktQuery(title: title, kind: .movie)
        pendingQuery = nil
        activeTitle = title
        match = nil
        pendingProgress = progress
        isStopped = false
        lastAction = "search"
        Task { @MainActor in
            guard let result = try? await client.search(title: query.title, type: query.kind.rawValue) else { return }
            self.match = (result.0, query)
            self.send("start", progress: self.pendingProgress)
        }
    }

    func update(title: String, progress: Double, isPaused: Bool) {
        guard client != nil, !isStopped, activeTitle == title else { return }
        pendingProgress = progress
        let action = isPaused ? "pause" : "start"
        guard Date().timeIntervalSince(lastSentAt) >= 10 else { return }
        send(action, progress: progress)
    }

    func stop(title: String, progress: Double) {
        guard client != nil, !isStopped, activeTitle == title else { return }
        pendingProgress = progress
        isStopped = true
        send("stop", progress: progress, force: true)
    }

    private func send(_ action: String, progress: Double, force: Bool = false) {
        guard let client, let match else { return }
        if !force, Date().timeIntervalSince(lastSentAt) < 10 { return }
        lastSentAt = Date()
        lastAction = action
        let value = min(100, max(0, progress))
        Task {
            try? await client.scrobble(
                action: action,
                ids: match.ids,
                type: match.query.kind.rawValue,
                season: match.query.season,
                episode: match.query.episode,
                progress: value
            )
        }
    }
}
