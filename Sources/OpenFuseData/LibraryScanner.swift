import AVFoundation
import Foundation

public enum LibraryScanError: LocalizedError {
    case noMedia
    case tooManyFiles
    case invalidFolder
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .noMedia: return "没有找到可识别的视频文件"
        case .tooManyFiles: return "目录过大，已停止扫描（上限 5000 个文件）"
        case .invalidFolder: return "无法读取该文件夹"
        case .cancelled: return "扫描已取消"
        }
    }
}

public final class ScanCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}
    public func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }
    public var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }
}

public enum LibraryScanner {
    public static let videoExtensions: Set<String> = [
        "mkv", "mp4", "m4v", "mov", "ts", "m2ts", "webm", "avi", "flv", "wmv", "iso", "mpg", "mpeg",
    ]
    public static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp"]

    struct FileCandidate {
        var relativePath: String
        var name: String
        var fileURL: URL?
        var remotePath: String?
        var posterPath: String?
        var posterURL: String?
        var nfo: NFOMetadata?
        var showNFO: NFOMetadata?
        var modifiedAt: Date? = nil
        var resolution: String? = nil
        var dynamicRange: String? = nil
        var contentKey: String? = nil
    }

    // MARK: - Local

    public static func scanLocal(
        directory: URL,
        token: ScanCancellationToken? = nil,
        progress: ((Int) -> Void)? = nil
    ) throws -> ScannedLibrary {
        let directory = directory.standardizedFileURL
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw LibraryScanError.invalidFolder
        }
        let sourceID = "local-" + LibraryID.hash(directory.path).replacingOccurrences(of: "local-", with: "")
        var videoFiles: [(URL, String, NFOMetadata?, NFOMetadata?, Date?, String?)] = []
        var posterMap: [String: String] = [:]
        var fileCount = 0
        while let file = enumerator.nextObject() as? URL {
            if token?.isCancelled == true { throw LibraryScanError.cancelled }
            let ext = file.pathExtension.lowercased()
            guard videoExtensions.contains(ext) || imageExtensions.contains(ext) else { continue }
            fileCount += 1
            if fileCount % 50 == 0 { progress?(fileCount) }
            if fileCount > 20000 { throw LibraryScanError.tooManyFiles }
            let relative = file.path.replacingOccurrences(of: directory.path + "/", with: "")
            if imageExtensions.contains(ext) {
                let dir = (relative as NSString).deletingLastPathComponent
                let base = (relative as NSString).deletingPathExtension
                let filename = (relative as NSString).lastPathComponent.lowercased()
                let key = dir + "|" + base
                if filename.hasPrefix("poster") || filename.hasPrefix("folder") || filename.hasPrefix("cover") {
                    posterMap[dir + "|dir"] = file.path
                }
                posterMap[key] = file.path
                continue
            }
            let showDirectory = file.deletingLastPathComponent().deletingLastPathComponent()
            let episodeNFO = NFOReader.readEpisode(videoURL: file)
            let movieNFO = NFOReader.readMovie(videoURL: file)
            let showNFO = NFOReader.readShow(showDirectory: showDirectory)
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            videoFiles.append((file, relative, movieNFO ?? episodeNFO, showNFO, modified, probeLocalHeight(file)))
        }
        let candidates = videoFiles.map { file, relative, nfo, showNFO, modified, resolution in
            FileCandidate(
                relativePath: relative,
                name: file.lastPathComponent,
                fileURL: file,
                remotePath: nil,
                posterPath: findLocalPoster(for: file, relativePath: relative, directory: directory, posterMap: posterMap),
                posterURL: nil,
                nfo: nfo,
                showNFO: showNFO,
                modifiedAt: modified,
                resolution: resolution
            )
        }
        let sourceName = directory.lastPathComponent.isEmpty ? "本地文件夹" : directory.lastPathComponent
        return buildLibrary(
            candidates: candidates,
            sourceKind: "local",
            sourceID: sourceID,
            sourceName: sourceName
        )
    }

    static func probeRemoteVideoHeight(url: URL, authorization: String) async -> (height: String?, dynamicRange: String?)? {
        #if os(macOS)
        let candidates = ["/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe", "/usr/bin/ffprobe"]
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return nil
        }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("openfuse-ffprobe-\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        guard let output = FileHandle(forWritingAtPath: outputURL.path) else { return nil }
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = [
            "-v", "error",
            "-rw_timeout", "8000000",
            "-analyzeduration", "500000",
            "-probesize", "1000000",
            "-headers", "Authorization: \(authorization)\r\n",
            "-select_streams", "v:0",
            "-show_entries", "stream=height,color_transfer,color_primaries",
            "-of", "json",
            url.absoluteString,
        ]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in
                try? output.close()
                let data = (try? Data(contentsOf: outputURL)) ?? Data()
                guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let streams = object["streams"] as? [[String: Any]],
                      let stream = streams.first else {
                    continuation.resume(returning: nil)
                    return
                }
                var height: String?
                if let value = stream["height"] as? Int, value > 0 {
                    height = value >= 2000 ? "2160p" : "\(value)p"
                }
                let transfer = stream["color_transfer"] as? String
                let primaries = stream["color_primaries"] as? String
                var dynamicRange: String?
                if transfer == "smpte2084" {
                    dynamicRange = primaries == "bt2020" ? "HDR10" : "HDR"
                } else if transfer == "arib-std-b67" {
                    dynamicRange = "HLG"
                }
                continuation.resume(returning: (height, dynamicRange))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
            }
        }
        #else
        return nil
        #endif
    }

    static func probeLocalHeight(_ url: URL) -> String? {
        #if os(visionOS)
        return nil
        #else
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size > 1024 else { return nil }
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { return nil }
        let dimensions = track.naturalSize.applying(track.preferredTransform)
        let height = Int(abs(dimensions.height).rounded())
        guard height > 0 else { return nil }
        if height >= 2000 { return "2160p" }
        return "\(height)p"
        #endif
    }

    private static func findLocalPoster(
        for file: URL,
        relativePath: String,
        directory: URL,
        posterMap: [String: String]
    ) -> String? {
        let folder = (relativePath as NSString).deletingLastPathComponent
        let base = (relativePath as NSString).deletingPathExtension
        if let direct = posterMap[folder + "|" + base] { return direct }
        if let folderPoster = posterMap[folder + "|dir"] { return folderPoster }
        // A season folder often has the show poster one level up.
        let parent = (folder as NSString).deletingLastPathComponent
        if !parent.isEmpty, let parentPoster = posterMap[parent + "|dir"] { return parentPoster }
        for name in ["poster.jpg", "folder.jpg", "cover.jpg", "poster.png", "folder.png"] {
            let candidate = file.deletingLastPathComponent().appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate.path }
        }
        return nil
    }

    // MARK: - Generic grouping

    static func buildLibrary(
        candidates: [FileCandidate],
        sourceKind: String,
        sourceID: String,
        sourceName: String,
        failedPaths: [String] = []
    ) -> ScannedLibrary {
        struct SeriesBucket {
            var title: String
            var year: Int?
            var overview: String?
            var posterPath: String?
            var posterURL: String?
            var addedAt: Date?
            var episodes: [(ParsedMediaName, FileCandidate)] = []
        }
        var movies: [(ParsedMediaName, FileCandidate)] = []
        var series: [String: SeriesBucket] = [:]

        for candidate in candidates {
            let fakeURL = URL(fileURLWithPath: candidate.relativePath.isEmpty ? candidate.name : candidate.relativePath)
            let parsed = MediaNameParser.parse(fileURL: fakeURL, relativePath: candidate.relativePath)
            if parsed.kind == .series, let episode = parsed.episode {
                var season = parsed.season ?? 1
                if season < 1 { season = 1 }
                let key = parsed.showTitle.lowercased()
                var bucket = series[key] ?? SeriesBucket(
                    title: candidate.showNFO?.title ?? parsed.showTitle,
                    year: candidate.showNFO?.year ?? parsed.year,
                    overview: candidate.showNFO?.overview
                )
                if bucket.year == nil { bucket.year = candidate.showNFO?.year ?? parsed.year }
                if bucket.overview == nil { bucket.overview = candidate.showNFO?.overview }
                if bucket.posterPath == nil {
                    bucket.posterPath = candidate.showNFO?.posterPath ?? candidate.posterPath
                }
                if bucket.posterURL == nil {
                    bucket.posterURL = candidate.showNFO?.posterURL?.absoluteString ?? candidate.posterURL
                }
                if let modified = candidate.modifiedAt {
                    bucket.addedAt = max(bucket.addedAt ?? modified, modified)
                }
                bucket.episodes.append((parsed, candidate))
                series[key] = bucket
                _ = episode
            } else {
                movies.append((parsed, candidate))
            }
        }

        var works: [ScannedWork] = []

        for (parsed, candidate) in movies {
            let title = candidate.nfo?.title ?? parsed.showTitle
            let workID = LibraryID.hash("\(sourceID)|movie|\(candidate.relativePath)", prefix: sourceKind == "local" ? "local-" : "\(sourceKind)-")
            let episodeID = workID + "-main"
            let versionID = episodeID + "-v0"
            let poster = candidate.nfo?.posterPath.map { PosterRef.file($0) }
                ?? candidate.nfo?.posterURL.map { PosterRef.remote($0.absoluteString) }
                ?? candidate.posterPath.map { PosterRef.file($0) }
                ?? candidate.posterURL.map { PosterRef.remote($0) }
            let version = ScannedVersion(
                id: versionID,
                name: candidate.resolution.map {
                    "\($0) · \(LibraryAggregation.sourceLabel(sourceKind))"
                } ?? (sourceKind == "local" ? "本地文件" : LibraryAggregation.sourceLabel(sourceKind)),
                mediaSourceID: nil,
                container: (candidate.name as NSString).pathExtension.uppercased(),
                resolution: candidate.resolution,
                dynamicRange: candidate.dynamicRange,
                contentKey: candidate.contentKey,
                remotePath: candidate.remotePath,
                fileURL: candidate.fileURL?.absoluteString
            )
            let episode = ScannedEpisode(
                id: episodeID,
                seasonNumber: 0,
                episodeNumber: 1,
                title: title,
                overview: candidate.nfo?.overview,
                runtime: 0,
                poster: poster,
                serverID: nil,
                remotePath: candidate.remotePath,
                remoteVariant: nil,
                fileURL: candidate.fileURL?.absoluteString,
                versions: [version]
            )
            works.append(
                ScannedWork(
                    id: workID,
                    kind: .movie,
                    title: title,
                    sortTitle: title,
                    year: candidate.nfo?.year ?? parsed.year,
                    overview: candidate.nfo?.overview,
                    poster: poster,
                    sourceKind: sourceKind,
                    sourceID: sourceID,
                    serverID: nil,
                    addedAt: candidate.modifiedAt,
                    seasons: [],
                    movie: episode
                )
            )
        }

        for (_, bucket) in series {
            let title = bucket.title.isEmpty ? "未命名剧集" : bucket.title
            let workID = LibraryID.hash("\(sourceID)|series|\(title.lowercased())", prefix: sourceKind == "local" ? "local-" : "\(sourceKind)-")
            let poster = bucket.posterPath.map { PosterRef.file($0) } ?? bucket.posterURL.map { PosterRef.remote($0) }
            var seasonMap: [Int: [ScannedEpisode]] = [:]
            for (parsed, candidate) in bucket.episodes {
                let season = max(1, parsed.season ?? 1)
                let episode = max(1, parsed.episode ?? 1)
                let episodeID = workID + "-s\(season)e\(episode)-" + String(LibraryID.hash(candidate.relativePath).prefix(8))
                let versionID = episodeID + "-v0"
                let version = ScannedVersion(
                    id: versionID,
                    name: candidate.resolution.map {
                    "\($0) · \(LibraryAggregation.sourceLabel(sourceKind))"
                } ?? (sourceKind == "local" ? "本地文件" : LibraryAggregation.sourceLabel(sourceKind)),
                    mediaSourceID: nil,
                    container: (candidate.name as NSString).pathExtension.uppercased(),
                    resolution: candidate.resolution,
                    dynamicRange: candidate.dynamicRange,
                    contentKey: candidate.contentKey,
                    remotePath: candidate.remotePath,
                    fileURL: candidate.fileURL?.absoluteString
                )
                var titleText = candidate.nfo?.title ?? parsed.episodeTitle ?? ""
                if titleText.isEmpty { titleText = "第 \(episode) 集" }
                let ep = ScannedEpisode(
                    id: episodeID,
                    seasonNumber: season,
                    episodeNumber: episode,
                    title: titleText,
                    overview: candidate.nfo?.overview,
                    runtime: 0,
                    poster: candidate.posterPath.map { PosterRef.file($0) } ?? candidate.posterURL.map { PosterRef.remote($0) },
                    serverID: nil,
                    remotePath: candidate.remotePath,
                    remoteVariant: nil,
                    fileURL: candidate.fileURL?.absoluteString,
                    versions: [version]
                )
                seasonMap[season, default: []].append(ep)
            }
            let seasons = seasonMap.keys.sorted().map { number -> ScannedSeason in
                ScannedSeason(
                    id: workID + "-s\(number)",
                    number: number,
                    title: "第 \(number) 季",
                    poster: poster,
                    episodes: seasonMap[number, default: []].sorted { $0.episodeNumber < $1.episodeNumber }
                )
            }
            works.append(
                ScannedWork(
                    id: workID,
                    kind: .series,
                    title: title,
                    sortTitle: title,
                    year: bucket.year,
                    overview: bucket.overview,
                    poster: poster,
                    sourceKind: sourceKind,
                    sourceID: sourceID,
                    serverID: nil,
                    addedAt: bucket.addedAt,
                    seasons: seasons,
                    movie: nil
                )
            )
        }

        return ScannedLibrary(
            sourceKind: sourceKind,
            sourceID: sourceID,
            sourceName: sourceName,
            works: works.sorted { $0.sortTitle.localizedStandardCompare($1.sortTitle) == .orderedAscending },
            failedPaths: failedPaths
        )
    }

    // MARK: - Jellyfin

    public struct JellyfinLibraryIssue: Sendable, Hashable {
        public var libraryID: String
        public var libraryName: String
        public var message: String
        /// True when the server answered 401/403: access was explicitly
        /// withdrawn and cached entries must disappear. False means a
        /// transient failure and the previous index must survive.
        public var accessRevoked: Bool
    }

    public struct JellyfinScanResult: Sendable {
        public var library: ScannedLibrary
        public var issues: [JellyfinLibraryIssue]

        public init(library: ScannedLibrary, issues: [JellyfinLibraryIssue] = []) {
            self.library = library
            self.issues = issues
        }

        /// A revoked library is an authoritative answer, so it does not make
        /// the scan partial; a transport/timeout failure does.
        public var hasTransientFailure: Bool {
            issues.contains { !$0.accessRevoked }
        }

        public var revokedLibraryNames: [String] {
            issues.filter(\.accessRevoked).map(\.libraryName)
        }

        public var transientFailures: [JellyfinLibraryIssue] {
            issues.filter { !$0.accessRevoked }
        }
    }

    /// Loads every library page by page. A single failing page aborts the
    /// whole library (never a silent prefix), and a cancellation throws
    /// `.cancelled` so the caller keeps the last complete index.
    public static func scanJellyfin(
        source: JellyfinSource,
        client: JellyfinClient,
        token: ScanCancellationToken? = nil,
        progress: ((Int) -> Void)? = nil
    ) async throws -> JellyfinScanResult {
        let views = try await client.views()
        var items: [JellyfinItem] = []
        var issues: [JellyfinLibraryIssue] = []
        var loadedLibraries = 0
        for (index, view) in views.enumerated() {
            if token?.isCancelled == true { throw LibraryScanError.cancelled }
            if Task.isCancelled { throw LibraryScanError.cancelled }
            do {
                let libraryItems = try await client.libraryItems(parentID: view.id, token: token)
                items.append(contentsOf: libraryItems)
                loadedLibraries += 1
                progress?(items.count + index)
            } catch JellyfinError.cancelled {
                throw LibraryScanError.cancelled
            } catch is CancellationError {
                throw LibraryScanError.cancelled
            } catch let error as JellyfinError {
                issues.append(
                    JellyfinLibraryIssue(
                        libraryID: view.id,
                        libraryName: view.name,
                        message: error.localizedDescription,
                        accessRevoked: error.isAccessRevoked
                    )
                )
            } catch {
                issues.append(
                    JellyfinLibraryIssue(
                        libraryID: view.id,
                        libraryName: view.name,
                        message: error.localizedDescription,
                        accessRevoked: false
                    )
                )
            }
        }
        if token?.isCancelled == true { throw LibraryScanError.cancelled }

        // Nothing usable came back: give the caller the failure list without
        // spending time rebuilding an empty library.
        if loadedLibraries == 0 && !views.isEmpty {
            return JellyfinScanResult(
                library: ScannedLibrary(
                    sourceKind: source.kind,
                    sourceID: source.id,
                    sourceName: source.name,
                    works: []
                ),
                issues: issues
            )
        }

        var movies: [JellyfinItem] = []
        var seriesItems: [String: JellyfinItem] = [:]
        var seasonItems: [String: [JellyfinItem]] = [:]
        var episodeItems: [JellyfinItem] = []
        for item in items {
            if token?.isCancelled == true { throw LibraryScanError.cancelled }
            switch item.itemType {
            case "Movie": movies.append(item)
            case "Series": seriesItems[item.id] = item
            case "Season": seasonItems[item.seriesID ?? item.parentID ?? "", default: []].append(item)
            case "Episode": episodeItems.append(item)
            default: break
            }
        }
        // Derive series that only appear through episodes.
        for episode in episodeItems {
            let seriesID = episode.seriesID ?? episode.parentID ?? episode.id
            if seriesItems[seriesID] == nil {
                seriesItems[seriesID] = JellyfinItem(
                    id: seriesID,
                    name: episode.seriesName ?? "未命名剧集",
                    itemType: "Series"
                )
            }
        }
        var works: [ScannedWork] = []

        func versions(for item: JellyfinItem, prefix: String) -> [ScannedVersion] {
            let sources = item.mediaSources ?? []
            var versions: [ScannedVersion] = []
            for (index, media) in sources.enumerated() {
                let video = media.mediaStreams?.first(where: { $0.type == "Video" })
                versions.append(
                    ScannedVersion(
                        id: prefix + "-v\(index)",
                        name: media.name,
                        mediaSourceID: media.id,
                        container: media.container,
                        resolution: video?.height.map { "\($0)p" },
                        dynamicRange: jellyfinHDR(video),
                        remotePath: item.id,
                        fileURL: nil
                    )
                )
            }
            if versions.isEmpty {
                versions = [ScannedVersion(
                    id: prefix + "-v0",
                    name: "服务器版本",
                    mediaSourceID: nil,
                    container: nil,
                    resolution: nil,
                    remotePath: item.id,
                    fileURL: nil
                )]
            }
            return versions
        }

        for movie in movies {
            let workID = "jf:\(source.id):\(movie.id)"
            let episodeID = workID + "-main"
            let poster = movie.primaryImageTag.map { PosterRef.jellyfin(itemID: movie.id, tag: $0) }
            let episode = ScannedEpisode(
                id: episodeID,
                seasonNumber: 0,
                episodeNumber: 1,
                title: movie.name,
                overview: movie.overview,
                runtime: JellyfinTicks.seconds(movie.runTimeTicks),
                poster: poster,
                serverID: movie.id,
                remotePath: movie.id,
                remoteVariant: nil,
                fileURL: nil,
                versions: versions(for: movie, prefix: episodeID)
            )
            works.append(
                ScannedWork(
                    id: workID,
                    kind: .movie,
                    title: movie.name,
                    sortTitle: movie.name,
                    year: movie.productionYear,
                    overview: movie.overview,
                    poster: poster,
                    sourceKind: source.kind,
                    sourceID: source.id,
                    serverID: movie.id,
                    addedAt: Self.jellyfinDate(movie.dateCreated),
                    seasons: [],
                    movie: episode
                )
            )
        }

        for (seriesID, seriesItem) in seriesItems {
            if token?.isCancelled == true { throw LibraryScanError.cancelled }
            let workID = "jf:\(source.id):\(seriesID)"
            let posterItem = seriesItem
            let poster = posterItem.primaryImageTag.map { PosterRef.jellyfin(itemID: posterItem.id, tag: $0) }
            var episodesBySeason: [Int: [JellyfinItem]] = [:]
            for episode in episodeItems where (episode.seriesID ?? episode.parentID) == seriesID {
                episodesBySeason[episode.parentIndexNumber ?? 1, default: []].append(episode)
            }
            var seasons: [ScannedSeason] = []
            let seasonIndex = Dictionary(grouping: seasonItems[seriesID] ?? [], by: { $0.id })
            for (seasonNumber, episodes) in episodesBySeason.sorted(by: { $0.key < $1.key }) {
                let seasonID = episodes.first?.seasonID ?? "\(workID)-s\(seasonNumber)"
                let seasonItem = seasonIndex[seasonID]?.first
                let seasonPoster = (seasonItem?.primaryImageTag ?? posterItem.primaryImageTag).map {
                    PosterRef.jellyfin(itemID: seasonItem?.id ?? posterItem.id, tag: $0)
                }
                var scannedEpisodes: [ScannedEpisode] = []
                for episode in episodes.sorted(by: { ($0.indexNumber ?? 0) < ($1.indexNumber ?? 0) }) {
                    let episodeID = "jf:\(source.id):\(episode.id)"
                    let episodePoster = (episode.primaryImageTag ?? seasonItem?.primaryImageTag).map {
                        PosterRef.jellyfin(itemID: episode.primaryImageTag != nil ? episode.id : (seasonItem?.id ?? posterItem.id), tag: $0)
                    }
                    scannedEpisodes.append(
                        ScannedEpisode(
                            id: episodeID,
                            seasonNumber: episode.parentIndexNumber ?? seasonNumber,
                            episodeNumber: episode.indexNumber ?? 0,
                            title: episode.name,
                            overview: episode.overview,
                            runtime: JellyfinTicks.seconds(episode.runTimeTicks),
                            poster: episodePoster,
                            serverID: episode.id,
                            remotePath: episode.id,
                            remoteVariant: nil,
                            fileURL: nil,
                            versions: versions(for: episode, prefix: episodeID)
                        )
                    )
                }
                seasons.append(
                    ScannedSeason(
                        id: seasonID,
                        number: seasonNumber,
                        title: seasonItem?.name ?? "第 \(seasonNumber) 季",
                        poster: seasonPoster,
                        episodes: scannedEpisodes
                    )
                )
            }
            // A season with no episodes still belongs in the library.
            for seasonItem in seasonItems[seriesID] ?? [] where !seasons.contains(where: { $0.id == seasonItem.id }) {
                seasons.append(
                    ScannedSeason(
                        id: seasonItem.id,
                        number: seasonItem.indexNumber ?? 1,
                        title: seasonItem.name,
                        poster: seasonItem.primaryImageTag.map { PosterRef.jellyfin(itemID: seasonItem.id, tag: $0) },
                        episodes: []
                    )
                )
            }
            seasons.sort { $0.number < $1.number }
            works.append(
                ScannedWork(
                    id: workID,
                    kind: .series,
                    title: seriesItem.name,
                    sortTitle: seriesItem.name,
                    year: seriesItem.productionYear,
                    overview: seriesItem.overview,
                    poster: poster,
                    sourceKind: source.kind,
                    sourceID: source.id,
                    serverID: seriesID,
                    addedAt: Self.jellyfinDate(seriesItem.dateCreated),
                    seasons: seasons,
                    movie: nil
                )
            )
        }

        return JellyfinScanResult(
            library: ScannedLibrary(
                sourceKind: source.kind,
                sourceID: source.id,
                sourceName: source.name,
                works: works.sorted { $0.sortTitle.localizedStandardCompare($1.sortTitle) == .orderedAscending }
            ),
            issues: issues
        )
    }

    static func jellyfinHDR(_ stream: JellyfinMediaStream?) -> String? {
        guard let stream else { return nil }
        let type = (stream.videoRangeType ?? "").lowercased()
        if type.contains("dovi") || type.contains("dolby") { return "Dolby Vision" }
        if type.contains("hdr10+") || type.contains("hdr10plus") { return "HDR10+" }
        if type.contains("hdr10") { return "HDR10" }
        if type.contains("hlg") { return "HLG" }
        if (stream.videoRange ?? "").lowercased() == "hdr" { return "HDR" }
        return nil
    }

    static func jellyfinDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    // MARK: - WebDAV

    public static func scanWebDAV(
        source: WebDAVSource,
        client: WebDAVClient,
        rootPath: String = "",
        maxDepth: Int = 6,
        maxFiles: Int = 3000,
        posterCacheDirectory: URL? = nil,
        token: ScanCancellationToken? = nil,
        progress: ((Int) -> Void)? = nil
    ) async throws -> ScannedLibrary {
        var queue: [(path: String, depth: Int)] = [(rootPath, 0)]
        var candidates: [FileCandidate] = []
        var postersByDirectory: [String: String] = [:]  // value: remote path
        var nfoByKey: [String: NFOMetadata] = [:]
        var movieNFOByDirectory: [String: NFOMetadata] = [:]
        var showNFOByDirectory: [String: NFOMetadata] = [:]
        var visited = 0
        var downloadedPosters = 0
        var failedPaths: [String] = []
        if let posterCacheDirectory {
            try? FileManager.default.createDirectory(at: posterCacheDirectory, withIntermediateDirectories: true)
        }

        func probeRemoteHeight(_ remotePath: String) async -> (height: String?, dynamicRange: String?) {
            let ext = (remotePath as NSString).pathExtension.lowercased()
            guard let header = client.basicAuthorizationHeader else { return (nil, nil) }
            if ["mp4", "m4v", "mov"].contains(ext) {
                let loader = AuthenticatedAssetLoader(
                    url: client.url(for: remotePath),
                    headers: ["Authorization": header]
                )
                let asset = loader.makeAsset()
                guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                      let size = try? await track.load(.naturalSize) else { return (nil, nil) }
                let height = Int(abs(size.height).rounded())
                guard height > 0 else { return (nil, nil) }
                return (height >= 2000 ? "2160p" : "\(height)p", nil)
            }
            guard ["mkv", "webm", "ts", "m2ts", "avi"].contains(ext) else { return (nil, nil) }
            #if os(macOS)
            let preferHeader = ProcessInfo.processInfo.environment["OPENFUSE_MKV_HEADER"] == "1"
            #else
            let preferHeader = true
            #endif
            if preferHeader || ext == "mkv" {
                if let (data, _) = try? await client.fetch(path: remotePath, range: 0..<2_000_000),
                   let header = MatroskaProbe.parse(data) {
                    return (header.resolution, header.dynamicRange)
                }
            }
            return await Self.probeRemoteVideoHeight(
                url: client.url(for: remotePath),
                authorization: header
            ) ?? (nil, nil)
        }

        func contentFingerprint(_ entry: RemoteEntry) async -> String? {
            guard entry.size > 0 else { return nil }
            let chunk = Int64(ContentFingerprint.chunkSize)
            let firstLength = min(chunk, entry.size)
            guard let (first, _) = try? await client.fetch(
                path: entry.path, range: 0..<firstLength
            ), !first.isEmpty else { return nil }
            var last: Data?
            if entry.size > chunk,
               let (value, _) = try? await client.fetch(
                   path: entry.path, range: (entry.size - chunk)..<entry.size
               ) {
                last = value
            }
            return ContentFingerprint.key(size: entry.size, first: first, last: last)
        }

        func cachePoster(remotePath: String) async -> String? {
            guard let posterCacheDirectory, downloadedPosters < 300, !remotePath.isEmpty else { return nil }
            let ext = (remotePath as NSString).pathExtension.lowercased()
            let suffix = ["jpg", "jpeg", "png", "webp"].contains(ext) ? ext : "jpg"
            let name = LibraryID.hash(remotePath) + "." + suffix
            let destination = posterCacheDirectory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: destination.path) {
                downloadedPosters += 1
                return destination.path
            }
            guard let (data, _) = try? await client.fetch(path: remotePath), !data.isEmpty else {
                return nil
            }
            try? data.write(to: destination, options: .atomic)
            downloadedPosters += 1
            return destination.path
        }

        while !queue.isEmpty {
            if token?.isCancelled == true { throw LibraryScanError.cancelled }
            let current = queue.removeFirst()
            let entries: [RemoteEntry]
            do {
                entries = try await client.list(path: current.path)
            } catch {
                if token?.isCancelled == true { throw LibraryScanError.cancelled }
                failedPaths.append(current.path)
                progress?(visited)
                continue
            }
            progress?(visited)
            for entry in entries where entry.isDirectory {
                if current.depth < maxDepth { queue.append((entry.path, current.depth + 1)) }
            }
            // Posters must be known before videos in the same directory are
            // turned into candidates; directory listings are sorted by name.
            for entry in entries where !entry.isDirectory && imageExtensions.contains(entry.fileExtension) {
                let directory = (entry.path as NSString).deletingLastPathComponent
                let base = (entry.name as NSString).deletingPathExtension.lowercased()
                if ["poster", "folder", "cover"].contains(base) || entry.name.lowercased().contains("poster") {
                    postersByDirectory[directory + "|dir"] = entry.path
                }
                postersByDirectory[directory + "|" + base] = entry.path
            }
            // NFO files are fetched with the same auth as media. Parsing keeps
            // the raw poster reference so relative names can be resolved later.
            for entry in entries where !entry.isDirectory && entry.fileExtension == "nfo" {
                guard let (data, _) = try? await client.fetch(path: entry.path),
                      let metadata = NFOReader.parse(
                        data: data,
                        baseURL: URL(fileURLWithPath: "/remote/" + entry.path)
                      )
                else { continue }
                let directory = (entry.path as NSString).deletingLastPathComponent
                let base = (entry.name as NSString).deletingPathExtension.lowercased()
                if base == "tvshow" {
                    showNFOByDirectory[directory] = metadata
                } else if base == "movie" {
                    movieNFOByDirectory[directory] = metadata
                } else {
                    nfoByKey[directory + "|" + base] = metadata
                }
            }

            for entry in entries where !entry.isDirectory && videoExtensions.contains(entry.fileExtension) {
                visited += 1
                if visited > maxFiles { break }
                let directory = (entry.path as NSString).deletingLastPathComponent
                let parent = (directory as NSString).deletingLastPathComponent
                let base = (entry.name as NSString).deletingPathExtension.lowercased()
                let nfo = nfoByKey[directory + "|" + base] ?? movieNFOByDirectory[directory]
                let showDirectory = showNFOByDirectory[directory] != nil ? directory : parent
                let showNFO = showNFOByDirectory[directory] ?? showNFOByDirectory[parent]
                var posterPath: String?
                var posterURL: String?

                var nfoPoster: (reference: String, directory: String)?
                if let reference = nfo?.posterReference, !reference.isEmpty {
                    nfoPoster = (reference, directory)
                } else if let reference = showNFO?.posterReference, !reference.isEmpty {
                    nfoPoster = (reference, showDirectory)
                }
                if let nfoPoster {
                    if nfoPoster.reference.hasPrefix("http://") || nfoPoster.reference.hasPrefix("https://") {
                        posterURL = nfoPoster.reference
                    } else {
                        let remote = nfoPoster.directory + "/" + nfoPoster.reference
                        if let cached = await cachePoster(remotePath: remote) {
                            posterPath = cached
                        } else {
                            posterURL = client.url(for: remote).absoluteString
                        }
                    }
                } else if let remote = postersByDirectory[directory + "|" + base]
                            ?? postersByDirectory[directory + "|dir"]
                            ?? postersByDirectory[parent + "|dir"] {
                    if let cached = await cachePoster(remotePath: remote) {
                        posterPath = cached
                    } else {
                        posterURL = client.url(for: remote).absoluteString
                    }
                }

                if let (header, _) = try? await client.fetch(path: entry.path, range: 0..<64),
                   !MediaSignature.looksLikeVideo(name: entry.name, header: header) {
                    continue
                }
                let probe = await probeRemoteHeight(entry.path)
                let contentKey = await contentFingerprint(entry)
                candidates.append(
                    FileCandidate(
                        relativePath: entry.path,
                        name: entry.name,
                        fileURL: nil,
                        remotePath: entry.path,
                        posterPath: posterPath,
                        posterURL: posterURL,
                        nfo: nfo,
                        showNFO: showNFO,
                        modifiedAt: entry.modifiedAt,
                        resolution: probe.height,
                        dynamicRange: probe.dynamicRange,
                        contentKey: contentKey
                    )
                )
            }
            if visited > maxFiles { break }
        }
        if candidates.isEmpty { throw LibraryScanError.noMedia }
        return buildLibrary(
            candidates: candidates,
            sourceKind: "webdav",
            sourceID: source.id,
            sourceName: source.name,
            failedPaths: failedPaths
        )
    }
}
