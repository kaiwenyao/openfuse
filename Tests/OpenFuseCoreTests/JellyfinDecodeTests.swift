import XCTest
@testable import OpenFuseData

final class JellyfinDecodeTests: XCTestCase {
    func testItemDecodesRatingsPeopleAndBackdrops() throws {
        let json = """
        {
          "Id": "ep1", "Name": "Pilot", "Type": "Episode",
          "SeriesId": "s1", "SeriesName": "Show", "SeasonId": "season1",
          "IndexNumber": 2, "ParentIndexNumber": 1,
          "CommunityRating": 8.2, "CriticRating": 93, "OfficialRating": "TV-MA",
          "Genres": ["犯罪", "剧情"], "PremiereDate": "2014-04-15T00:00:00.0000000Z",
          "ProviderIds": {"Imdb": "tt1234567"},
          "BackdropImageTags": ["bd1"], "SeriesPrimaryImageTag": "sp1",
          "People": [{"Id": "p1", "Name": "Actor", "Role": "Hero", "Type": "Actor", "PrimaryImageTag": "pt"}],
          "UserData": {"PlaybackPositionTicks": 10000000, "Played": false}
        }
        """.data(using: .utf8)!
        let item = try JSONDecoder().decode(JellyfinItem.self, from: json)
        XCTAssertEqual(item.episodeLabel, "S01E02")
        XCTAssertEqual(item.communityRating, 8.2)
        XCTAssertEqual(item.criticRating, 93)
        XCTAssertEqual(item.officialRating, "TV-MA")
        XCTAssertEqual(item.imdbID, "tt1234567")
        XCTAssertEqual(item.backdropImageTag, "bd1")
        XCTAssertEqual(item.primaryImageTag, "sp1")
        XCTAssertEqual(item.people?.first?.role, "Hero")
        XCTAssertEqual(item.releaseLabel, "2014-04-15")
        XCTAssertEqual(item.communityRatingLabel, "社区评分 8.2/10")
        XCTAssertEqual(item.criticRatingLabel, "影评人 93%")
    }

    func testMediaSourceDecodesSizeBitrateAndStreams() throws {
        let json = """
        {
          "Id": "src", "Name": "1080p", "Container": "mkv",
          "Size": 957900000, "Bitrate": 1700000,
          "MediaStreams": [
            {"Type": "Video", "Index": 0, "Codec": "hevc", "Width": 1920, "Height": 1080,
             "BitRate": 1500000, "FrameRate": 23.976023976, "BitDepth": 10,
             "Profile": "Main 10", "VideoRangeType": "HDR10"},
            {"Type": "Audio", "Index": 1, "Codec": "aac", "Channels": 6,
             "ChannelLayout": "5.1", "Language": "jpn", "BitRate": 192000}
          ]
        }
        """.data(using: .utf8)!
        let source = try JSONDecoder().decode(JellyfinMediaSource.self, from: json)
        XCTAssertEqual(source.size, 957_900_000)
        XCTAssertEqual(source.bitrate, 1_700_000)
        XCTAssertEqual(source.mediaStreams?.first?.frameRate ?? 0, 23.976023976, accuracy: 0.000001)
        XCTAssertEqual(source.mediaStreams?.first?.bitDepth, 10)
        let summary = JellyfinMediaSummary(source: source)
        XCTAssertEqual(summary.shortLine, "957.9 MB · HEVC · 1920×1080 · AAC 5.1 · 1.7 Mbps · 23.976 fps")
    }

    func testUserViewUsesReadableFolderLabel() {
        let view = JellyfinItem(id: "v", name: "文件夹", itemType: "UserView")
        XCTAssertEqual(view.subtitle, "文件夹")
    }

    func testPlaybackInfoDecode() throws {
        let json = """
        {"PlaySessionId": "ps", "MediaSources": [{"Id": "a", "Name": "1080p"}]}
        """.data(using: .utf8)!
        let info = try JSONDecoder().decode(JellyfinPlaybackInfo.self, from: json)
        XCTAssertEqual(info.playSessionID, "ps")
        XCTAssertEqual(info.mediaSources.first?.id, "a")
    }
}
