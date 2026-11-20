import XCTest
@testable import OpenFuseCore
@testable import OpenFuseData

final class JellyfinTests: XCTestCase {
    func testDecodesItemAndPlaybackInfo() throws {
        let itemJSON = """
        {"Id":"ep-1","Name":"第 1 集","Type":"Episode","SeriesId":"series-1","SeriesName":"示例剧",
         "IndexNumber":1,"ParentIndexNumber":1,"RunTimeTicks":600000000,"ProductionYear":2026,
         "ImageTags":{"Primary":"tag1"},
         "UserData":{"PlaybackPositionTicks":125000000,"Played":false,"PlayCount":2}}
        """.data(using: .utf8)!
        let item = try JSONDecoder().decode(JellyfinItem.self, from: itemJSON)
        XCTAssertEqual(item.id, "ep-1")
        XCTAssertEqual(item.episodeLabel, "S01E01")
        XCTAssertEqual(item.primaryImageTag, "tag1")
        XCTAssertEqual(JellyfinTicks.seconds(item.userData?.playbackPositionTicks), 12.5)

        let infoJSON = """
        {"PlaySessionId":"play-1","MediaSources":[
          {"Id":"ms1","Name":"1080p HEVC 5.1","Container":"mkv","RunTimeTicks":600000000,
           "SupportsDirectPlay":true,"SupportsDirectStream":true,
           "DirectStreamUrl":"/Videos/ep-1/stream?Static=true&MediaSourceId=ms1",
           "MediaStreams":[{"Type":"Audio","Index":1,"Codec":"eac3","Language":"chi","Channels":6,
                            "DisplayTitle":"E-AC-3 5.1","IsDefault":true}]}
        ]}
        """.data(using: .utf8)!
        let info = try JSONDecoder().decode(JellyfinPlaybackInfo.self, from: infoJSON)
        XCTAssertEqual(info.playSessionID, "play-1")
        XCTAssertEqual(info.mediaSources.count, 1)
        XCTAssertEqual(info.mediaSources[0].mediaStreams?.first?.channels, 6)
    }

    func testStreamAndImageURLs() {
        let source = JellyfinSource(
            name: "fixture",
            baseURL: URL(string: "http://127.0.0.1:8096")!,
            username: "test",
            userID: "user-1"
        )
        let client = JellyfinClient(source: source, token: "TOKEN")
        let media = JellyfinMediaSource(
            id: "ms1", name: "1080p", container: "mkv", runTimeTicks: 600_000_000,
            supportsDirectPlay: true, supportsDirectStream: true,
            directStreamURL: "/Videos/ep-1/stream?Static=true&MediaSourceId=ms1",
            transcodingURL: nil, mediaStreams: []
        )
        XCTAssertEqual(
            client.streamURL(itemID: "ep-1", mediaSource: media)?.absoluteString,
            "http://127.0.0.1:8096/Videos/ep-1/stream?Static=true&MediaSourceId=ms1"
        )
        let image = client.imageURL(itemID: "ep-1", tag: "tag1")!.absoluteString
        XCTAssertTrue(image.hasPrefix("http://127.0.0.1:8096/Items/ep-1/Images/Primary?"))
        XCTAssertTrue(image.contains("api_key=TOKEN"))
        XCTAssertTrue(image.contains("maxWidth=480"))
    }

    func testServerProgressTicks() {
        XCTAssertEqual(JellyfinTicks.from(seconds: 41.042), 410_420_000)
        XCTAssertEqual(JellyfinTicks.seconds(410_420_000), 41.042, accuracy: 0.0001)
        XCTAssertEqual(JellyfinTicks.seconds(nil), 0)
    }

    func testMediaItemJellyfinIdentityAndHeaders() throws {
        let source = JellyfinSource(
            name: "Home", baseURL: URL(string: "http://host:8096")!,
            username: "test", userID: "user-1", serverID: "srv"
        )
        let item = try JSONDecoder().decode(JellyfinItem.self, from: """
        {"Id":"ep-1","Name":"第 1 集","Type":"Episode","RunTimeTicks":600000000,
         "UserData":{"PlaybackPositionTicks":250000000}}
        """.data(using: .utf8)!)
        let media = JellyfinMediaSource(
            id: "ms1", name: "1080p", container: "mkv", runTimeTicks: 600000_000,
            supportsDirectPlay: true, supportsDirectStream: true,
            directStreamURL: "/Videos/ep-1/stream?MediaSourceId=ms1",
            transcodingURL: nil, mediaStreams: []
        )
        let info = JellyfinPlaybackInfo(playSessionID: "play", mediaSources: [media])
        let mediaItem = try XCTUnwrap(MediaItem.jellyfin(
            source: source, item: item, mediaSource: media, playbackInfo: info,
            token: "TOKEN", subtitles: []
        ))
        XCTAssertEqual(mediaItem.sourceKind, "jellyfin")
        XCTAssertEqual(mediaItem.fingerprint.resumeKey, "jellyfin://\(source.id)/ep-1/ms1")
        XCTAssertEqual(mediaItem.jellyfinContext?.startPosition, 25)
        XCTAssertEqual(mediaItem.httpHeaders, ["X-Emby-Token: TOKEN"])
        XCTAssertEqual(mediaItem.remotePath, "ep-1|ms1")
    }
}
