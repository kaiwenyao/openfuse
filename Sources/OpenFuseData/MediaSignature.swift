import Foundation

/// Cheap container signature check for remote listings. A file whose magic
/// disagrees with its extension is almost certainly corrupt and should not
/// enter the library; unknown extensions are kept.
public enum MediaSignature {
    public static func looksLikeVideo(name: String, header: Data) -> Bool {
        let bytes = [UInt8](header.prefix(64))
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "mkv", "webm":
            return starts(bytes, [0x1A, 0x45, 0xDF, 0xA3])
        case "mp4", "m4v", "mov":
            guard bytes.count >= 8 else { return false }
            let type = String(bytes: bytes[4..<8], encoding: .ascii) ?? ""
            return type == "ftyp" || type == "moov" || type == "mdat"
        case "avi":
            return starts(bytes, Array("RIFF".utf8))
        case "ts", "m2ts":
            guard !bytes.isEmpty else { return false }
            if bytes[0] == 0x47 { return true }
            return bytes.count > 192 && bytes[188] == 0x47
        default:
            return true
        }
    }

    private static func starts(_ bytes: [UInt8], _ magic: [UInt8]) -> Bool {
        bytes.count >= magic.count && Array(bytes.prefix(magic.count)) == magic
    }
}
