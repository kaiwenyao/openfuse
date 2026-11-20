import Foundation
import OpenFuseCore

/// Trakt scrobbler. Configuration is supplied by AppModel (env or persisted
/// settings); this type also exposes the device-code flow for the settings UI.
@MainActor
final class TraktService {
    static let shared = TraktService()

    private var client: TraktClient?
    private var config: TraktConfig?
    private var token: String?
    private var match: (ids: TraktIDs, query: TraktQuery)?
    private var pendingQuery: TraktQuery?
    private var activeTitle: String?
    private var pendingProgress: Double = 0
    private var lastSentAt = Date.distantPast
    private var isStopped = true
    private(set) var lastAction: String?

    var isConfigured: Bool { client != nil }

    private init() {}

    func configure(baseURL: URL, clientID: String, clientSecret: String, token: String?) {
        let config = TraktConfig(baseURL: baseURL, clientID: clientID, clientSecret: clientSecret)
        self.config = config
        self.token = token
        self.client = token.flatMap { TraktClient(config: config, token: $0) }
    }

    func requestDeviceCode() async throws -> TraktDeviceCode {
        guard let config else { throw TraktError.unauthorized }
        let client = TraktClient(config: config)
        return try await client.deviceCode()
    }

    func pollDeviceToken(code: String) async throws -> TraktToken {
        guard let config else { throw TraktError.unauthorized }
        let client = TraktClient(config: config)
        let token = try await client.pollToken(deviceCode: code)
        configure(baseURL: config.baseURL, clientID: config.clientID, clientSecret: config.clientSecret, token: token.accessToken)
        return token
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
