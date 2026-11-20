import CryptoKit
import Foundation

/// Stable content identity used to dedupe versions across local/WebDAV/SMB.
/// Uses size plus the first and last 64KiB; this is an identity hint, not a
/// cryptographic whole-file hash.
public enum ContentFingerprint {
    public static let chunkSize = 65_536

    public static func key(size: Int64, first: Data, last: Data?) -> String? {
        guard size > 0, !first.isEmpty else { return nil }
        var hasher = SHA256()
        withUnsafeBytes(of: UInt64(size).littleEndian) { hasher.update(bufferPointer: $0) }
        hasher.update(data: first)
        if let last, !last.isEmpty { hasher.update(data: last) }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return String(digest.prefix(32))
    }

    public static func localKey(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size: UInt64 = (try? handle.seekToEnd()) ?? 0
        guard size > 0 else { return nil }
        try? handle.seek(toOffset: 0)
        let first = (try? handle.read(upToCount: Int(min(UInt64(chunkSize), size)))) ?? Data()
        var last: Data?
        if size > UInt64(chunkSize) {
            try? handle.seek(toOffset: size - UInt64(chunkSize))
            last = try? handle.read(upToCount: chunkSize)
        }
        return key(size: Int64(size), first: first, last: last)
    }
}
