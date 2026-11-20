import AppKit
import AVFoundation
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
case "tmdb":
    let title = arguments[2]
    let year = arguments.count > 3 ? Int(arguments[3]) : nil
    let kind: LibraryKind = arguments.count > 4 && arguments[4] == "tv" ? .series : .movie
    let key = ProcessInfo.processInfo.environment["OPENFUSE_TMDB_API_KEY"] ?? ""
    let base = URL(string: ProcessInfo.processInfo.environment["OPENFUSE_TMDB_BASE_URL"] ?? "https://api.themoviedb.org/3")!
    let image = URL(string: ProcessInfo.processInfo.environment["OPENFUSE_TMDB_IMAGE_BASE"] ?? "https://image.tmdb.org/t/p/w500")!
    let client = TMDBClient(apiKey: key, baseURL: base, imageBaseURL: image)
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        let match = await client.match(title: title, year: year, kind: kind)
        let candidates = await client.candidates(title: title, year: year, kind: kind)
        var payload: [String: Any] = match.map { item in
            ["id": item.id, "title": item.title, "year": item.year ?? 0,
             "overview": item.overview ?? "", "poster": client.imageURL(path: item.posterPath)?.absoluteString ?? ""]
        } ?? [:]
        payload["candidates"] = candidates.map { item in
            ["id": item.id, "title": item.title, "year": item.year ?? 0]
        }
        let data = try! JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        print(String(data: data, encoding: .utf8)!)
        semaphore.signal()
    }
    semaphore.wait()
    exit(0)
case "authed-asset":
    let url = URL(string: arguments[2])!
    let user = arguments.count > 3 ? arguments[3] : ""
    let password = arguments.count > 4 ? arguments[4] : ""
    let credential = Data("\(user):\(password)".utf8).base64EncodedString()
    let loader = AuthenticatedAssetLoader(
        url: url,
        headers: ["Authorization": "Basic \(credential)"]
    )
    let asset = loader.makeAsset()
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        var payload: [String: Any] = ["url": url.absoluteString]
        do {
            let duration = try await asset.load(.duration)
            payload["duration"] = duration.seconds
            let tracks = try await asset.loadTracks(withMediaType: .video)
            payload["videoTracks"] = tracks.count
            if let track = tracks.first {
                let size = try await track.load(.naturalSize)
                payload["width"] = Int(size.width)
                payload["height"] = Int(size.height)
            }
        } catch {
            payload["error"] = error.localizedDescription
        }
        let data = try! JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        print(String(data: data, encoding: .utf8)!)
        semaphore.signal()
    }
    semaphore.wait()
    exit(0)
case "authed-play":
    let url = URL(string: arguments[2])!
    let user = arguments.count > 3 ? arguments[3] : ""
    let password = arguments.count > 4 ? arguments[4] : ""
    let credential = Data("\(user):\(password)".utf8).base64EncodedString()
    let loader = AuthenticatedAssetLoader(
        url: url,
        headers: ["Authorization": "Basic \(credential)"]
    )
    let asset = loader.makeAsset()
    let item = AVPlayerItem(asset: asset)
    let player = AVPlayer(playerItem: item)
    player.play()
    RunLoop.main.run(until: Date().addingTimeInterval(4))
    let seconds = player.currentTime().seconds
    let payload: [String: Any] = [
        "position": seconds.isFinite ? seconds : 0,
        "status": item.status.rawValue,
        "error": item.error?.localizedDescription ?? "",
    ]
    let data = try! JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    print(String(data: data, encoding: .utf8)!)
    player.pause()
    _ = loader
    exit(seconds > 0.3 ? 0 : 1)
case "jellyfin-remote":
    let base = URL(string: arguments[2])!
    let user = arguments[3]
    let password = arguments[4]
    let itemID = arguments[5]
    let source = JellyfinSource(name: "fixture", baseURL: base, username: user)
    Task { @MainActor in
        var payload: [String: Any] = [:]
        do {
            let session = try await JellyfinClient.authenticate(source: source, password: password)
            var authenticated = source
            authenticated.userID = session.userID
            authenticated.serverID = session.serverID
            let client = JellyfinClient(source: authenticated, token: session.accessToken)
            let info = try await client.playbackInfo(itemID: itemID)
            guard let media = info.mediaSources.first,
                  let stream = client.streamURL(itemID: itemID, mediaSource: media) else {
                throw NSError(domain: "probe", code: 1, userInfo: [NSLocalizedDescriptionKey: "no media source"])
            }
            var components = URLComponents(url: stream, resolvingAgainstBaseURL: false)
            var query = components?.queryItems ?? []
            query.append(URLQueryItem(name: "api_key", value: session.accessToken))
            components?.queryItems = query
            let url = components?.url ?? stream
            let loader = AuthenticatedAssetLoader(
                url: url,
                headers: [
                    "X-Emby-Token": session.accessToken,
                    "Authorization": "MediaBrowser Token=\"\(session.accessToken)\"",
                ]
            )
            let asset = loader.makeAsset()
            let duration = try await asset.load(.duration)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let item = AVPlayerItem(asset: asset)
            let player = AVPlayer(playerItem: item)
            player.play()
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            payload = [
                "duration": duration.seconds,
                "videoTracks": tracks.count,
                "position": player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0,
                "status": item.status.rawValue,
                "error": item.error?.localizedDescription ?? "",
                "url": url.absoluteString,
            ]
            player.pause()
            _ = loader
        } catch {
            payload = ["error": error.localizedDescription]
        }
        let data = try! JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        print(String(data: data, encoding: .utf8)!)
        exit(0)
    }
    RunLoop.main.run(until: Date().addingTimeInterval(12))
    exit(1)
