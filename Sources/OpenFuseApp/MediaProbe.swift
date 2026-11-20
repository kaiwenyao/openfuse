import CryptoKit
import Foundation
import OpenFuseCore

enum MediaProbe {
    private struct VideoInfo {
        var height: String?
        var dynamicRange: String?
        var playable: Bool?
    }

    static func enrichLocalResolutions(_ library: ScannedLibrary) -> ScannedLibrary {
        var result = library
        var works: [ScannedWork] = []
        for var work in result.works {
            if var movie = work.movie {
                movie.versions = filtered(movie.versions)
                work.movie = movie.versions.isEmpty ? nil : movie
            }
            work.seasons = work.seasons.compactMap { season in
                var season = season
                season.episodes = season.episodes.compactMap { episode in
                    var episode = episode
                    episode.versions = filtered(episode.versions)
                    return episode.versions.isEmpty ? nil : episode
                }
                return season.episodes.isEmpty ? nil : season
            }
            if work.movie != nil || !work.seasons.isEmpty {
                works.append(work)
            }
        }
        result.works = works
        return result
    }

    private static func filtered(_ versions: [ScannedVersion]) -> [ScannedVersion] {
        versions.compactMap { version in
            guard let path = version.fileURL.flatMap(URL.init(string:)) else { return version }
            let probe = probeVideo(path)
            if probe.playable == false { return nil }
            var copy = version
            if copy.resolution == nil { copy.resolution = probe.height }
            if copy.dynamicRange == nil { copy.dynamicRange = probe.dynamicRange }
            if copy.contentKey == nil { copy.contentKey = contentKey(path) }
            return copy
        }
    }

    private static func contentKey(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        guard size > 0 else { return nil }
        let chunk: UInt64 = 65_536
        var hasher = SHA256()
        withUnsafeBytes(of: size.littleEndian) { hasher.update(bufferPointer: $0) }
        if let first = try? handle.read(upToCount: Int(min(chunk, size))), !first.isEmpty {
            hasher.update(data: first)
        }
        if size > chunk {
            try? handle.seek(toOffset: size - chunk)
            if let last = try? handle.read(upToCount: Int(chunk)), !last.isEmpty {
                hasher.update(data: last)
            }
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return String(digest.prefix(32))
    }

    private static func probeVideo(_ url: URL) -> VideoInfo {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size > 1024 else { return VideoInfo(playable: false) }
        let candidates = ["/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe", "/usr/bin/ffprobe"]
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return VideoInfo()
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = [
            "-v", "error", "-select_streams", "v:0",
            "-show_entries", "stream=height,color_transfer,color_primaries", "-of", "json", url.path,
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return VideoInfo()
        }
        guard process.terminationStatus == 0,
              let data = try? pipe.fileHandleForReading.readToEnd(),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let streams = object["streams"] as? [[String: Any]],
              let stream = streams.first else {
            return VideoInfo(playable: false)
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
        return VideoInfo(height: height, dynamicRange: dynamicRange, playable: true)
    }
}
