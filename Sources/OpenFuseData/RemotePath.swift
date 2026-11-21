import Foundation

/// Path helpers for remote (WebDAV) browsing.
///
/// `RemoteEntry.path` is already relative to the source root and may contain
/// several segments (`Show/Season 1`). The browser used to append that whole
/// string to its navigation stack on every click, so clicking a folder again
/// while the previous listing was still loading stacked the same path
/// repeatedly (`Show / Show / Show` in the breadcrumb) and persisted it.
/// Everything here canonicalises paths instead of concatenating them.
public enum RemotePath {
    /// Segments of `path` with empty components removed.
    public static func components(_ path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    /// Canonical navigation stack: `[""]` for the root, then one entry per
    /// segment. `stack.last` is always the current directory path.
    public static func stack(_ path: String) -> [String] {
        [""] + components(path)
    }

    /// Root-relative path for a stack produced by `stack(_:)`.
    public static func path(_ stack: [String]) -> String {
        stack.dropFirst()
            .filter { !$0.isEmpty }
            .joined(separator: "/")
    }

    /// Label for one breadcrumb segment. `component` must already be split;
    /// passing a whole `RemoteEntry.path` here renders `Show/Season 1` on a
    /// single card. Use `folderDisplayName(name:path:)` for entries.
    public static func displayName(_ component: String) -> String {
        component.isEmpty ? "/" : component
    }

    /// Label for one directory entry, always exactly one path segment.
    ///
    /// WebDAV servers disagree about `<displayname>`: a healthy server returns
    /// the folder's own name, OpenList sometimes returns the whole
    /// root-relative path, and others omit it (`RemoteEntry.name` then already
    /// falls back to the last href segment). The browser draws one card per
    /// child and the parent stays in the breadcrumb, so the card must never
    /// repeat the path. Prefer a usable single-segment server name and derive
    /// the last non-empty `path` segment otherwise. `path` and `url` keep
    /// serving requests, navigation and cache keys unchanged, and this helper
    /// never decodes percent escapes a second time.
    public static func folderDisplayName(name: String, path: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var segment = trimmed
        while segment.count > 1, segment.hasSuffix("/") {
            segment.removeLast()
        }
        if !segment.isEmpty,
           segment != ".",
           segment != "..",
           !segment.contains("/"),
           !segment.lowercased().contains("%2f") {
            return segment
        }
        return components(path).last ?? segment
    }
}

public extension RemoteEntry {
    /// Single-segment display label used by the grid, the list, the season card
    /// subtitle and VoiceOver. Requests keep using `path`/`url`.
    var folderDisplayName: String {
        RemotePath.folderDisplayName(name: name, path: path)
    }

    /// File name with a folder-style fallback. Some WebDAV servers put the
    /// whole root-relative path into `<displayname>`; using that as a filename
    /// (subtitle matching, NFO sidecars, playback title) would duplicate the
    /// directory in every request.
    var baseName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty,
           !trimmed.contains("/"),
           !trimmed.lowercased().contains("%2f") {
            return trimmed
        }
        return (path as NSString).lastPathComponent
    }

    var fileBaseName: String { (baseName as NSString).deletingPathExtension }
}

/// Navigation state for one browser. Pure value type so the "click a folder
/// twice while the listing loads" race can be unit tested without a UI.
public struct RemotePathState: Equatable, Sendable {
    public private(set) var stack: [String]

    public init(stack: [String] = [""]) {
        self.stack = Self.canonical(stack)
    }

    /// Current directory, root-relative (`""` at the root).
    public var path: String { RemotePath.path(stack) }

    public var isRoot: Bool { stack.count <= 1 }

    public var depth: Int { max(0, stack.count - 1) }

    /// Enter a child directory. Ignored while another listing is in flight and
    /// idempotent, so repeated clicks can never stack the same path.
    @discardableResult
    public mutating func enter(_ childPath: String, busy: Bool = false) -> Bool {
        guard !busy else { return false }
        let target = Self.canonical(RemotePath.stack(childPath))
        guard target.count > 1 else { return false }
        guard target != stack else { return false }
        stack = target
        return true
    }

    @discardableResult
    public mutating func up() -> Bool {
        guard stack.count > 1 else { return false }
        stack.removeLast()
        return true
    }

    /// Jump to a breadcrumb segment (`0` is the source root).
    @discardableResult
    public mutating func jump(to index: Int) -> Bool {
        guard index >= 0, index < stack.count, index != stack.count - 1 else { return false }
        stack = Array(stack.prefix(index + 1))
        return true
    }

    @discardableResult
    public mutating func reset() -> Bool {
        guard stack.count > 1 else { return false }
        stack = [""]
        return true
    }

    /// Normalise a stack produced by any past version of the browser.
    ///
    /// Older builds stored root-relative paths (`["", "Show", "Show/Season 1"]`)
    /// and, when the user clicked a folder again while it loaded, the same path
    /// several times. Newer builds store one component per entry. Both shapes
    /// are folded back into `["<component>", ...]` so a persisted bad path
    /// cannot resurface as `Show / Show / Show`.
    public static func canonical(_ stack: [String]) -> [String] {
        let entries = stack.dropFirst().filter { !$0.isEmpty }.map { $0 }
        guard !entries.isEmpty else { return [""] }
        // Only the old shape keeps slashes in an entry; single-segment old
        // stacks are already indistinguishable from the component shape.
        let looksLegacy = entries.contains { $0.contains("/") }
        if looksLegacy, isAscendingPathChain(entries) {
            return RemotePath.stack(entries[entries.count - 1])
        }
        return [""] + entries.flatMap { RemotePath.components($0) }
    }

    private static func isAscendingPathChain(_ entries: [String]) -> Bool {
        for index in 1..<entries.count {
            let previous = RemotePath.components(entries[index - 1])
            let current = RemotePath.components(entries[index])
            guard current.count >= previous.count,
                  Array(current.prefix(previous.count)) == previous
            else { return false }
        }
        return true
    }
}
