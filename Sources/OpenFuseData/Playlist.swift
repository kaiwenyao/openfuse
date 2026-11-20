import Foundation

/// "Play the next episode" ordering shared by the WebDAV and Jellyfin paths.
/// Kept separate from the app so the rules can be unit tested without a player.
public enum PlaylistOrder {
    /// Next video file in the same WebDAV folder, ordered the way Finder orders
    /// names (`S03E09` before `S03E10`).
    public static func nextPlayableEntry(
        after entry: RemoteEntry,
        among siblings: [RemoteEntry]
    ) -> RemoteEntry? {
        let videos = siblings
            .filter { !$0.isDirectory && $0.isPlayableVideo }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard let index = videos.firstIndex(where: { $0.path == entry.path }),
              index + 1 < videos.count
        else { return nil }
        return videos[index + 1]
    }

    /// Next episode of the same season, ordered by episode number.
    public static func nextEpisode(
        after item: JellyfinItem,
        among episodes: [JellyfinItem]
    ) -> JellyfinItem? {
        guard item.itemType == "Episode" else { return nil }
        let ordered = episodes
            .filter { $0.itemType == "Episode" }
            .sorted { ($0.indexNumber ?? Int.max) < ($1.indexNumber ?? Int.max) }
        guard let index = ordered.firstIndex(where: { $0.id == item.id }),
              index + 1 < ordered.count
        else { return nil }
        return ordered[index + 1]
    }
}
