import AppKit
import OpenFuseCore

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
    private var failures: Set<String> = []

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

    func configure(itemKey: String, url: URL, headers: [String]) {
        let next = Config(itemKey: itemKey, url: url, headers: headers)
        guard next != config else { return }
        config = next
        generation &+= 1
        cache.removeAll()
        failures.removeAll()
        lastTime = nil
        lastBytes = 0
        queue.async { [box] in
            box.engine?.stop()
            box.engine = nil
        }
    }

    func shutdown() {
        generation &+= 1
        config = nil
        cache.removeAll()
        failures.removeAll()
        lastTime = nil
        lastBytes = 0
        queue.async { [box] in
            box.engine?.stop()
            box.engine = nil
        }
    }

    func cachedImage(for time: Double) -> NSImage? {
        guard let config else { return nil }
        return cache[Self.key(item: config.itemKey, bucket: ThumbnailMath.bucket(for: time))]
    }

    func image(for time: Double) async -> NSImage? {
        guard let config else { return nil }
        let bucket = ThumbnailMath.bucket(for: time)
        let key = Self.key(item: config.itemKey, bucket: bucket)
        if let cached = cache[key] { return cached }
        if failures.contains(key) { return nil }

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
        if cache.count >= 80 { cache.removeAll() }
        cache[key] = image
        lastTime = start
        lastBytes = data.count
        return image
    }

    private static func key(item: String, bucket: Int) -> String {
        "\(item)#\(bucket)"
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
