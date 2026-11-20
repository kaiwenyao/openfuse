import XCTest
@testable import OpenFuseCore
@testable import OpenFuseData

final class WebDAVTests: XCTestCase {
    func testParsesPercentEncodedMultistatus() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <d:multistatus xmlns:d="DAV:">
          <d:response>
            <d:href>/dav/</d:href>
            <d:propstat><d:prop><d:displayname>root</d:displayname><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat>
          </d:response>
          <d:response>
            <d:href>/dav/Movies/%E7%94%B5%E5%BD%B1/</d:href>
            <d:propstat><d:prop><d:displayname>电影</d:displayname><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat>
          </d:response>
          <d:response>
            <d:href>/dav/Movies/%E7%94%B5%E5%BD%B1/OpenFuse%20Fixture.mkv</d:href>
            <d:propstat><d:prop>
              <d:displayname>OpenFuse Fixture.mkv</d:displayname>
              <d:resourcetype/>
              <d:getcontentlength>17654819</d:getcontentlength>
              <d:getcontenttype>video/x-matroska</d:getcontenttype>
              <d:getlastmodified>Thu, 19 Nov 2026 22:00:00 GMT</d:getlastmodified>
            </d:prop></d:propstat>
          </d:response>
        </d:multistatus>
        """.data(using: .utf8)!
        let parser = WebDAVMultistatusParser()
        XCTAssertTrue(parser.parse(xml))
        XCTAssertEqual(parser.responses.count, 3)
        XCTAssertEqual(parser.responses[1].displayName, "电影")
        XCTAssertTrue(parser.responses[1].isCollection)
        XCTAssertEqual(parser.responses[2].contentLength, 17654819)
        XCTAssertFalse(parser.responses[2].isCollection)
        XCTAssertNotNil(parser.responses[2].modifiedAt)
    }

    func testPathDecoding() {
        XCTAssertEqual(WebDAVClient.decodePath("/dav/Movies/%E7%94%B5%E5%BD%B1/"), "/dav/Movies/电影/")
        XCTAssertEqual(WebDAVClient.decodePath("https://host/dav/a%20b.mkv"), "/dav/a b.mkv")
        XCTAssertEqual(WebDAVClient.decodePath("/dav/100%25/"), "/dav/100%/")
    }

    func testURLJoiningPreservesUnicodeAndPercent() {
        let source = WebDAVSource(name: "t", baseURL: URL(string: "http://127.0.0.1:8099/dav")!, username: "test")
        let client = WebDAVClient(source: source, password: "test")
        XCTAssertEqual(client.url(for: "电影/片 名.mkv").absoluteString,
                       "http://127.0.0.1:8099/dav/%E7%94%B5%E5%BD%B1/%E7%89%87%20%E5%90%8D.mkv")
        XCTAssertEqual(client.url(for: "100% 测试", isDirectory: true).absoluteString,
                       "http://127.0.0.1:8099/dav/100%25%20%E6%B5%8B%E8%AF%95/")
    }

    func testRemoteSubtitleDiscovery() {
        let video = RemoteEntry(
            path: "Shows/示例剧/Season 01/示例剧.S01E01.mkv",
            name: "示例剧.S01E01.mkv",
            url: URL(string: "http://host/dav/Shows/%E7%A4%BA%E4%BE%8B%E5%89%A7/Season%2001/%E7%A4%BA%E4%BE%8B%E5%89%A7.S01E01.mkv")!,
            isDirectory: false,
            size: 100
        )
        let siblings = [
            video,
            RemoteEntry(path: "Shows/示例剧/Season 01/示例剧.S01E01.zh-Hans.ass", name: "示例剧.S01E01.zh-Hans.ass", url: URL(string: "http://host/a.ass")!, isDirectory: false),
            RemoteEntry(path: "Shows/示例剧/Season 01/示例剧.S01E01.zh-Hant.ass", name: "示例剧.S01E01.zh-Hant.ass", url: URL(string: "http://host/b.ass")!, isDirectory: false),
            RemoteEntry(path: "Shows/示例剧/Season 01/其他剧.S01E01.zh-Hans.ass", name: "其他剧.S01E01.zh-Hans.ass", url: URL(string: "http://host/c.ass")!, isDirectory: false),
        ]
        let tracks = WebDAVClient.subtitleTracks(for: video, siblings: siblings)
        XCTAssertEqual(tracks.map { $0.language ?? "" }, ["zh-Hans", "zh-Hant"])
        XCTAssertEqual(tracks[0].source, .external)
        XCTAssertEqual(tracks[0].url?.absoluteString, "http://host/a.ass")
    }
}