case "jellyfin-hls":
    let base = URL(string: arguments[2])!
    let user = arguments[3]
    let password = arguments[4]
    let itemID = arguments[5]
    let source = JellyfinSource(name: "fixture", baseURL: base, username: user)
    Task { @MainActor in
        var payload: [String: Any] = [:]
        do {
            let session = try await JellyfinClient.authenticate(source: source, password: password)
            var authenticated = source
            authenticated.userID = session.userID
            authenticated.serverID = session.serverID
            let client = JellyfinClient(source: authenticated, token: session.accessToken)
            let info = try await client.playbackInfo(itemID: itemID)
            guard let media = info.mediaSources.first,
                  let url = client.hlsURL(itemID: itemID, mediaSourceID: media.id, token: session.accessToken) else {
                throw NSError(domain: "probe", code: 1, userInfo: [NSLocalizedDescriptionKey: "no hls url"])
            }
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let item = AVPlayerItem(asset: asset)
            let player = AVPlayer(playerItem: item)
            player.play()
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            payload = [
                "duration": duration.seconds,
                "videoTracks": tracks.count,
                "position": player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0,
                "status": item.status.rawValue,
                "error": item.error?.localizedDescription ?? "",
                "url": url.absoluteString,
            ]
            player.pause()
        } catch {
            payload = ["error": error.localizedDescription]
        }
        let data = try! JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        print(String(data: data, encoding: .utf8)!)
        exit(0)
    }
    RunLoop.main.run(until: Date().addingTimeInterval(12))
    exit(1)
case "audio-devices":
    let devices = AudioDevices.outputDevices()
    let payload = devices.map { ["id": $0.id, "name": $0.name, "channels": String($0.outputChannels)] }
    let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
case "trakt-device":
    guard arguments.count >= 4, let base = URL(string: arguments[2]) else {
        print("usage: openfuse-probe trakt-device BASE_URL CLIENT_ID [SECRET]")
        exit(2)
    }
    do {
        let client = TraktClient(config: TraktConfig(
            baseURL: base, clientID: arguments[3], clientSecret: arguments.count > 4 ? arguments[4] : ""
        ))
        let code = try await client.deviceCode()
        let data = try JSONEncoder().encode(code)
        print(String(decoding: data, as: UTF8.self))
    } catch {
        print("error: \(error.localizedDescription)")
        exit(1)
    }
case "trakt-poll":
    guard arguments.count >= 6, let base = URL(string: arguments[2]) else {
        print("usage: openfuse-probe trakt-poll BASE_URL CLIENT_ID SECRET DEVICE_CODE")
        exit(2)
    }
    do {
        let client = TraktClient(config: TraktConfig(
            baseURL: base, clientID: arguments[3], clientSecret: arguments[4]
        ))
        let token = try await client.pollToken(deviceCode: arguments[5])
        let data = try JSONEncoder().encode(token)
        print(String(decoding: data, as: UTF8.self))
    } catch {
        print("error: \(error.localizedDescription)")
        exit(1)
    }
case "smb-list":
    guard arguments.count >= 7,
          let port = Int(arguments[3]) else {
        print("usage: openfuse-probe smb-list SERVER PORT SHARE USER PASSWORD [PATH]")
        exit(2)
    }
    do {
        let source = SMBSource(name: "probe", server: arguments[2], port: port, share: arguments[4], username: arguments[5])
        let client = SMBClient(source: source, password: arguments[6])
        let entries = try client.list(path: arguments.count > 7 ? arguments[7] : nil)
        let rows = entries.map { entry -> [String: Any] in
            ["name": entry.name, "path": entry.path, "dir": entry.isDirectory, "size": entry.size]
        }
        let data = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    } catch {
        print("error: \(error.localizedDescription)")
        exit(1)
    }
case "smb-fetch":
    guard arguments.count >= 8,
          let port = Int(arguments[3]) else {
        print("usage: openfuse-probe smb-fetch SERVER PORT SHARE USER PASSWORD PATH OUT")
        exit(2)
    }
    do {
        let source = SMBSource(name: "probe", server: arguments[2], port: port, share: arguments[4], username: arguments[5])
        let client = SMBClient(source: source, password: arguments[6])
        let data = try client.fetch(path: arguments[7])
        try data.write(to: URL(fileURLWithPath: arguments[8]))
        print("bytes=\(data.count)")
    } catch {
        print("error: \(error.localizedDescription)")
        exit(1)
    }
