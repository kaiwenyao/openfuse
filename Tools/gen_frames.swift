// Generates raw BGRA frames on stdout for the OpenFuse test pattern.
// Build:  swiftc -O Tools/gen_frames.swift -o build/gen_frames
// Usage:  build/gen_frames 60 24 1920 1080 | ffmpeg -f rawvideo -pix_fmt bgra ...
//
// The pattern deliberately contains:
//   * an exact HH:MM:SS:FF timecode and a millisecond clock,
//   * a full-frame white flash on every whole second (audio sync marker),
//   * a moving scan line and progress bar (seek accuracy),
//   * a 5.1 speaker diagram (channel identification),
//   * subtitle-safe bottom third.

import AppKit
import CoreGraphics
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

let args = CommandLine.arguments
guard args.count >= 5,
      let seconds = Double(args[1]),
      let fps = Double(args[2]),
      let width = Int(args[3]),
      let height = Int(args[4])
else {
    fail("usage: gen_frames <seconds> <fps> <width> <height>")
}

let totalFrames = Int((seconds * fps).rounded())
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
let bytesPerRow = width * 4
let byteCount = bytesPerRow * height
let W = CGFloat(width)
let H = CGFloat(height)

let storage = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 64)
storage.initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)
let stdout = FileHandle.standardOutput

func makeColor(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [r, g, b, a])!
}

let background = makeColor(0.043, 0.051, 0.067)
let panel = makeColor(0.086, 0.098, 0.125)
let accent = makeColor(0.36, 0.78, 0.98)
let warm = makeColor(0.98, 0.72, 0.25)
let textColor = makeColor(0.93, 0.95, 0.98)
let muted = makeColor(0.55, 0.60, 0.68)

let scenePalette: [(CGFloat, CGFloat, CGFloat)] = [
    (0.10, 0.16, 0.26),
    (0.22, 0.12, 0.20),
    (0.10, 0.22, 0.18),
    (0.24, 0.20, 0.10),
    (0.16, 0.14, 0.26),
    (0.24, 0.10, 0.12),
]

let context = CGContext(
    data: storage,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: bytesPerRow,
    space: colorSpace,
    bitmapInfo: bitmapInfo
)!

NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

func drawText(_ string: String, at point: CGPoint, size: CGFloat, weight: NSFont.Weight = .regular,
              color: CGColor, monospaced: Bool = false, alignment: NSTextAlignment = .left) {
    let font = monospaced
        ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        : NSFont.systemFont(ofSize: size, weight: weight)
    let style = NSMutableParagraphStyle()
    style.alignment = alignment
    style.lineBreakMode = .byClipping
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(cgColor: color) ?? .white,
        .paragraphStyle: style,
    ]
    let attributed = NSAttributedString(string: string, attributes: attributes)
    let line = CTLineCreateWithAttributedString(attributed)
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    var x = point.x
    if alignment == .center { x -= bounds.width / 2 }
    if alignment == .right { x -= bounds.width }
    context.textPosition = CGPoint(x: x, y: point.y)
    CTLineDraw(line, context)
}

