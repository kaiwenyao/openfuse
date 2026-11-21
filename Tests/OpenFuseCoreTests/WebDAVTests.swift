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

    func testSubtitleDiscoveryWhenDisplayNamesAreFullPaths() {
        let directory = "电视剧/Fargo (2014)/Season 01"
        let video = RemoteEntry(
            path: "\(directory)/Fargo (2014) - S01E01 - Pilot.mkv",
            name: "\(directory)/Fargo (2014) - S01E01 - Pilot.mkv",
            url: URL(string: "http://host/dav/v.mkv")!,
            isDirectory: false,
            size: 100
        )
        let brother = RemoteEntry(
            path: "\(directory)/Fargo (2014) - S01E02 - The Rooster Prince.mkv",
            name: "\(directory)/Fargo (2014) - S01E02 - The Rooster Prince.mkv",
            url: URL(string: "http://host/dav/b.mkv")!,
            isDirectory: false,
            size: 100
        )
        let subtitle = RemoteEntry(
            path: "\(directory)/Fargo (2014) - S01E01 - Pilot.zh-Hans.ass",
            name: "\(directory)/Fargo (2014) - S01E01 - Pilot.zh-Hans.ass",
            url: URL(string: "http://host/dav/s.ass")!,
            isDirectory: false
        )
        let tracks = WebDAVClient.subtitleTracks(for: video, siblings: [video, brother, subtitle])
        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks.first?.language, "zh-Hans")
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

final class WebDAVStubProtocol: URLProtocol {
    nonisolated(unsafe) static var body = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 207,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/xml"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class WebDAVListFilterTests: XCTestCase {
    func testFullPathDisplayNameStillYieldsOneFolderLabel() async throws {
        // OpenList can put the whole root-relative path into <displayname>.
        // The entry keeps that path/url for navigation and requests, while the
        // card label is the last segment only.
        WebDAVStubProtocol.body = Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <d:multistatus xmlns:d="DAV:">
          <d:response><d:href>/dav/local/</d:href><d:propstat><d:prop>
            <d:displayname>local</d:displayname><d:resourcetype><d:collection/></d:resourcetype>
          </d:prop></d:propstat></d:response>
          <d:response><d:href>/dav/local/kaiwenyao/%E7%94%B5%E8%A7%86%E5%89%A7/Fargo%20(2014)/</d:href><d:propstat><d:prop>
            <d:displayname>local/kaiwenyao/电视剧/Fargo (2014)</d:displayname>
            <d:resourcetype><d:collection/></d:resourcetype>
          </d:prop></d:propstat></d:response>
          <d:response><d:href>/dav/local/kaiwenyao/%E7%94%B5%E8%A7%86%E5%89%A7/Fargo%20(2014)/Season%2001/</d:href><d:propstat><d:prop>
            <d:displayname>Fargo (2014)/Season 01</d:displayname>
            <d:resourcetype><d:collection/></d:resourcetype>
          </d:prop></d:propstat></d:response>
        </d:multistatus>
        """.utf8)
        let source = WebDAVSource(name: "t", baseURL: URL(string: "http://host/dav/")!, username: "u")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WebDAVStubProtocol.self]
        let client = WebDAVClient(
            source: source, password: "p",
            session: URLSession(configuration: configuration)
        )
        let entries = try await client.list(path: "local")
        XCTAssertEqual(entries.count, 2)
        let fargo = try XCTUnwrap(entries.first { $0.folderDisplayName == "Fargo (2014)" })
        let season = try XCTUnwrap(entries.first { $0.folderDisplayName == "Season 01" })
        XCTAssertEqual(fargo.path, "local/kaiwenyao/电视剧/Fargo (2014)")
        XCTAssertEqual(season.path, "local/kaiwenyao/电视剧/Fargo (2014)/Season 01")
        XCTAssertEqual(fargo.name, "local/kaiwenyao/电视剧/Fargo (2014)")
        XCTAssertEqual(season.name, "Fargo (2014)/Season 01")
        XCTAssertTrue(season.url.absoluteString.hasPrefix("http://host/dav/local/kaiwenyao/"))
        XCTAssertTrue(season.url.absoluteString.hasSuffix("Season%2001/"))
    }


    func testDepthOneResponseOmitsTheRequestedDirectory() async throws {
        WebDAVStubProtocol.body = Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <d:multistatus xmlns:d="DAV:">
          <d:response><d:href>/dav/Movies/</d:href><d:propstat><d:prop>
            <d:displayname>Movies</d:displayname><d:resourcetype><d:collection/></d:resourcetype>
          </d:prop></d:propstat></d:response>
          <d:response><d:href>/dav/Movies/Film.mkv</d:href><d:propstat><d:prop>
            <d:displayname>Film.mkv</d:displayname><d:resourcetype/>
            <d:getcontentlength>123</d:getcontentlength>
          </d:prop></d:propstat></d:response>
        </d:multistatus>
        """.utf8)
        let source = WebDAVSource(name: "t", baseURL: URL(string: "http://host/dav/")!, username: "u")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WebDAVStubProtocol.self]
        let client = WebDAVClient(
            source: source, password: "p",
            session: URLSession(configuration: configuration)
        )
        let entries = try await client.list(path: "Movies")
        XCTAssertEqual(entries.map(\.path), ["Movies/Film.mkv"])
        XCTAssertEqual(entries.first?.size, 123)
    }
}
