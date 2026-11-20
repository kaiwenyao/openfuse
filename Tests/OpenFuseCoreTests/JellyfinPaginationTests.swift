import XCTest
@testable import OpenFuseCore
@testable import OpenFuseData

/// URLProtocol stub used to exercise real JellyfinClient pagination without a
/// server. Every response is ordinary JSON, exactly what the client decodes.
final class JellyfinStubProtocol: URLProtocol {
    struct StubError: Error {}
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
    nonisolated(unsafe) static var requestLog: [URL] = []
    private static let lock = NSLock()

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        handler = nil
        requestLog = []
    }

    static func log(_ url: URL) {
        lock.lock(); defer { lock.unlock() }
        requestLog.append(url)
    }

    static var requests: [URL] {
        lock.lock(); defer { lock.unlock() }
        return requestLog
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.log(request.url!)
        do {
            guard let handler = Self.handler else { throw StubError() }
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status,
                httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

final class JellyfinPaginationTests: XCTestCase {
    private let source = JellyfinSource(
        name: "stub", baseURL: URL(string: "http://127.0.0.1:8096")!,
        username: "test", userID: "user-1"
    )

    override func setUp() {
        super.setUp()
        JellyfinStubProtocol.reset()
    }

    override func tearDown() {
        JellyfinStubProtocol.reset()
        super.tearDown()
    }

    private func makeClient() -> JellyfinClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [JellyfinStubProtocol.self]
        return JellyfinClient(
            source: source,
            token: "TOKEN",
            session: URLSession(configuration: configuration)
        )
    }

    private func itemsJSON(
        start: Int, limit: Int, total: Int,
        type: String = "Episode", prefix: String = "ep"
    ) -> Data {
        let end = min(start + limit, total)
        let items = (start..<end).map { index in
            """
            {"Id":"\(prefix)-\(index)","Name":"条目 \(index)","Type":"\(type)",
             "SeriesId":"series-1","SeriesName":"示例剧","IndexNumber":\(index),
             "ParentIndexNumber":1,"RunTimeTicks":600000000}
            """
        }
        let json = """
        {"Items":[\(items.joined(separator: ","))],"TotalRecordCount":\(total)}
        """
        return Data(json.utf8)
    }

    private func total(from request: URLRequest) -> Int? {
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "TotalRecordCount" })?.value.flatMap(Int.init)
    }

    func testDirectChildrenPaginationReturns501stItem() async throws {
        JellyfinStubProtocol.handler = { [self] request in
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            let start = Int(components.queryItems?.first { $0.name == "StartIndex" }?.value ?? "0") ?? 0
            let limit = Int(components.queryItems?.first { $0.name == "Limit" }?.value ?? "200") ?? 200
            return (200, itemsJSON(start: start, limit: limit, total: 501))
        }
        let items = try await makeClient().items(parentID: "lib-1")
        XCTAssertEqual(items.count, 501)
        XCTAssertEqual(items.last?.id, "ep-500")
        XCTAssertGreaterThanOrEqual(JellyfinStubProtocol.requests.count, 3)
        let starts = JellyfinStubProtocol.requests.compactMap { url -> Int? in
            URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "StartIndex" }?.value.flatMap(Int.init)
        }
        XCTAssertEqual(starts, [0, 200, 400])
    }

    func testRecursiveLibraryPaginationReturns5001stItem() async throws {
        JellyfinStubProtocol.handler = { [self] request in
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            let start = Int(components.queryItems?.first { $0.name == "StartIndex" }?.value ?? "0") ?? 0
            let limit = Int(components.queryItems?.first { $0.name == "Limit" }?.value ?? "200") ?? 200
            return (200, itemsJSON(start: start, limit: limit, total: 5001))
        }
        let items = try await makeClient().libraryItems(parentID: "lib-1")
        XCTAssertEqual(items.count, 5001)
        XCTAssertEqual(items.last?.id, "ep-5000")
    }

    func testMiddlePageFailureKeepsPreviousIndexAndRetryCompletes() async throws {
        JellyfinStubProtocol.handler = { [self] request in
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            let path = components.path
            if path.hasSuffix("/Views") {
                let data = Data("""
                {"Items":[{"Id":"lib-1","Name":"电影","Type":"CollectionFolder","CollectionType":"movies"}],"TotalRecordCount":1}
                """.utf8)
                return (200, data)
            }
            let start = Int(components.queryItems?.first { $0.name == "StartIndex" }?.value ?? "0") ?? 0
            if start == 200 { return (500, Data("{}".utf8)) }
            return (200, itemsJSON(start: start, limit: 200, total: 501))
        }
        let result = try await LibraryScanner.scanJellyfin(
            source: source, client: makeClient(), token: ScanCancellationToken()
        )
        XCTAssertTrue(result.hasTransientFailure)
        XCTAssertTrue(result.library.works.isEmpty)
        XCTAssertFalse(result.hasTransientFailure == false)
        XCTAssertEqual(result.transientFailures.first?.libraryName, "电影")

        // Retry with the failing page fixed: the complete 501-item library
        // replaces the old one.
        JellyfinStubProtocol.handler = { [self] request in
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            if components.path.hasSuffix("/Views") {
                let data = Data("""
                {"Items":[{"Id":"lib-1","Name":"电影","Type":"CollectionFolder","CollectionType":"movies"}],"TotalRecordCount":1}
                """.utf8)
                return (200, data)
            }
            let start = Int(components.queryItems?.first { $0.name == "StartIndex" }?.value ?? "0") ?? 0
            return (200, itemsJSON(start: start, limit: 200, total: 501, type: "Movie", prefix: "movie"))
        }
        let retried = try await LibraryScanner.scanJellyfin(
            source: source, client: makeClient(), token: ScanCancellationToken()
        )
        XCTAssertFalse(retried.hasTransientFailure)
        XCTAssertEqual(retried.library.works.count, 501)
        XCTAssertEqual(retried.library.works.last?.serverID, "movie-500")
    }

    func testRevokedLibraryIsRemovedWithoutBeingTreatedAsTransient() async throws {
        JellyfinStubProtocol.handler = { request in
            let path = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.path
            if path.hasSuffix("/Views") {
                let data = Data("""
                {"Items":[{"Id":"lib-1","Name":"电影","Type":"CollectionFolder","CollectionType":"movies"}],"TotalRecordCount":1}
                """.utf8)
                return (200, data)
            }
            return (401, Data("{}".utf8))
        }
        let result = try await LibraryScanner.scanJellyfin(
            source: source, client: makeClient(), token: ScanCancellationToken()
        )
        XCTAssertFalse(result.hasTransientFailure)
        XCTAssertEqual(result.revokedLibraryNames, ["电影"])
        XCTAssertTrue(result.library.works.isEmpty)
    }

    func testCancellationStopsPaginationMidway() async throws {
        let token = ScanCancellationToken()
        JellyfinStubProtocol.handler = { [self] request in
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            if components.path.hasSuffix("/Views") {
                let data = Data("""
                {"Items":[{"Id":"lib-1","Name":"电影","Type":"CollectionFolder","CollectionType":"movies"}],"TotalRecordCount":1}
                """.utf8)
                return (200, data)
            }
            let start = Int(components.queryItems?.first { $0.name == "StartIndex" }?.value ?? "0") ?? 0
            if start >= 200 { token.cancel() }
            return (200, itemsJSON(start: start, limit: 200, total: 5001))
        }
        do {
            _ = try await LibraryScanner.scanJellyfin(source: source, client: makeClient(), token: token)
            XCTFail("expected cancellation")
        } catch LibraryScanError.cancelled {
            // expected
        }
    }

    func testResumeMergePrefersLatestActionNotFarthestPosition() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let local = PlaybackRecord(
            mediaPath: "jellyfin://s/ep", duration: 3000, position: 2400,
            lastPlayedAt: now, isFinished: false
        )
        // Another device rewatched from 5:00 after this Mac stopped at 40:00.
        XCTAssertEqual(
            ResumeMerge.startPosition(local: local, serverPosition: 300, serverLastPlayedAt: now.addingTimeInterval(60)),
            300,
            accuracy: 0.001
        )
        // A later local play still wins.
        XCTAssertEqual(
            ResumeMerge.startPosition(local: local, serverPosition: 300, serverLastPlayedAt: now.addingTimeInterval(-60)),
            2400,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ResumeMerge.startPosition(local: nil, serverPosition: 42, serverLastPlayedAt: nil),
            42,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ResumeMerge.startPosition(local: nil, serverPosition: 0, serverLastPlayedAt: now),
            0,
            accuracy: 0.001
        )
    }

    func testMergedRemotePositionDoesNotOverrideNewerLocalPlay() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("openfuse-merge-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try PlaybackStore(directory: directory)
        let key = MediaFingerprint(path: "jellyfin://s/ep", fileSize: 10, modifiedAt: nil)
        let later = Date()
        store.update(fingerprint: key, duration: 3000, position: 2400, finished: false)
        _ = store.mergeRemotePosition(
            fingerprint: key, position: 300, duration: 3000,
            lastPlayedAt: later.addingTimeInterval(-500), finished: false
        )
        XCTAssertEqual(store.record(forPath: key.resumeKey)?.position ?? 0, 2400, accuracy: 0.001)
        _ = store.mergeRemotePosition(
            fingerprint: key, position: 300, duration: 3000,
            lastPlayedAt: later.addingTimeInterval(500), finished: false
        )
        XCTAssertEqual(store.record(forPath: key.resumeKey)?.position ?? 0, 300, accuracy: 0.001)
    }
}

