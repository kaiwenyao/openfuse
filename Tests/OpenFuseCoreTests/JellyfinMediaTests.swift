import XCTest
@testable import OpenFuseData

final class JellyfinMediaTests: XCTestCase {
    private func source(size: Int64 = 957_900_000, bitrate: Int64 = 1_700_000) -> JellyfinMediaSource {
        JellyfinMediaSource(
            id: "ms1", name: "1080p", container: "mkv",
            runTimeTicks: 60_000_000_000,
            supportsDirectPlay: true, supportsDirectStream: true,
            directStreamURL: nil, transcodingURL: nil,
            mediaStreams: [
                JellyfinMediaStream(
                    type: "Video", index: 0, codec: "hevc", language: nil,
                    displayTitle: nil, channels: nil, isDefault: true,
                    isForced: nil, isExternal: nil, deliveryURL: nil,
                    width: 1920, height: 1080, profile: "Main 10",
                    videoRange: "HDR", videoRangeType: "HDR10",
                    bitRate: 1_500_000, frameRate: 24_000.0 / 1_001.0,
                    bitDepth: 10, colorSpace: "bt2020nc", colorTransfer: "smpte2084",
                    colorPrimaries: "bt2020", channelLayout: nil, codecTag: nil
                ),
                JellyfinMediaStream(
                    type: "Audio", index: 1, codec: "aac", language: "jpn",
                    displayTitle: nil, channels: 6, isDefault: true,
                    isForced: nil, isExternal: nil, deliveryURL: nil,
                    width: nil, height: nil, profile: nil,
                    videoRange: nil, videoRangeType: nil,
                    bitRate: 192_000, frameRate: nil, bitDepth: nil,
                    colorSpace: nil, colorTransfer: nil, colorPrimaries: nil,
                    channelLayout: "5.1", codecTag: nil
                ),
                JellyfinMediaStream(
                    type: "Subtitle", index: 2, codec: "ass", language: "zh",
                    displayTitle: nil, channels: nil, isDefault: true,
                    isForced: nil, isExternal: false, deliveryURL: nil,
                    width: nil, height: nil, profile: nil,
                    videoRange: nil, videoRangeType: nil,
                    bitRate: nil, frameRate: nil, bitDepth: nil,
                    colorSpace: nil, colorTransfer: nil, colorPrimaries: nil,
                    channelLayout: nil, codecTag: nil
                ),
            ],
            size: size, bitrate: bitrate
        )
    }

    func testShortLineMatchesReferenceFormat() {
        let summary = JellyfinMediaSummary(source: source())
        XCTAssertEqual(summary.shortLine, "957.9 MB · HEVC · 1920×1080 · AAC 5.1 · 1.7 Mbps · 23.976 fps")
    }

    func testFrameRateKeepsThreeDecimals() {
        XCTAssertEqual(JellyfinMediaSummary.formatFrameRate(24_000.0 / 1_001.0), "23.976 fps")
        XCTAssertEqual(JellyfinMediaSummary.formatFrameRate(24), "24 fps")
        XCTAssertEqual(JellyfinMediaSummary.formatFrameRate(25), "25 fps")
    }

    func testDetailsIncludeProfileBitDepthAndSeparateBitrates() {
        let summary = JellyfinMediaSummary(source: source())
        let details = Dictionary(uniqueKeysWithValues: summary.detailLines)
        XCTAssertEqual(details["容器"], "MKV")
        XCTAssertEqual(details["视频编码"], "HEVC Main 10")
        XCTAssertEqual(details["位深"], "10-bit")
        XCTAssertEqual(details["动态范围"], "HDR10")
        XCTAssertEqual(details["总码率"], "1.7 Mbps")
        XCTAssertEqual(details["视频码率"], "1.5 Mbps")
        XCTAssertEqual(details["音轨"], "AAC 5.1 · JPN")
        XCTAssertEqual(details["字幕"], "ASS · ZH")
    }

    func testUnknownFieldsAreOmitted() {
        let empty = JellyfinMediaSource(
            id: "x", name: "x", container: nil, runTimeTicks: nil,
            supportsDirectPlay: nil, supportsDirectStream: nil,
            directStreamURL: nil, transcodingURL: nil, mediaStreams: nil,
            size: nil, bitrate: nil
        )
        let summary = JellyfinMediaSummary(source: empty)
        XCTAssertEqual(summary.shortLine, "")
        XCTAssertTrue(summary.detailLines.isEmpty)
    }

    func testChannelLayoutFallback() {
        XCTAssertEqual(JellyfinMediaSummary.channelLayout(channels: 6, layout: nil), "5.1")
        XCTAssertEqual(JellyfinMediaSummary.channelLayout(channels: 2, layout: nil), "2.0")
        XCTAssertEqual(JellyfinMediaSummary.channelLayout(channels: 6, layout: "5.1(side)"), "5.1(side)")
        XCTAssertNil(JellyfinMediaSummary.channelLayout(channels: nil, layout: nil))
    }

    func testSizeAndBitrateUnits() {
        XCTAssertEqual(JellyfinMediaSummary.formatSize(1_004_000_000), "1.0 GB")
        XCTAssertEqual(JellyfinMediaSummary.formatSize(957_900_000), "957.9 MB")
        XCTAssertEqual(JellyfinMediaSummary.formatBitrate(1_700_000), "1.7 Mbps")
        XCTAssertEqual(JellyfinMediaSummary.formatBitrate(850_000), "850 kbps")
    }
}