case "track-list":
    let raw = arguments[2]
    let url = raw.hasPrefix("http") ? URL(string: raw)! : URL(fileURLWithPath: raw)
    let asset = AVURLAsset(url: url)
    Task {
        var payload: [String: Any] = ["url": url.absoluteString]
        do {
            let audio = try await asset.loadTracks(withMediaType: .audio)
            let subtitles = try await asset.loadTracks(withMediaType: .subtitle)
            payload["audioTracks"] = audio.count
            payload["subtitleTracks"] = subtitles.count
            if let group = asset.mediaSelectionGroup(forMediaCharacteristic: .audible) {
                payload["audible"] = group.options.map { option in
                    ["name": option.displayName, "locale": option.locale?.identifier ?? ""]
                }
            }
            if let group = asset.mediaSelectionGroup(forMediaCharacteristic: .legible) {
                payload["legible"] = group.options.map { option in
                    ["name": option.displayName, "locale": option.locale?.identifier ?? ""]
                }
            }
            let duration = try await asset.load(.duration)
            payload["duration"] = duration.seconds
        } catch {
            payload["error"] = error.localizedDescription
        }
        let data = try! JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        print(String(data: data, encoding: .utf8)!)
        exit(0)
    }
    RunLoop.main.run(until: Date().addingTimeInterval(8))
    exit(1)
case "jellyfin":
    let base = arguments[2]
    let user = ProcessInfo.processInfo.environment["OPENFUSE_JELLYFIN_USER"] ?? "test"
    let password = ProcessInfo.processInfo.environment["OPENFUSE_JELLYFIN_PASSWORD"] ?? "test"
    guard let url = URL(string: base) else { exit(2) }
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        do {
            var source = JellyfinSource(name: "fixture", baseURL: url, username: user)
            let session = try await JellyfinClient.authenticate(source: source, password: password)
            source.userID = session.userID
            source.serverID = session.serverID
            let client = JellyfinClient(source: source, token: session.accessToken)
            let views = try await client.views()
            let items = try await client.items(parentID: views.first?.id)
            var report: [String: Any] = [
                "server": base,
                "userID": session.userID,
                "views": views.map { ["id": $0.id, "name": $0.name, "type": $0.itemType ?? "", "collection": $0.collectionType ?? ""] },
                "items": items.map { ["id": $0.id, "name": $0.name, "type": $0.itemType ?? ""] },
            ]
            if let first = items.first(where: { $0.isPlayable }) {
                let info = try await client.playbackInfo(itemID: first.id)
                report["playSession"] = info.playSessionID ?? ""
                report["versions"] = info.mediaSources.map { ["id": $0.id, "name": $0.name, "direct": $0.supportsDirectPlay ?? false] }
                if let media = info.mediaSources.first {
                    report["streamURL"] = client.streamURL(itemID: first.id, mediaSource: media)?.absoluteString ?? ""
                    report["imageURL"] = client.imageURL(itemID: first.id, tag: first.primaryImageTag)?.absoluteString.replacingOccurrences(of: session.accessToken, with: "TOKEN") ?? ""
                }
            }
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            print(String(data: data, encoding: .utf8) ?? "{}")
        } catch {
            FileHandle.standardError.write("jellyfin error: \(error)\n".data(using: .utf8)!)
            exit(1)
        }
        semaphore.signal()
    }
    semaphore.wait()
    exit(0)
case "webdav":
    let base = arguments[2]
    let path = arguments.count > 3 ? arguments[3] : ""
    guard let url = URL(string: base) else { exit(2) }
    let user = ProcessInfo.processInfo.environment["OPENFUSE_WEBDAV_USER"] ?? "test"
    let password = ProcessInfo.processInfo.environment["OPENFUSE_WEBDAV_PASSWORD"] ?? "test"
    let source = WebDAVSource(name: "fixture", baseURL: url, username: user)
    let client = WebDAVClient(source: source, password: password)
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        do {
            let entries = try await client.list(path: path)
            var report: [String: Any] = [
                "base": base,
                "path": path,
                "entries": entries.map { entry -> [String: Any] in
                    ["name": entry.name, "path": entry.path, "dir": entry.isDirectory, "size": entry.size]
                },
            ]
            if let video = entries.first(where: { $0.isPlayableVideo }) {
                let first = try await client.fetch(path: video.path, range: 0..<1024)
                report["rangeStatus"] = first.1.statusCode
                report["rangeLength"] = first.0.count
                report["rangeContentRange"] = first.1.value(forHTTPHeaderField: "Content-Range") ?? ""
                report["magic"] = first.0.prefix(4).map { String(format: "%02x", $0) }.joined()
            }
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            print(String(data: data, encoding: .utf8) ?? "{}")
        } catch {
            FileHandle.standardError.write("webdav error: \(error)\n".data(using: .utf8)!)
            exit(1)
        }
        semaphore.signal()
    }
    semaphore.wait()
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
