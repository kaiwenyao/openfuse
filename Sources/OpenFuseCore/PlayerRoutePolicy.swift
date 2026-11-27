import Foundation

/// Which page the player goes back to when it closes.
///
/// The loading route is a placeholder shown while a source is being resolved, so
/// it can never be a destination. Recording it as the return route is what left
/// the app staring at "正在准备播放…" after closing a «继续观看» item.
public enum PlayerReturnRoutePolicy {
    /// The route to remember for the next `closePlayer()`.
    ///
    /// - Parameters:
    ///   - current: the route the UI shows right now.
    ///   - existing: the route remembered before the loading page was pushed.
    ///   - isPlaceholder: true for routes that must never be returned to.
    /// - Returns: `existing` while `current` is a placeholder, `current` otherwise.
    public static func route<Route: Equatable>(
        current: Route,
        existing: Route?,
        isPlaceholder: (Route) -> Bool
    ) -> Route? {
        isPlaceholder(current) ? existing : current
    }
}

/// Whether the `.loading` route still has anything to show.
public enum PlaybackLoadingState {
    /// The loading page is legitimate while a request is in flight or after that
    /// request failed. With neither, the route is stale — for example a resume
    /// that already handed over to the player — and the home page must win.
    public static func showsLoadingPage(isLoading: Bool, error: String?) -> Bool {
        guard !isLoading else { return true }
        guard let error else { return false }
        return !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