final class JellyfinSubtitleURLTests: XCTestCase {
    func testSidecarWithoutDeliveryURLGetsAbsoluteStreamURL() throws {
        let source = JellyfinSource(
            name: "t", baseURL: URL(string: "http://127.0.0.1:8096")!,
            username: "u", userID: "user-1"
        )
        let stream = JellyfinMediaStream(
            type: "Subtitle", index: 2, codec: "ass", language: "zh-hant",
            displayTitle: "Chinese (Traditional) - ASS - External", channels: nil,
            isDefault: nil, isForced: false, isExternal: true, deliveryURL: nil,
            width: nil, height: nil, profile: nil, videoRange: nil, videoRangeType: nil
        )
        let media = JellyfinMediaSource(
            id: "ms-1", name: "1080p", container: "mkv", runTimeTicks: 600_000_000,
            supportsDirectPlay: true, supportsDirectStream: true,
            directStreamURL: nil, transcodingURL: nil, mediaStreams: [stream]
        )
        let tracks = MediaItem.serverSubtitles(
            source: source, mediaSource: media, itemID: "item-1", token: "TOKEN"
        )
        let track = try XCTUnwrap(tracks.only)
        XCTAssertEqual(track.language, "zh-Hant")
        XCTAssertEqual(track.format, .ass)
        XCTAssertEqual(
            track.url?.absoluteString,
            "http://127.0.0.1:8096/Videos/item-1/ms-1/Subtitles/2/Stream.ass?api_key=TOKEN"
        )
        XCTAssertTrue(track.displayName.contains("繁體"))
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
