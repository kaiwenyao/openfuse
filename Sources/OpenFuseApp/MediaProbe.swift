import Foundation
import OpenFuseCore

enum MediaProbe {
    static func enrichLocalResolutions(_ library: ScannedLibrary) -> ScannedLibrary {
        var result = library
        for workIndex in result.works.indices {
            if let movie = result.works[workIndex].movie {
                var updated = movie
                updated.versions = movie.versions.map { version in
                    var copy = version
                    if let path = copy.fileURL.flatMap(URL.init(string:)) {
                        let probe = probeVideo(path)
                        if copy.resolution == nil { copy.resolution = probe.height }
                        if copy.dynamicRange == nil { copy.dynamicRange = probe.dynamicRange }
                    }
                    return copy
                }
                result.works[workIndex].movie = updated
            }
            for seasonIndex in result.works[workIndex].seasons.indices {
                for episodeIndex in result.works[workIndex].seasons[seasonIndex].episodes.indices {
                    var episode = result.works[workIndex].seasons[seasonIndex].episodes[episodeIndex]
                    episode.versions = episode.versions.map { version in
                        var copy = version
                        if let path = copy.fileURL.flatMap(URL.init(string:)) {
                            let probe = probeVideo(path)
                            if copy.resolution == nil { copy.resolution = probe.height }
                            if copy.dynamicRange == nil { copy.dynamicRange = probe.dynamicRange }
                        }
                        return copy
                    }
                    result.works[workIndex].seasons[seasonIndex].episodes[episodeIndex] = episode
                }
            }
        }
        return result
    }

    private static func probeVideo(_ url: URL) -> (height: String?, dynamicRange: String?) {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size > 1_048_576 else { return (nil, nil) }
        let candidates = ["/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe", "/usr/bin/ffprobe"]
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return (nil, nil)
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
            return (nil, nil)
        }
        guard process.terminationStatus == 0,
              let data = try? pipe.fileHandleForReading.readToEnd(),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let streams = object["streams"] as? [[String: Any]],
              let stream = streams.first else {
            return (nil, nil)
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
        return (height, dynamicRange)
    }
}
