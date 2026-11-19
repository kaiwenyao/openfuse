import AppKit
import OpenGL.GL

/// NSOpenGLView that libmpv renders into. Kept deliberately small: mpv owns
/// the GL state, this view only supplies the drawable and the frame clock.
public final class MPVGLView: NSOpenGLView {
    private let engine: MPVEngine
    private var didCreateContext = false
    private var pendingCaptureURL: URL?

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

    public override var isOpaque: Bool { true }
    public override var acceptsFirstResponder: Bool { true }

    public override func prepareOpenGL() {
        super.prepareOpenGL()
        guard let context = openGLContext else { return }
        context.makeCurrentContext()
        var swapInterval: GLint = 1
        context.setValues(&swapInterval, for: .swapInterval)
        if ProcessInfo.processInfo.environment["OPENFUSE_DEBUG_GL"] != nil {
            print("[gl] version \(String(cString: glGetString(GLenum(GL_VERSION)))) renderer \(String(cString: glGetString(GLenum(GL_RENDERER))))")
        }
        if !didCreateContext {
            didCreateContext = engine.makeRenderContext(view: self)
        }
    }

    public override func reshape() {
        super.reshape()
        needsDisplay = true
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard let context = openGLContext, didCreateContext else { return }
        context.makeCurrentContext()
        engine.render(into: self)
        engine.reportSwap()
        if let url = pendingCaptureURL {
            pendingCaptureURL = nil
            captureFramebuffer(to: url)
        }
        context.flushBuffer()
    }

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
        if ProcessInfo.processInfo.environment["OPENFUSE_DEBUG_GL"] != nil {
            let center = ((height / 2) * width + width / 2) * 4
            print("[gl] capture center rgba \(flipped[center]),\(flipped[center+1]),\(flipped[center+2]),\(flipped[center+3])")
        }
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
