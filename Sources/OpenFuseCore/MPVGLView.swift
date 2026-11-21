import AppKit
import CoreVideo
import OpenGL.GL
import QuartzCore

/// `NSOpenGLView` that libmpv renders into.
///
/// Kept as the presentation surface on purpose: the 0.5.0 Core Animation
/// (`CAOpenGLLayer`) rewrite introduced two picture-level regressions that did
/// not reproduce with this view — plain-text (SRT) subtitles disappeared and
/// Core Animation reinterpreted the float drawable, tinting the picture on XDR
/// displays. This view uses the same 8-bit sRGB drawable as 0.4.x, so libmpv's
/// subtitle bitmaps and colours reach the screen unchanged.
///
/// The timing work stays: a CVDisplayLink reports swaps and the panel refresh
/// rate to mpv, and the update callback only marks the view dirty (the player's
/// playhead is published separately by `PlaybackClock`).
public final class MPVGLView: NSOpenGLView {
    fileprivate let engine: MPVEngine
    private var didCreateContext = false
    private var pendingCaptureURL: URL?
    private var displayLink: CVDisplayLink?
    private var currentDisplay: CGDirectDisplayID?
    private var isUninited = false

    public init?(engine: MPVEngine) {
        self.engine = engine
        let attributes: [NSOpenGLPixelFormatAttribute] = [
            NSOpenGLPixelFormatAttribute(NSOpenGLPFAAccelerated),
            NSOpenGLPixelFormatAttribute(NSOpenGLPFADoubleBuffer),
            NSOpenGLPixelFormatAttribute(NSOpenGLPFAColorSize), 24,
            NSOpenGLPixelFormatAttribute(NSOpenGLPFAAlphaSize), 8,
            NSOpenGLPixelFormatAttribute(NSOpenGLPFADepthSize), 0,
            NSOpenGLPixelFormatAttribute(NSOpenGLPFAOpenGLProfile),
            NSOpenGLPixelFormatAttribute(NSOpenGLProfileVersion3_2Core),
            0,
        ]
        let format = NSOpenGLPixelFormat(attributes: attributes) ?? NSOpenGLPixelFormat(attributes: [
            NSOpenGLPixelFormatAttribute(NSOpenGLPFADoubleBuffer),
            NSOpenGLPixelFormatAttribute(NSOpenGLPFAColorSize), 24,
            0,
        ])!
        super.init(frame: .zero, pixelFormat: format)
        wantsBestResolutionOpenGLSurface = true
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    deinit {
        uninit()
    }

    public override var isOpaque: Bool { true }
    public override var acceptsFirstResponder: Bool { true }

    /// The mpv surface sits under SwiftUI's control overlay. AppKit views are
    /// routed mouse events before the SwiftUI layers drawn above them, so
    /// without this the play/pause, subtitle and audio controls silently
    /// swallowed every click. Returning nil lets clicks fall through to the
    /// overlay while keyboard focus stays with the window.
    public override func hitTest(_ point: NSPoint) -> NSView? { nil }

    public override func prepareOpenGL() {
        super.prepareOpenGL()
        guard let context = openGLContext else { return }
        context.makeCurrentContext()
        var swapInterval: GLint = 1
        context.setValues(&swapInterval, for: .swapInterval)
        if !didCreateContext {
            didCreateContext = engine.makeRenderContext(view: self)
        }
    }

    public override func reshape() {
        super.reshape()
        needsDisplay = true
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard let context = openGLContext, didCreateContext, !isUninited else { return }
        context.makeCurrentContext()
        engine.render(into: self)
        engine.reportSwap()
        if ProcessInfo.processInfo.environment["OPENFUSE_DEBUG_GL"] != nil {
            let stamp = DispatchTime.now().uptimeNanoseconds
            FileHandle.standardError.write(Data("[gl] draw \(stamp)\n".utf8))
        }
        if let url = pendingCaptureURL {
            pendingCaptureURL = nil
            captureFramebuffer(to: url)
        }
        context.flushBuffer()
    }

    // MARK: - Display link

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            stopDisplayLink()
            return
        }
        startDisplayLink()
    }

    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            stopDisplayLink()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    private func startDisplayLink() {
        guard !isUninited else { return }
        let link: CVDisplayLink
        if let existing = displayLink {
            link = existing
        } else {
            var created: CVDisplayLink?
            CVDisplayLinkCreateWithActiveCGDisplays(&created)
            guard let created else { return }
            displayLink = created
            link = created
        }
        guard !CVDisplayLinkIsRunning(link) else { return }

        if let screen = window?.screen ?? NSScreen.main {
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            let displayID = (screen.deviceDescription[key] as? NSNumber)?.uint32Value
            if let displayID, currentDisplay != displayID {
                currentDisplay = displayID
                CVDisplayLinkSetCurrentCGDisplay(link, displayID)
            }
            let actual = CVDisplayLinkGetActualOutputVideoRefreshPeriod(link)
            let nominal = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(link)
            var fps: Double = 0
            if nominal.flags & Int32(CVTimeFlags.isIndefinite.rawValue) == 0, nominal.timeValue > 0 {
                let nominalFPS = Double(nominal.timeScale) / Double(nominal.timeValue)
                if actual > 0 { fps = 1 / actual }
                if fps == 0 || abs(fps - nominalFPS) > 1 { fps = nominalFPS }
            } else {
                fps = 60
            }
            if fps > 1 {
                engine.setProperty("display-fps-override", String(format: "%.3f", fps))
            }
        }

        CVDisplayLinkSetOutputCallback(link, mpvglDisplayLinkCallback, Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkStart(link)
    }

    private func stopDisplayLink() {
        guard let link = displayLink, CVDisplayLinkIsRunning(link) else { return }
        CVDisplayLinkStop(link)
    }

    /// Releases the libmpv render context with this view's GL context current,
    /// then stops drawing. Called from the main thread by `MPVEngine.stop()`.
    func prepareForTeardown() {
        if !isUninited { uninit() }
        openGLContext?.makeCurrentContext()
        engine.freeRenderContext()
    }

    /// Stops drawing before mpv is torn down.
    func uninit() {
        guard !isUninited else { return }
        isUninited = true
        stopDisplayLink()
    }

    // MARK: - Frame capture

    /// Ask for one PNG of the next rendered frame. This is the frame the video
    /// output actually produced, not a still extracted from the file.
    public func requestFrameCapture(to url: URL) {
        pendingCaptureURL = url
        needsDisplay = true
    }

    private func captureFramebuffer(to url: URL) {
        let backing = convertToBacking(bounds)
        let width = Int(backing.width)
        let height = Int(backing.height)
        guard width > 0, height > 0 else { return }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
        glPixelStorei(GLenum(GL_PACK_ALIGNMENT), 1)
        glReadBuffer(GLenum(GL_BACK))
        glReadPixels(0, 0, GLsizei(width), GLsizei(height), GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), &pixels)
        var flipped = [UInt8](repeating: 0, count: pixels.count)
        let rowBytes = width * 4
        for row in 0..<height {
            let source = (height - 1 - row) * rowBytes
            let destination = row * rowBytes
            flipped.replaceSubrange(destination..<(destination + rowBytes), with: pixels[source..<(source + rowBytes)])
        }
        let data = Data(flipped)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: rowBytes, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              )
        else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
            print("[OpenFuse] captured rendered frame \(width)x\(height) to \(url.path)")
        }
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsDisplay = true
    }
}

private let mpvglDisplayLinkCallback: CVDisplayLinkOutputCallback = { _, _, _, _, _, context in
    guard let context else { return kCVReturnSuccess }
    let view = Unmanaged<MPVGLView>.fromOpaque(context).takeUnretainedValue()
    view.engine.reportSwap()
    return kCVReturnSuccess
}
