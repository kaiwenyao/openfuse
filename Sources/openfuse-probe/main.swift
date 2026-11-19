import AppKit
import AVFoundation
import Foundation
import OpenFuseCore
import QuartzCore

// Headless verification tool used by Scripts/eval_engines.sh and by the
// acceptance records in Docs/. It never opens a window.

struct ProbeResult: Codable {
    var engine: String
    var file: String
    var playable: Bool
    var duration: Double
    var position: Double
    var videoCodec: String?
    var audioCodec: String?
    var audioChannels: Int?
    var hwdec: String?
    var tracks: [Track]
    var error: String?
    var elapsedToFirstFrame: Double?

    struct Track: Codable {
        var type: String
        var codec: String?
        var language: String?
        var channels: Int?
        var title: String?
        var external: Bool
    }
}

func printJSON(_ result: ProbeResult) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(result), let text = String(data: data, encoding: .utf8) {
        print(text)
    }
}

func runMPV(path: String, seek: Double?, playSeconds: Double) -> ProbeResult {
    let engine = MPVEngine(headless: true)
    var duration: Double = 0
    var position: Double = 0
    var tracks: [MPVTrackInfo] = []
    var loadedAt: Date?
    var firstTime: Double?
    var errorMessage: String?
    var fileLoaded = false

    engine.onDurationChanged = { duration = $0 }
    engine.onTimeChanged = { value in
        position = value
        if firstTime == nil, value > 0 { firstTime = Date().timeIntervalSince(loadedAt ?? Date()) }
    }
    engine.onTracksChanged = { tracks = $0 }
    engine.onFileLoaded = {
        fileLoaded = true
        loadedAt = Date()
    }
    engine.onLog = { message in
        if message.contains("error") || message.contains("failed") { errorMessage = message }
    }
    engine.load(url: URL(fileURLWithPath: path), startAt: 0)
    engine.play()

    let deadline = Date().addingTimeInterval(playSeconds + 4)
    while Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        if fileLoaded, duration > 0, Date().timeIntervalSince(loadedAt ?? Date()) > 1.5 { break }
    }
    if let seek {
        engine.seek(to: seek)
        let seekDeadline = Date().addingTimeInterval(3)
        while Date() < seekDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            if abs(position - seek) < 1.0 { break }
        }
    }
    let result = ProbeResult(
        engine: "libmpv",
        file: path,
        playable: fileLoaded,
        duration: duration,
        position: position,
        videoCodec: engine.getPropertyString("video-codec"),
        audioCodec: engine.getPropertyString("audio-codec-name"),
        audioChannels: engine.getPropertyString("audio-params/channel-count").flatMap(Int.init),
        hwdec: engine.getPropertyString("hwdec-current"),
        tracks: tracks.map { ProbeResult.Track(type: $0.type, codec: $0.codec, language: $0.language, channels: $0.channels, title: $0.title, external: $0.external) },
        error: errorMessage,
        elapsedToFirstFrame: firstTime
    )
    engine.command(["quit"])
    return result
}

func runAVPlayer(path: String) -> ProbeResult {
    let url = URL(fileURLWithPath: path)
    let asset = AVURLAsset(url: url)
    var playable = false
    var duration: Double = 0
    var tracks: [ProbeResult.Track] = []
    var errorMessage: String?
    do {
        playable = asset.isPlayable
        duration = asset.duration.seconds
        let loaded = asset.tracks
        for track in loaded {
            let type: String
            switch track.mediaType {
            case .video: type = "video"
            case .audio: type = "audio"
            case .subtitle: type = "sub"
            default: type = "other"
            }
            tracks.append(ProbeResult.Track(type: type, codec: track.formatDescriptions.first.map { "\($0)" }, language: track.languageCode, channels: nil, title: track.extendedLanguageTag, external: false))
        }
    }
    var firstFrame: Double?
    var position = 0.0
    if playable, let video = asset.tracks(withMediaType: .video).first {
        let item = AVPlayerItem(asset: asset)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        item.add(output)
        let player = AVPlayer(playerItem: item)
        let start = Date()
        player.play()
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            let time = output.itemTime(forHostTime: CACurrentMediaTime())
            if output.hasNewPixelBuffer(forItemTime: time) { firstFrame = Date().timeIntervalSince(start); break }
            position = item.currentTime().seconds
        }
        _ = video
        player.pause()
    }
    return ProbeResult(
        engine: "AVFoundation",
        file: path,
        playable: playable,
        duration: duration,
        position: position,
        videoCodec: nil,
        audioCodec: nil,
        audioChannels: nil,
        hwdec: nil,
        tracks: tracks,
        error: errorMessage,
        elapsedToFirstFrame: firstFrame
    )
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write("usage: openfuse-probe <mpv|avplayer|version> <file> [seek]\n".data(using: .utf8)!)
    exit(2)
}
let mode = arguments[1]
switch mode {
case "version":
    let engine = MPVEngine()
    print("mpv client API \(engine.clientAPIversion), mpv-version \(engine.getPropertyString("mpv-version") ?? "?")")
    exit(0)
case "tracks":
    let engine = MPVEngine(headless: true)
    var loaded = false
    engine.onFileLoaded = { loaded = true }
    engine.load(url: URL(fileURLWithPath: arguments[2]), startAt: 0)
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline && !loaded {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    print(engine.getPropertyString("track-list") ?? "[]")
    print("hwdec-current=\(engine.getPropertyString("hwdec-current") ?? "nil") video-codec=\(engine.getPropertyString("video-codec") ?? "nil")")
    engine.command(["quit"])
    exit(0)
case "mpv":
    let seek = arguments.count > 3 ? Double(arguments[3]) : nil
    printJSON(runMPV(path: arguments[2], seek: seek, playSeconds: 3))
case "avplayer":
    printJSON(runAVPlayer(path: arguments[2]))
default:
    FileHandle.standardError.write("unknown mode \(mode)\n".data(using: .utf8)!)
    exit(2)
}
