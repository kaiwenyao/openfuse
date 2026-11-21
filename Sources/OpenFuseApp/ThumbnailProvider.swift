import AppKit
import OpenFuseCore
import OpenFuseData

/// Generates scrubber hover previews with a private, audio-less libmpv engine
/// that writes one decoded frame as a PNG (`vo=image`, `frames=1`). The
/// playback engine is never seeked, so previews cannot disturb playback.
@MainActor
final class ThumbnailProvider {
    private struct Config: Equatable {
        let itemKey: String
        let url: URL
        let headers: [String]
    }

    /// Box so the nonisolated thumbnail queue can own the preview engine
    /// without touching main-actor state.
    private final class EngineBox: @unchecked Sendable {
        var engine: MPVEngine?
    }

    /// Marks the newest hover request so a queue of stale thumbnail jobs exits
    /// before loading/seeking instead of delaying the preview the user wants.
    private final class RequestBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func next() -> Int {
            lock.lock(); defer { lock.unlock() }
            value += 1
            return value
        }
        func isCurrent(_ id: Int) -> Bool {
            lock.lock(); defer { lock.unlock() }
            return id == value
        }
    }

    private let queue = DispatchQueue(label: "openfuse.thumbnails", qos: .userInitiated)
    private nonisolated let box = EngineBox()
    private nonisolated let requests = RequestBox()
    private var config: Config?
    private var generation = 0
    private var cache: [String: NSImage] = [:]
    private var cacheOrder: [String] = []
    private var failures: Set<String> = []
    private var diskDirectory: URL?
    private var trickplay: JellyfinTrickplaySource?
    private(set) var lastSource = ""
    private(set) var lastElapsedMs = 0
    private(set) var diskHits = 0
    private(set) var trickplayHits = 0

    private(set) var lastTime: Double?
    private(set) var lastBytes = 0
    var cacheCount: Int { cache.count }

    nonisolated let outputDir: URL

    init() {
        let env = ProcessInfo.processInfo.environment["OPENFUSE_THUMBNAIL_DIR"]
        if let env, !env.isEmpty {
            outputDir = URL(fileURLWithPath: env, isDirectory: true)
        } else {
            outputDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("OpenFuseThumbnails", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    }

    func configure(
        itemKey: String,
        url: URL,
        headers: [String],
        cacheDirectory: URL? = nil,
        trickplay: JellyfinTrickplaySource? = nil
    ) {
        self.trickplay = trickplay
        if ProcessInfo.processInfo.environment["OPENFUSE_DEBUG_THUMBS"] == "1" {
            print("[thumb] configure trickplay=\(trickplay != nil) item=\(itemKey)")
        }
        if let cacheDirectory {
            diskDirectory = cacheDirectory
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
        let next = Config(itemKey: itemKey, url: url, headers: headers)
        guard next != config else { return }
        config = next
        generation &+= 1
        cache.removeAll()
        cacheOrder.removeAll()
        failures.removeAll()
        lastTime = nil
        lastBytes = 0
        lastSource = ""
        lastElapsedMs = 0
        diskHits = 0
        trickplayHits = 0
        queue.async { [box] in
            box.engine?.stop()
            box.engine = nil
        }
    }

    func shutdown() {
        generation &+= 1
        config = nil
        cache.removeAll()
        cacheOrder.removeAll()
        failures.removeAll()
        lastTime = nil
        lastBytes = 0
        lastSource = ""
        lastElapsedMs = 0
        diskHits = 0
        trickplayHits = 0
        queue.async { [box] in
            box.engine?.stop()
            box.engine = nil
        }
    }

    func cachedImage(for time: Double) -> NSImage? {
        guard let config else { return nil }
        let key = Self.key(item: config.itemKey, bucket: ThumbnailMath.bucket(for: time))
        guard let image = cache[key] else { return nil }
        touch(key)
        lastSource = "memory"
        return image
    }

    /// Disk lookup is asynchronous and never touches libmpv. A hit is promoted
    /// into the bounded LRU memory cache.
    func cachedOrDiskImage(for time: Double) async -> NSImage? {
        guard let config else { return nil }
        let bucket = ThumbnailMath.bucket(for: time)
        let key = Self.key(item: config.itemKey, bucket: bucket)
        if let cached = cachedImage(for: time) { return cached }
        guard let directory = diskDirectory else { return nil }
        let file = Self.diskURL(directory: directory, item: config.itemKey, bucket: bucket)
        let data = await Task.detached(priority: .userInitiated) { try? Data(contentsOf: file) }.value
        guard let data, let image = NSImage(data: data) else { return nil }
        guard config == self.config else { return nil }
        insert(image, key: key)
        diskHits += 1
        lastSource = "disk"
        return image
    }

    private func touch(_ key: String) {
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
    }

    private func insert(_ image: NSImage, key: String) {
        if cache[key] == nil, cache.count >= 80, let oldest = cacheOrder.first {
            cache.removeValue(forKey: oldest)
            cacheOrder.removeFirst()
        }
        cache[key] = image
        touch(key)
    }

    func image(for time: Double) async -> NSImage? {
        guard let config else { return nil }
        let bucket = ThumbnailMath.bucket(for: time)
        let key = Self.key(item: config.itemKey, bucket: bucket)
        if let cached = cache[key] { lastSource = "memory"; touch(key); return cached }
        if failures.contains(key) { return nil }
        if let disk = await cachedOrDiskImage(for: time) { return disk }
        let started = CFAbsoluteTimeGetCurrent()
        if ProcessInfo.processInfo.environment["OPENFUSE_DEBUG_THUMBS"] == "1" {
            print("[thumb] try trickplay=\(trickplay != nil) bucket=\(bucket)")
        }
        if let trickplay, let image = await trickplayImage(for: time, source: trickplay, key: key) {
            insert(image, key: key)
            trickplayHits += 1
            lastSource = "trickplay"
            lastElapsedMs = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
            if let directory = diskDirectory,
               let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let data = rep.representation(using: .png, properties: [:]) {
                let file = Self.diskURL(directory: directory, item: config.itemKey, bucket: bucket)
                try? data.write(to: file, options: .atomic)
            }
            return image
        }

        let start = ThumbnailMath.bucketTime(bucket)
        let gen = generation
        let requestID = requests.next()
        let box = self.box
        let requests = self.requests
        let outputDir = self.outputDir
        let data: Data? = await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Self.generate(
                    box: box,
                    outputDir: outputDir,
                    start: start,
                    config: config,
                    requests: requests,
                    requestID: requestID
                ))
            }
        }
        guard gen == generation, requests.isCurrent(requestID) else { return nil }

        guard let data, let image = NSImage(data: data) else {
            failures.insert(key)
            return nil
        }
        insert(image, key: key)
        lastTime = start
        lastBytes = data.count
        lastSource = "decode"
        lastElapsedMs = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
        if let directory = diskDirectory {
            let file = Self.diskURL(directory: directory, item: config.itemKey, bucket: bucket)
            await Task.detached(priority: .utility) {
                try? data.write(to: file, options: .atomic)
            }.value
            Self.pruneDisk(directory: directory)
        }
        return image
    }

    private func trickplayImage(for time: Double, source: JellyfinTrickplaySource, key: String) async -> NSImage? {
        let info = source.info
        if ProcessInfo.processInfo.environment["OPENFUSE_DEBUG_THUMBS"] == "1" {
            print("[thumb] trickplay start time=\(time) item=\(source.itemID)")
        }
        guard info.interval > 0, info.width > 0, info.height > 0,
              info.tileWidth > 0, info.tileHeight > 0 else { return nil }
        let index = Int((max(0, time) * 1000) / Double(info.interval))
        guard index >= 0, index < info.thumbnailCount else { return nil }
        let path = "Items/\(source.itemID)/Trickplay/\(info.width)/\(index).jpg"
        let url = source.baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.setValue(source.token, forHTTPHeaderField: "X-Emby-Token")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let tile = NSImage(data: data) else {
            if ProcessInfo.processInfo.environment["OPENFUSE_DEBUG_THUMBS"] == "1" {
                print("[thumb] trickplay fetch failed \(url.absoluteString)")
            }
            return nil
        }
        var rect = CGRect.zero
        if let cg = tile.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            let col = index % info.tileWidth
            let row = index / info.tileWidth
            let crop = CGRect(x: col * info.width, y: row * info.height, width: info.width, height: info.height)
            if let cropped = cg.cropping(to: crop) {
                if ProcessInfo.processInfo.environment["OPENFUSE_DEBUG_THUMBS"] == "1" {
                    print("[thumb] trickplay index=\(index) tile=\(url.lastPathComponent)")
                }
                return NSImage(cgImage: cropped, size: NSSize(width: info.width, height: info.height))
            }
        }
        return tile
    }

    private static func key(item: String, bucket: Int) -> String {
        "\(item)#\(bucket)"
    }

    private static func stableHash(_ value: String) -> UInt64 {
        var hash: UInt64 = 1469598103934665603
        for byte in value.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return hash
    }

    private static func diskURL(directory: URL, item: String, bucket: Int) -> URL {
        directory.appendingPathComponent(String(format: "%016llx-%d.png", stableHash(item), bucket))
    }

    nonisolated private static func pruneDisk(directory: URL, maxFiles: Int = 400, maxBytes: Int64 = 64 * 1024 * 1024) {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        let sorted = files.sorted {
            let a = (try? $0.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            return a > b
        }
        var total: Int64 = 0
        for (index, file) in sorted.enumerated() {
            let size = Int64((try? file.resourceValues(forKeys: Set(keys)).fileSize) ?? 0)
            total += size
            if index >= maxFiles || total > maxBytes {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    // MARK: - Queue-only work

    nonisolated private static func generate(
        box: EngineBox,
        outputDir: URL,
        start: Double,
        config: Config,
        requests: RequestBox,
        requestID: Int
    ) -> Data? {
        let fm = FileManager.default
        try? fm.createDirectory(at: outputDir, withIntermediateDirectories: true)
        removePNGs(in: outputDir)

        if box.engine == nil {
            box.engine = MPVEngine(httpHeaders: config.headers, thumbnailOutput: outputDir)
        }
        guard let engine = box.engine else { return nil }
        guard requests.isCurrent(requestID) else { return nil }

        engine.setProperty("start", String(format: "%.3f", start))
        engine.load(url: config.url)
        engine.play()

        // Local seeks finish in a few hundred ms; a remote seek has to fetch a
        // new range first, so allow more time. Hovering never waits on this
        // queue synchronously: the UI shows a spinner until the image arrives.
        let timeout: TimeInterval = config.url.isFileURL ? 2.5 : 8.0
        let deadline = Date().addingTimeInterval(timeout)
        var lastSize = -1

        while Date() < deadline {
            if !requests.isCurrent(requestID) { return nil }
            if let file = pngFiles(in: outputDir).first {
                let size = (try? fm.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
                if size > 0, size == lastSize {
                    return try? Data(contentsOf: file)
                }
                lastSize = size
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return nil
    }

    nonisolated private static func pngFiles(in outputDir: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: outputDir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return files.filter { $0.pathExtension.lowercased() == "png" }.sorted { $0.path < $1.path }
    }

    nonisolated private static func removePNGs(in outputDir: URL) {
        for file in pngFiles(in: outputDir) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
