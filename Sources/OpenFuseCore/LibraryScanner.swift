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
        var videoFiles: [(URL, String, NFOMetadata?, NFOMetadata?)] = []
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
            videoFiles.append((file, relative, movieNFO ?? episodeNFO, showNFO))
        }
        let candidates = videoFiles.map { file, relative, nfo, showNFO in
            FileCandidate(
                relativePath: relative,
                name: file.lastPathComponent,
                fileURL: file,
                remotePath: nil,
                posterPath: findLocalPoster(for: file, relativePath: relative, directory: directory, posterMap: posterMap),
                posterURL: nil,
                nfo: nfo,
                showNFO: showNFO
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
        sourceName: String
    ) -> ScannedLibrary {
        struct SeriesBucket {
            var title: String
            var year: Int?
            var overview: String?
            var posterPath: String?
            var posterURL: String?
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
            let workID = LibraryID.hash("\(sourceID)|movie|\(candidate.relativePath)", prefix: sourceKind == "local" ? "local-" : "webdav-")
            let episodeID = workID + "-main"
            let versionID = episodeID + "-v0"
            let poster = candidate.nfo?.posterPath.map { PosterRef.file($0) }
                ?? candidate.nfo?.posterURL.map { PosterRef.remote($0.absoluteString) }
                ?? candidate.posterPath.map { PosterRef.file($0) }
                ?? candidate.posterURL.map { PosterRef.remote($0) }
            let version = ScannedVersion(
                id: versionID,
                name: sourceKind == "local" ? "本地文件" : "WebDAV",
                mediaSourceID: nil,
                container: (candidate.name as NSString).pathExtension.uppercased(),
                resolution: nil,
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
                    seasons: [],
                    movie: episode
                )
            )
        }

        for (_, bucket) in series {
            let title = bucket.title.isEmpty ? "未命名剧集" : bucket.title
            let workID = LibraryID.hash("\(sourceID)|series|\(title.lowercased())", prefix: sourceKind == "local" ? "local-" : "webdav-")
            let poster = bucket.posterPath.map { PosterRef.file($0) } ?? bucket.posterURL.map { PosterRef.remote($0) }
            var seasonMap: [Int: [ScannedEpisode]] = [:]
            for (parsed, candidate) in bucket.episodes {
                let season = max(1, parsed.season ?? 1)
                let episode = max(1, parsed.episode ?? 1)
                let episodeID = workID + "-s\(season)e\(episode)-" + String(LibraryID.hash(candidate.relativePath).prefix(8))
                let versionID = episodeID + "-v0"
                let version = ScannedVersion(
                    id: versionID,
                    name: sourceKind == "local" ? "本地文件" : "WebDAV",
                    mediaSourceID: nil,
                    container: (candidate.name as NSString).pathExtension.uppercased(),
                    resolution: nil,
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
                    seasons: seasons,
                    movie: nil
                )
            )
        }

        return ScannedLibrary(
            sourceKind: sourceKind,
            sourceID: sourceID,
            sourceName: sourceName,
            works: works.sorted { $0.sortTitle.localizedStandardCompare($1.sortTitle) == .orderedAscending }
        )
    }

    // MARK: - Jellyfin

    public static func scanJellyfin(
        source: JellyfinSource,
        client: JellyfinClient,
        token: ScanCancellationToken? = nil,
        progress: ((Int) -> Void)? = nil
    ) async throws -> ScannedLibrary {
        let views = try await client.views()
        var items: [JellyfinItem] = []
        for (index, view) in views.enumerated() {
            if token?.isCancelled == true { throw LibraryScanError.cancelled }
            items.append(contentsOf: (try? await client.libraryItems(parentID: view.id)) ?? [])
            progress?(items.count + index)
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

        for movie in movies {
            let workID = "jf:\(source.id):\(movie.id)"
            let episodeID = workID + "-main"
            let poster = movie.primaryImageTag.map { PosterRef.jellyfin(itemID: movie.id, tag: $0) }
            var versions: [ScannedVersion] = []
            if let info = try? await client.playbackInfo(itemID: movie.id) {
                for (index, media) in info.mediaSources.enumerated() {
                    versions.append(
                        ScannedVersion(
                            id: episodeID + "-v\(index)",
                            name: media.name,
                            mediaSourceID: media.id,
                            container: media.container,
                            resolution: nil,
                            remotePath: movie.id,
                            fileURL: nil
                        )
                    )
                }
            }
            if versions.isEmpty {
                versions = [ScannedVersion(
                    id: episodeID + "-v0",
                    name: "服务器版本",
                    mediaSourceID: nil,
                    container: nil,
                    resolution: nil,
                    remotePath: movie.id,
                    fileURL: nil
                )]
            }
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
                versions: versions
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
                    sourceKind: "jellyfin",
                    sourceID: source.id,
                    serverID: movie.id,
                    seasons: [],
                    movie: episode
                )
            )
        }

        for (seriesID, seriesItem) in seriesItems {
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
                let scannedEpisodes = episodes.sorted { ($0.indexNumber ?? 0) < ($1.indexNumber ?? 0) }.map { episode -> ScannedEpisode in
                    let episodeID = "jf:\(source.id):\(episode.id)"
                    let episodePoster = (episode.primaryImageTag ?? seasonItem?.primaryImageTag).map {
                        PosterRef.jellyfin(itemID: episode.primaryImageTag != nil ? episode.id : (seasonItem?.id ?? posterItem.id), tag: $0)
                    }
                    let version = ScannedVersion(
                        id: episodeID + "-v0",
                        name: "服务器版本",
                        mediaSourceID: nil,
                        container: nil,
                        resolution: nil,
                        remotePath: episode.id,
                        fileURL: nil
                    )
                    return ScannedEpisode(
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
                        versions: [version]
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
                    sourceKind: "jellyfin",
                    sourceID: source.id,
                    serverID: seriesID,
                    seasons: seasons,
                    movie: nil
                )
            )
        }

        return ScannedLibrary(
            sourceKind: "jellyfin",
            sourceID: source.id,
            sourceName: source.name,
            works: works.sorted { $0.sortTitle.localizedStandardCompare($1.sortTitle) == .orderedAscending }
        )
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
        if let posterCacheDirectory {
            try? FileManager.default.createDirectory(at: posterCacheDirectory, withIntermediateDirectories: true)
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
            let entries = try await client.list(path: current.path)
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

                candidates.append(
                    FileCandidate(
                        relativePath: entry.path,
                        name: entry.name,
                        fileURL: nil,
                        remotePath: entry.path,
                        posterPath: posterPath,
                        posterURL: posterURL,
                        nfo: nfo,
                        showNFO: showNFO
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
            sourceName: source.name
        )
    }
}
