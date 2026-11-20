import AVFAudio
import Foundation
import OpenFuseData

struct MobilePlaybackItem: Identifiable, Hashable {
    var id: String { url.absoluteString }
    var url: URL
    var title: String
    var subtitle: String?
    var fingerprint: MediaFingerprint
    var resumePosition: TimeInterval?
    var sourceKind: String
    var sourceID: String
    var remotePath: String?
    var remoteURL: String?
}

@MainActor
final class MobileLibraryModel: ObservableObject {
    @Published var works: [LibraryWork] = []
    @Published var groups: [LibraryGroup] = []
    @Published var recent: [PlaybackRecord] = []
    @Published var status: String?
    @Published var isWorking = false

    let supportDirectory: URL
    private let libraryStore: LibraryStore
    private let playbackStore: PlaybackStore

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        supportDirectory = base.appendingPathComponent("OpenFuse", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            libraryStore = try LibraryStore(directory: supportDirectory)
            playbackStore = try PlaybackStore(directory: supportDirectory)
        } catch {
            fatalError("OpenFuse mobile store init failed: \(error)")
        }
        seedBundledSampleIfNeeded()
        reload()
    }

    var countsText: String {
        "\(works.count) 个作品 · \(works.reduce(0) { $0 + $1.episodeCount }) 集"
    }

    func reload() {
        do {
            works = try libraryStore.works()
            let grouped = Dictionary(grouping: works, by: \.mergeKey)
            groups = grouped.map { key, values in
                let sorted = values.sorted {
                    sourceRank($0.sourceKind) == sourceRank($1.sourceKind)
                        ? $0.episodeCount > $1.episodeCount
                        : sourceRank($0.sourceKind) < sourceRank($1.sourceKind)
                }
                return LibraryGroup(id: sorted[0].id, key: key, primary: sorted[0], works: sorted)
            }
            .sorted { $0.primary.sortTitle.localizedStandardCompare($1.primary.sortTitle) == .orderedAscending }
            recent = playbackStore.recentlyPlayed(limit: 12)
        } catch {
            status = "读取媒体库失败：\(error.localizedDescription)"
        }
    }

    func resumePosition(for work: LibraryWork) -> TimeInterval? {
        guard let item = playbackItem(for: work) else { return nil }
        guard let record = playbackStore.record(forPath: item.fingerprint.resumeKey) else { return nil }
        return ResumePolicy.resumePosition(for: record)
    }

    func progress(for work: LibraryWork) -> Double? {
        guard let item = playbackItem(for: work),
              let record = playbackStore.record(forPath: item.fingerprint.resumeKey),
              record.duration > 0 else { return nil }
        guard !record.isFinished else { return 1 }
        return min(max(record.position / record.duration, 0), 1)
    }

    func episodes(for workID: String) -> [LibraryEpisode] {
        (try? libraryStore.episodes(workID: workID)) ?? []
    }

    func playbackItem(for work: LibraryWork) -> MobilePlaybackItem? {
        guard let episode = (try? libraryStore.episodes(workID: work.id))?.first else { return nil }
        return playbackItem(work: work, episode: episode)
    }

    func playbackItem(work: LibraryWork, episode: LibraryEpisode) -> MobilePlaybackItem? {
        let versions = (try? libraryStore.versions(itemID: episode.id)) ?? []
        let url: URL?
        if let file = versions.first?.fileURL ?? episode.fileURL {
            url = URL(fileURLWithPath: file)
        } else if let remote = episode.remotePath, episode.sourceKind == "webdav" {
            url = nil // WebDAV mobile sources arrive with the source picker milestone.
        } else {
            url = nil
        }
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        let fingerprint = (try? MediaFingerprint(url: url))
            ?? MediaFingerprint(path: url.path, fileSize: 0, modifiedAt: nil)
        let record = playbackStore.record(forPath: fingerprint.resumeKey)
        return MobilePlaybackItem(
            url: url,
            title: work.title,
            subtitle: episode.episodeLabel,
            fingerprint: fingerprint,
            resumePosition: record.flatMap(ResumePolicy.resumePosition(for:)),
            sourceKind: work.sourceKind,
            sourceID: work.sourceID,
            remotePath: episode.remotePath,
            remoteURL: nil
        )
    }

    func recordProgress(item: MobilePlaybackItem, duration: TimeInterval, position: TimeInterval, finished: Bool? = nil) {
        guard duration > 0 else { return }
        playbackStore.update(
            fingerprint: item.fingerprint,
            duration: duration,
            position: position,
            displayTitle: item.title,
            finished: finished,
            sourceKind: item.sourceKind,
            sourceID: item.sourceID,
            remotePath: item.remotePath,
            remoteURL: item.remoteURL
        )
        recent = playbackStore.recentlyPlayed(limit: 12)
    }

    func importVideo(from url: URL) {
        isWorking = true
        defer { isWorking = false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let ext = url.pathExtension.lowercased()
        guard ["mp4", "m4v", "mov"].contains(ext) else {
            status = "移动端首版使用 AVPlayer，只支持 MP4/MOV；MKV 由 Mac 端 libmpv 播放。"
            return
        }
        let imports = documentsDirectory.appendingPathComponent("Imports", isDirectory: true)
        let folder = imports.appendingPathComponent(url.deletingPathExtension().lastPathComponent, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            let scanned = try LibraryScanner.scanLocal(directory: imports)
            try libraryStore.replace(source: scanned)
            reload()
            status = "已导入 \(url.lastPathComponent)"
        } catch {
            status = "导入失败：\(error.localizedDescription)"
        }
    }

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    private func seedBundledSampleIfNeeded() {
        guard (try? libraryStore.counts().works) == 0,
              let video = Bundle.main.url(forResource: "openfuse-mobile", withExtension: "mp4") else { return }
        let sample = documentsDirectory
            .appendingPathComponent("OpenFuse Mobile Sample (2026)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: sample, withIntermediateDirectories: true)
            let target = sample.appendingPathComponent("OpenFuse Mobile Sample.mp4")
            if !FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.copyItem(at: video, to: target)
            }
            if let poster = Bundle.main.url(forResource: "openfuse-mobile", withExtension: "jpg") {
                let posterTarget = sample.appendingPathComponent("poster.jpg")
                if !FileManager.default.fileExists(atPath: posterTarget.path) {
                    try FileManager.default.copyItem(at: poster, to: posterTarget)
                }
            }
            let scanned = try LibraryScanner.scanLocal(directory: documentsDirectory.appendingPathComponent("OpenFuse Mobile Sample (2026)"))
            try libraryStore.replace(source: ScannedLibrary(
                sourceKind: "local", sourceID: "bundled", sourceName: "示例", works: scanned.works
            ))
        } catch {
            status = "示例入库失败：\(error.localizedDescription)"
        }
    }

    private func sourceRank(_ kind: String) -> Int {
        switch kind {
        case "jellyfin": return 0
        case "local": return 1
        default: return 2
        }
    }
}
