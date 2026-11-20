import Darwin
import Foundation
import OpenFuseCore

/// Loopback HTTP/1.1 server exposing one SMB file with Range support.
/// Network.framework's NWListener fails with EINVAL in this environment, so
/// the listener uses a plain BSD socket; connections are served concurrently
/// (bounded) and read SMB chunks through libsmb2 on demand.
final class SMBStreamServer: @unchecked Sendable {
    let url: URL
    private let client: SMBClient
    private let path: String
    private let size: Int64
    private var listenFD: Int32
    private let acceptQueue = DispatchQueue(label: "com.openfuse.smb-stream.accept", qos: .userInitiated)
    private let connectionQueue = DispatchQueue(
        label: "com.openfuse.smb-stream.connection",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private let connectionLimit = DispatchSemaphore(value: 4)
    private let lock = NSLock()
    private var running = true
    private(set) var requestCount = 0

    private init(fd: Int32, client: SMBClient, path: String, size: Int64, port: UInt16) {
        self.listenFD = fd
        self.client = client
        self.path = path
        self.size = size
        self.url = URL(string: "http://127.0.0.1:\(port)/stream")!
        acceptQueue.async { [weak self] in self?.acceptLoop() }
    }

    static func start(client: SMBClient, path: String, size: Int64) async throws -> SMBStreamServer {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SMBError.operation("socket failed") }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0, listen(fd, 16) == 0 else {
            close(fd)
            throw SMBError.operation("SMB stream bind failed")
        }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard nameResult == 0 else {
            close(fd)
            throw SMBError.operation("SMB stream getsockname failed")
        }
        return SMBStreamServer(
            fd: fd, client: client, path: path, size: size, port: address.sin_port.bigEndian
        )
    }

    func stop() {
        lock.lock()
        guard running else { lock.unlock(); return }
        running = false
        let fd = listenFD
        listenFD = -1
        lock.unlock()
        if fd >= 0 { close(fd) }
    }

    deinit { stop() }

    private var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return running
    }

    private func acceptLoop() {
        while isRunning {
            var address = sockaddr()
            var length = socklen_t(MemoryLayout<sockaddr>.size)
            let fd = accept(listenFD, &address, &length)
            if fd < 0 {
                if !isRunning { break }
                if errno == EINTR { continue }
                usleep(20_000)
                continue
            }
            var noSigPipe: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
            guard connectionLimit.wait(timeout: .now()) == .success else {
                close(fd)
                continue
            }
            connectionQueue.async { [weak self] in
                defer { self?.connectionLimit.signal() }
                self?.handle(fd)
            }
        }
    }

    private func handle(_ fd: Int32) {
        defer { shutdown(fd, SHUT_RDWR); close(fd) }
        var buffer = Data()
        while buffer.range(of: Data("\r\n\r\n".utf8)) == nil {
            var chunk = [UInt8](repeating: 0, count: 8192)
            let count = recv(fd, &chunk, chunk.count, 0)
            if count <= 0 { return }
            buffer.append(chunk, count: Int(count))
            if buffer.count > 64 * 1024 { return }
        }
        guard let headerRange = buffer.range(of: Data("\r\n\r\n".utf8)) else { return }
        let header = String(decoding: buffer[..<headerRange.lowerBound], as: UTF8.self)
        respond(fd, header: header)
    }

    private func respond(_ fd: Int32, header: String) {
        lock.lock(); requestCount += 1; lock.unlock()
        let lines = header.components(separatedBy: "\r\n")
        let request = lines.first?.split(separator: " ") ?? []
        let method = request.first.map(String.init) ?? "GET"
        var start: Int64 = 0
        var end = size - 1
        var status = "200 OK"
        for line in lines.dropFirst() where line.lowercased().hasPrefix("range:") {
            let value = line.split(separator: ":", maxSplits: 1).last?
                .trimmingCharacters(in: .whitespaces) ?? ""
            guard value.hasPrefix("bytes=") else { continue }
            let spec = value.dropFirst("bytes=".count).split(separator: "-", omittingEmptySubsequences: false)
            guard spec.count == 2 else { continue }
            if spec[0].isEmpty, let suffix = Int64(spec[1]) {
                start = max(0, size - suffix)
            } else if let value = Int64(spec[0]) {
                start = value
                if !spec[1].isEmpty, let value = Int64(spec[1]) { end = value }
            }
            status = "206 Partial Content"
        }
        start = max(0, min(start, max(0, size - 1)))
        end = max(start, min(end, size - 1))
        let length = max(0, end - start + 1)
        var headers = "HTTP/1.1 \(status)\r\n"
        headers += "Content-Type: video/x-matroska\r\n"
        headers += "Accept-Ranges: bytes\r\n"
        headers += "Content-Length: \(length)\r\n"
        headers += "Connection: close\r\n"
        if status.hasPrefix("206") {
            headers += "Content-Range: bytes \(start)-\(end)/\(size)\r\n"
        }
        headers += "\r\n"
        guard sendAll(fd, Data(headers.utf8)), method != "HEAD" else { return }
        var offset = start
        var remaining = length
        while remaining > 0 {
            let count = Int(min(64 * 1024, remaining))
            var chunk: Data?
            do {
                chunk = try client.read(path: path, offset: offset, length: count)
            } catch {
                client.reconnect()
                chunk = try? client.read(path: path, offset: offset, length: count)
            }
            guard let data = chunk, !data.isEmpty else {
                return
            }
            guard sendAll(fd, data) else { return }
            offset += Int64(data.count)
            remaining -= Int64(data.count)
        }
    }

    private func sendAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return true }
            var sent = 0
            while sent < raw.count {
                let count = send(fd, base.advanced(by: sent), raw.count - sent, 0)
                if count <= 0 { return false }
                sent += count
            }
            return true
        }
    }
}
