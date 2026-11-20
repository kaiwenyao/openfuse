import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// Bridges AVPlayer's resource loader to an HTTP(S) resource that needs
/// Authorization headers (WebDAV Basic auth, Jellyfin token). AVPlayer only
/// accepts custom URL schemes through a resource loader delegate, so callers
/// keep this object alive while the asset/player is in use.
public final class AuthenticatedAssetLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    public let realURL: URL
    public let headers: [String: String]

    private let session: URLSession
    private let delegateQueue: DispatchQueue
    private let lock = NSLock()
    private var tasks: [ObjectIdentifier: URLSessionDataTask] = [:]

    public init(url: URL, headers: [String: String], timeout: TimeInterval = 30) {
        self.realURL = url
        self.headers = headers
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 4
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
        self.delegateQueue = DispatchQueue(label: "OpenFuse.AuthenticatedAssetLoader")
        super.init()
    }

    public func makeAsset() -> AVURLAsset {
        let asset = AVURLAsset(url: customURL)
        asset.resourceLoader.setDelegate(self, queue: delegateQueue)
        return asset
    }

    public var customURL: URL {
        guard var components = URLComponents(url: realURL, resolvingAgainstBaseURL: false) else {
            return realURL
        }
        components.scheme = "openfuse-auth"
        return components.url ?? realURL
    }

    private func mappedURL(_ requested: URL?) -> URL {
        guard let requested, requested.scheme == "openfuse-auth",
              var components = URLComponents(url: requested, resolvingAgainstBaseURL: false) else {
            return realURL
        }
        components.scheme = realURL.scheme
        components.host = realURL.host
        components.port = realURL.port
        components.user = realURL.user
        components.password = realURL.password
        return components.url ?? realURL
    }

    private func request(method: String, range: String? = nil, url: URL? = nil) -> URLRequest {
        var request = URLRequest(url: mappedURL(url))
        request.httpMethod = method
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let range {
            request.setValue(range, forHTTPHeaderField: "Range")
        }
        return request
    }

    public func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        if let information = loadingRequest.contentInformationRequest {
            loadContentInformation(information, request: loadingRequest)
        } else if let dataRequest = loadingRequest.dataRequest {
            loadData(dataRequest, request: loadingRequest)
        } else {
            loadingRequest.finishLoading()
        }
        return true
    }

    public func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        lock.lock()
        let task = tasks.removeValue(forKey: ObjectIdentifier(loadingRequest))
        lock.unlock()
        task?.cancel()
    }

    private func loadContentInformation(
        _ information: AVAssetResourceLoadingContentInformationRequest,
        request loadingRequest: AVAssetResourceLoadingRequest
    ) {
        let task = session.dataTask(with: request(method: "HEAD", url: loadingRequest.request.url)) { [weak self] _, response, error in
            guard let self else { return }
            defer { self.finish(loadingRequest) }
            if let error {
                loadingRequest.finishLoading(with: error)
                return
            }
            guard let http = response as? HTTPURLResponse else { return }
            if let length = http.value(forHTTPHeaderField: "Content-Length").flatMap(Int64.init) {
                information.contentLength = length
            }
            if let mime = http.value(forHTTPHeaderField: "Content-Type") {
                information.contentType = UTType(mimeType: mime)?.identifier ?? mime
            }
            let acceptsRanges = (http.value(forHTTPHeaderField: "Accept-Ranges") ?? "").contains("bytes")
            information.isByteRangeAccessSupported = acceptsRanges || http.statusCode == 206
            _ = self
        }
        store(task, for: loadingRequest)
        task.resume()
    }

    private func loadData(
        _ dataRequest: AVAssetResourceLoadingDataRequest,
        request loadingRequest: AVAssetResourceLoadingRequest
    ) {
        let offset = max(0, dataRequest.requestedOffset)
        let requested = dataRequest.requestedLength
        let range: String
        if requested > 0 {
            range = "bytes=\(offset)-\(offset + Int64(requested) - 1)"
        } else {
            range = "bytes=\(offset)-"
        }
        let task = session.dataTask(with: request(method: "GET", range: range, url: loadingRequest.request.url)) { [weak self] data, response, error in
            guard let self else { return }
            defer { self.finish(loadingRequest) }
            if let error {
                loadingRequest.finishLoading(with: error)
                return
            }
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let data else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                loadingRequest.finishLoading(with: NSError(
                    domain: "OpenFuse.AuthenticatedAssetLoader",
                    code: status,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP \(status) while loading \(self.realURL.lastPathComponent)"]
                ))
                return
            }
            var payload = data
            if http.statusCode == 200, offset > 0 {
                let drop = Int(min(Int64(data.count), offset))
                payload = data.subdata(in: drop..<data.count)
            }
            if requested > 0 {
                payload = payload.prefix(Int(requested))
            }
            dataRequest.respond(with: payload)
        }
        store(task, for: loadingRequest)
        task.resume()
    }

    private func store(_ task: URLSessionDataTask, for request: AVAssetResourceLoadingRequest) {
        lock.lock()
        tasks[ObjectIdentifier(request)] = task
        lock.unlock()
    }

    private func finish(_ request: AVAssetResourceLoadingRequest) {
        lock.lock()
        tasks.removeValue(forKey: ObjectIdentifier(request))
        lock.unlock()
        if !request.isFinished { request.finishLoading() }
    }
}