for frameIndex in 0..<totalFrames {
    let time = Double(frameIndex) / fps
    let wholeSecond = Int(time.rounded(.down))
    let frameInSecond = frameIndex % Int(fps.rounded())
    let isFlash = frameInSecond == 0
    let sceneIndex = min(Int(time / 10), scenePalette.count - 1)
    let palette = scenePalette[sceneIndex]

    if isFlash {
        context.setFillColor(makeColor(1, 1, 1))
        context.fill(CGRect(x: 0, y: 0, width: W, height: H))
    } else {
        context.setFillColor(background)
        context.fill(CGRect(x: 0, y: 0, width: W, height: H))
        context.setFillColor(makeColor(palette.0, palette.1, palette.2))
        context.fill(CGRect(x: 0, y: H * 0.42, width: W, height: H * 0.58))
    }

    let fg = isFlash ? makeColor(0.05, 0.05, 0.05) : textColor
    let sub = isFlash ? makeColor(0.2, 0.2, 0.2) : muted

    if !isFlash {
        context.setFillColor(panel)
        context.fill(CGRect(x: 0, y: H - 92, width: CGFloat(width), height: 92))
        context.setFillColor(accent)
        context.fill(CGRect(x: 0, y: H - 92, width: 8, height: 92))
    }
    let identity = "OpenFuse Test Pattern  ·  \(width)×\(height)  ·  \(String(format: "%.3f", fps)) fps  ·  HEVC Main 10  ·  E-AC-3 5.1"
    drawText(identity, at: CGPoint(x: 42, y: H - 58), size: 30, weight: .medium, color: isFlash ? fg : textColor, monospaced: true)

    let hours = wholeSecond / 3600
    let minutes = (wholeSecond / 60) % 60
    let secs = wholeSecond % 60
    let timecode = String(format: "%02d:%02d:%02d:%02d", hours, minutes, secs, frameInSecond)
    drawText(timecode, at: CGPoint(x: 80, y: H * 0.60), size: 164, weight: .bold, color: fg, monospaced: true)
    let decimal = String(format: "t = %08.3f s    frame %05d / %05d", time, frameIndex, totalFrames)
    drawText(decimal, at: CGPoint(x: 88, y: H * 0.53), size: 34, weight: .regular, color: sub, monospaced: true)

    let sceneStart = sceneIndex * 10
    drawText(
        String(format: "SCENE %d  ·  %02d:00 – %02d:00", sceneIndex + 1, sceneStart, sceneStart + 10),
        at: CGPoint(x: 88, y: H * 0.47), size: 30, weight: .semibold, color: isFlash ? fg : warm, monospaced: true
    )

    if !isFlash {
        let cx = W * 0.80
        let cy = H * 0.62
        let speakerColor = makeColor(0.72, 0.78, 0.86)
        let labels = ["L", "R", "C", "LFE", "Ls", "Rs"]
        let points: [CGPoint] = [
            CGPoint(x: cx - 230, y: cy + 90),
            CGPoint(x: cx + 230, y: cy + 90),
            CGPoint(x: cx, y: cy + 140),
            CGPoint(x: cx, y: cy - 40),
            CGPoint(x: cx - 210, y: cy - 70),
            CGPoint(x: cx + 210, y: cy - 70),
        ]
        for (index, point) in points.enumerated() {
            let active = (wholeSecond % 6) == index
            context.setFillColor(active ? accent : speakerColor)
            context.fill(CGRect(x: point.x - 46, y: point.y - 26, width: 92, height: 52))
            drawText(labels[index], at: CGPoint(x: point.x, y: point.y - 10), size: 24, weight: .bold,
                     color: makeColor(0.04, 0.05, 0.07), monospaced: true, alignment: .center)
        }
        drawText("5.1 CHANNEL MAP", at: CGPoint(x: cx, y: cy + 210), size: 24, weight: .medium, color: sub, monospaced: true, alignment: .center)
    }

    let progress = CGFloat(time / seconds)
    if !isFlash {
        context.setFillColor(warm)
        context.fill(CGRect(x: progress * W - 2, y: 0, width: 4, height: H * 0.42))
        context.setFillColor(makeColor(1, 1, 1, 0.12))
        context.fill(CGRect(x: 0, y: 40, width: W, height: 10))
        context.setFillColor(accent)
        context.fill(CGRect(x: 0, y: 40, width: progress * W, height: 10))
    }

    if !isFlash {
        drawText("SUBTITLE SAFE AREA  ·  字幕安全区", at: CGPoint(x: 88, y: 70), size: 22, weight: .regular, color: makeColor(0.4, 0.45, 0.52))
        drawText(String(format: "%02d:%02d", minutes, secs), at: CGPoint(x: W - 88, y: 52), size: 40, weight: .semibold, color: sub, monospaced: true, alignment: .right)
    }

    stdout.write(Data(bytes: storage, count: byteCount))

    if frameIndex % Int(fps.rounded()) == 0 {
        FileHandle.standardError.write("frame \(frameIndex)/\(totalFrames) @ \(String(format: "%.2f", time))s\n".data(using: .utf8)!)
    }
}

storage.deallocate()
