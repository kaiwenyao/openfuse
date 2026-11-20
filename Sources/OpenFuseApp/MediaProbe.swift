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
                    if copy.resolution == nil, let path = copy.fileURL.flatMap(URL.init(string:)) {
                        copy.resolution = heightLabel(for: path)
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
                        if copy.resolution == nil, let path = copy.fileURL.flatMap(URL.init(string:)) {
                            copy.resolution = heightLabel(for: path)
                        }
                        return copy
                    }
                    result.works[workIndex].seasons[seasonIndex].episodes[episodeIndex] = episode
                }
            }
        }
        return result
    }

    private static func heightLabel(for url: URL) -> String? {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size > 1_048_576 else { return nil }
        let candidates = ["/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe", "/usr/bin/ffprobe"]
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return nil
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = [
            "-v", "error", "-select_streams", "v:0",
            "-show_entries", "stream=height", "-of", "csv=p=0", url.path,
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0,
              let data = try? pipe.fileHandleForReading.readToEnd(),
              let text = String(data: data, encoding: .utf8),
              let height = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return height >= 2000 ? "2160p" : "\(height)p"
    }
}
