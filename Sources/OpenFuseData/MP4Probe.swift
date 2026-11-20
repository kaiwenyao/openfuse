import Foundation

/// Minimal ISO-BMFF reader for video dimensions and `colr`/nclx HDR metadata.
public enum MP4Probe {
    public struct Info: Equatable, Sendable {
        public var width: Int?
        public var height: Int?
        public var transferCharacteristics: Int?
        public var colourPrimaries: Int?
        public var dynamicRange: String?

        public var resolution: String? {
            guard let height, height > 0 else { return nil }
            return height >= 2000 ? "2160p" : "\(height)p"
        }
    }

    public static func parse(_ data: Data) -> Info? {
        let bytes = [UInt8](data)
        var info = Info()
        _ = walk(bytes, 0, bytes.count, info: &info, depth: 0)
        guard info.width != nil || info.height != nil else { return nil }
        if info.transferCharacteristics == 16 {
            info.dynamicRange = info.colourPrimaries == 9 ? "HDR10" : "HDR"
        } else if info.transferCharacteristics == 18 {
            info.dynamicRange = "HLG"
        }
        return info
    }

    private static func walk(
        _ bytes: [UInt8], _ start: Int, _ end: Int,
        info: inout Info, depth: Int
    ) -> Bool {
        guard depth < 8 else { return false }
        var offset = start
        while offset + 8 <= end {
            var size = Int(be32(bytes, offset))
            let type = String(bytes: bytes[(offset + 4)..<(offset + 8)], encoding: .ascii) ?? ""
            var header = 8
            if size == 1 {
                guard offset + 16 <= end else { return false }
                let wide = be64(bytes, offset + 8)
                guard wide <= UInt64(Int.max) else { return false }
                size = Int(wide)
                header = 16
            } else if size == 0 {
                size = end - offset
            }
            guard size >= header, offset + size <= end else { return false }
            let payloadStart = offset + header
            let payloadEnd = offset + size
            switch type {
            case "moov", "trak", "mdia", "minf", "stbl", "stsd", "avc1", "hvc1", "hev1", "encv", "mp4v":
                _ = walk(bytes, payloadStart, payloadEnd, info: &info, depth: depth + 1)
            case "tkhd":
                readTrackHeader(bytes, payloadStart, payloadEnd, info: &info)
            case "colr":
                readColour(bytes, payloadStart, payloadEnd, info: &info)
            default:
                break
            }
            offset = payloadEnd
        }
        return true
    }

    private static func readTrackHeader(_ bytes: [UInt8], _ start: Int, _ end: Int, info: inout Info) {
        guard start + 4 <= end else { return }
        let version = bytes[start]
        let base = version == 1 ? start + 88 : start + 76
        guard base + 8 <= end else { return }
        let width = Int(be32(bytes, base)) >> 16
        let height = Int(be32(bytes, base + 4)) >> 16
        guard width > 0, height > 0 else { return }
        if height > (info.height ?? 0) {
            info.width = width
            info.height = height
        }
    }

    private static func readColour(_ bytes: [UInt8], _ start: Int, _ end: Int, info: inout Info) {
        guard start + 4 <= end else { return }
        let kind = String(bytes: bytes[start..<(start + 4)], encoding: .ascii) ?? ""
        guard kind == "nclx", start + 10 <= end else { return }
        info.colourPrimaries = Int(be16(bytes, start + 4))
        info.transferCharacteristics = Int(be16(bytes, start + 6))
        _ = be16(bytes, start + 8) // matrix
    }

    private static func be16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }

    private static func be32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24) | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8) | UInt32(bytes[offset + 3])
    }

    private static func be64(_ bytes: [UInt8], _ offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 { value = (value << 8) | UInt64(bytes[offset + index]) }
        return value
    }
}
