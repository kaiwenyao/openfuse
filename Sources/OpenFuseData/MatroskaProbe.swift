import Foundation

/// Minimal EBML/Matroska header reader. Reads only the first bytes of a file
/// (via WebDAV Range on iOS) and extracts video dimensions plus HDR color
/// metadata without ffprobe.
public struct MatroskaVideoInfo: Equatable, Sendable {
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

public enum MatroskaProbe {
    private static let segment: UInt64 = 0x18538067
    private static let info: UInt64 = 0x1549A966
    private static let tracks: UInt64 = 0x1654AE6B
    private static let trackEntry: UInt64 = 0xAE
    private static let video: UInt64 = 0xE0
    private static let pixelWidth: UInt64 = 0xB0
    private static let pixelHeight: UInt64 = 0xBA
    private static let colour: UInt64 = 0x55B0
    private static let transfer: UInt64 = 0x55BA
    private static let primaries: UInt64 = 0x55BB

    private static let masters: Set<UInt64> = [
        segment, info, tracks, trackEntry, video, colour,
    ]

    public static func parse(_ data: Data) -> MatroskaVideoInfo? {
        var bytes = [UInt8](data)
        guard !bytes.isEmpty else { return nil }
        var info = MatroskaVideoInfo()
        _ = walk(&bytes, 0, bytes.count, depth: 0, info: &info)
        guard info.height != nil || info.width != nil else { return nil }
        if info.transferCharacteristics == 16 {
            info.dynamicRange = info.colourPrimaries == 9 ? "HDR10" : "HDR"
        } else if info.transferCharacteristics == 18 {
            info.dynamicRange = "HLG"
        }
        return info
    }

    @discardableResult
    private static func walk(
        _ bytes: inout [UInt8],
        _ start: Int,
        _ end: Int,
        depth: Int,
        info: inout MatroskaVideoInfo
    ) -> Bool {
        guard depth < 9 else { return false }
        var offset = start
        while offset < end {
            guard let (id, idLength) = readID(bytes, offset, end) else { return false }
            offset += idLength
            guard let (size, sizeLength) = readSize(bytes, offset, end) else { return false }
            offset += sizeLength
            let unknown = size == UInt64.max
            let payloadStart = offset
            let payloadEnd: Int
            if unknown {
                payloadEnd = end
            } else {
                let length = Int(min(size, UInt64(Int.max)))
                if payloadStart + length <= end {
                    payloadEnd = payloadStart + length
                } else if masters.contains(id) {
                    // A 2MB header range truncates Segment/Tracks. Parse what
                    // is available; child sizes are still checked.
                    payloadEnd = end
                } else {
                    return false
                }
            }
            if id == pixelWidth {
                info.width = readUInt(bytes, payloadStart, payloadEnd).map(Int.init)
            } else if id == pixelHeight {
                info.height = readUInt(bytes, payloadStart, payloadEnd).map(Int.init)
            } else if id == transfer {
                info.transferCharacteristics = readUInt(bytes, payloadStart, payloadEnd).map(Int.init)
            } else if id == primaries {
                info.colourPrimaries = readUInt(bytes, payloadStart, payloadEnd).map(Int.init)
            } else if masters.contains(id) {
                if walk(&bytes, payloadStart, payloadEnd, depth: depth + 1, info: &info) {
                    return true
                }
            }
            if payloadEnd <= offset { return false }
            offset = payloadEnd
        }
        return false
    }

    private static func readID(_ bytes: [UInt8], _ offset: Int, _ end: Int) -> (UInt64, Int)? {
        guard offset < end else { return nil }
        let first = bytes[offset]
        var mask: UInt8 = 0x80
        var length = 1
        while length <= 4, first & mask == 0 {
            mask >>= 1
            length += 1
        }
        guard length <= 4, offset + length <= end else { return nil }
        var value: UInt64 = 0
        for index in 0..<length {
            value = (value << 8) | UInt64(bytes[offset + index])
        }
        return (value, length)
    }

    private static func readSize(_ bytes: [UInt8], _ offset: Int, _ end: Int) -> (UInt64, Int)? {
        guard offset < end else { return nil }
        let first = bytes[offset]
        var mask: UInt8 = 0x80
        var length = 1
        while length <= 8, first & mask == 0 {
            mask >>= 1
            length += 1
        }
        guard length <= 8, offset + length <= end else { return nil }
        var value = UInt64(first & (mask &- 1))
        var allOnes = value == UInt64(mask &- 1)
        for index in 1..<length {
            value = (value << 8) | UInt64(bytes[offset + index])
            allOnes = allOnes && bytes[offset + index] == 0xFF
        }
        if allOnes { return (UInt64.max, length) }
        return (value, length)
    }

    private static func readUInt(_ bytes: [UInt8], _ start: Int, _ end: Int) -> UInt64? {
        guard end > start, end - start <= 8 else { return nil }
        var value: UInt64 = 0
        for index in start..<end {
            value = (value << 8) | UInt64(bytes[index])
        }
        return value
    }
}
