import Foundation

/// What a remote browser offers when its listing fails.
public enum RemoteDirectoryRecovery: Equatable, Sendable {
    /// Nothing specific to do: the network, the server or the path failed, so the
    /// page keeps the plain 重试 button.
    case retry
    /// The password is gone (a «仅本次会话» source after a restart). The page must
    /// ask for it instead of blaming the account.
    case enterPassword

    /// Classifies a thrown error. Only a lost WebDAV credential is actionable;
    /// everything else keeps the generic retry.
    public static func action(for error: Error) -> RemoteDirectoryRecovery {
        if let webdav = error as? WebDAVError, case .missingCredential = webdav {
            return .enterPassword
        }
        return .retry
    }
}

/// How the shell presents a `statusMessage`.
public enum StatusNoticeKind: Equatable, Sendable {
    case info
    case keychainAuthorization

    /// The Keychain prompt is only useful when the user can trigger the system
    /// dialog again, so that notice carries a 重试 button.
    public var offersCredentialRetry: Bool { self == .keychainAuthorization }
}

/// Remote source kinds a history record can belong to.
///
/// `PlaybackRecord.isRemote` only knows the two kinds the home rail can fetch a
/// still for; the resume path has to recognise every remote kind, otherwise a
/// deleted source is reopened as if its URL were a local file.
public enum PlaybackSourceKind {
    public static let remoteKinds: Set<String> = ["webdav", "jellyfin", "emby", "smb", "plex"]

    public static func isRemote(_ kind: String?) -> Bool {
        guard let kind else { return false }
        return remoteKinds.contains(kind.lowercased())
    }
}

/// A failure the loading page can act on beyond 重试.
public enum LoadingFailureKind: Equatable, Sendable {
    case generic
    /// The record points at a source that no longer exists, so retrying can only
    /// fail again; the page offers 从历史中移除 instead.
    case sourceRemoved

    public var offersRemoveFromHistory: Bool { self == .sourceRemoved }
}

/// Resolves a Plex history record back to the item it played.
///
/// A record keeps only the part key; resuming needs the rating key, which the
/// scanned library stores on the episode (or movie) that owns that part.
public enum PlexResumeLookup {
    public struct Candidate: Equatable, Sendable {
        public var ratingKey: String?
        public var partKeys: [String?]

        public init(ratingKey: String?, partKeys: [String?]) {
            self.ratingKey = ratingKey
            self.partKeys = partKeys
        }
    }

    /// The first non-empty rating key whose candidate plays `partKey`.
    public static func ratingKey(for partKey: String, in candidates: [Candidate]) -> String? {
        guard !partKey.isEmpty else { return nil }
        for candidate in candidates where candidate.partKeys.contains(partKey) {
            if let key = candidate.ratingKey, !key.isEmpty { return key }
        }
        return nil
    }
}
