import AppKit
import CMpv
import Foundation
import OpenGL.GL
import QuartzCore

/// OpenGL layer for `MPVVideoView`, ported from IINA's `ViewLayer.swift`
/// (https://github.com/iina/iina, GPL-3.0).
///
/// The previous implementation rendered from `NSOpenGLView.draw(_:)` on the
/// main thread with `swapInterval = 1`, so every SwiftUI layout pass or menu
/// animation could hold the next video frame back. This layer draws from a
/// dedicated queue (`mpvGLQueue`) and lets Core Animation schedule the display,
/// exactly like IINA:
/// - libmpv's update callback posts to `mpvGLQueue` and calls `display()`.
/// - `canDraw` asks libmpv whether a frame is due (`mpv_render_context_update`).
/// - when AppKit skips a draw (another space, minimized), `display()` renders
///   with `SKIP_RENDERING` so the frame queue keeps moving.
final class MPVVideoLayer: CAOpenGLLayer {
    private let controller: MPVController
    private let mpvGLQueue = DispatchQueue(label: "openfuse.mpvgl", qos: .userInteractive)
    private let displayLock = NSRecursiveLock()
    /// Lets the main thread jump ahead of the GL queue when it needs
    /// `displayLock` (IINA's `MainThreadPriorityLock`). Without it the main
    /// thread can be descheduled behind the render queue, which shows up as a
    /// multi-frame video stall during window/layout work.
    private let mainThreadPriorityLock = MainThreadPriorityLock()
    private let stateLock = NSRecursiveLock()

    private let cglPixelFormat: CGLPixelFormatObj
    private let cglContext: CGLContextObj
    private var bufferDepth: GLint = 8

    private var isUninited = false
    private var needsFlip = false
    private var forceDraw = false
    private var fbo: GLint = 0
    private var pendingCaptureURL: URL?

    var inLiveResize = false {
        didSet {
            if inLiveResize { isAsynchronous = true }
            update(force: true)
        }
    }

    init(controller: MPVController) {
        self.controller = controller
        let created = Self.createPixelFormat()
        self.cglPixelFormat = created.pixelFormat
        self.bufferDepth = created.depth
        self.cglContext = Self.createContext(created.pixelFormat)
        super.init()
        autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        backgroundColor = NSColor.black.cgColor
        if bufferDepth > 8 {
            contentsFormat = .RGBA16Float
        }
        isAsynchronous = false
        contentsGravity = .resizeAspect
    }

    override init(layer: Any) {
        let previous = layer as! MPVVideoLayer
        controller = previous.controller
        cglPixelFormat = previous.cglPixelFormat
        cglContext = previous.cglContext
        bufferDepth = previous.bufferDepth
        super.init(layer: layer)
        autoresizingMask = previous.autoresizingMask
        backgroundColor = previous.backgroundColor
        contentsFormat = previous.contentsFormat
        contentsGravity = previous.contentsGravity
        isAsynchronous = previous.isAsynchronous
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not implemented")
    }

    // MARK: - Context lifecycle

    /// Creates the libmpv render context against this layer's CGL context and
    /// routes future frame notifications to `update()`.
    @discardableResult
    func attachRenderer() -> Bool {
        CGLLockContext(cglContext)
        CGLSetCurrentContext(cglContext)
        let success = controller.createRenderContext(openGLContext: cglContext)
        if ProcessInfo.processInfo.environment["OPENFUSE_DEBUG_GL"] != nil {
            FileHandle.standardError.write(Data("[gl] render context ready=\(success) depth=\(bufferDepth)\n".utf8))
        }
        if success {
            controller.setRenderUpdateCallback({ context in
                guard let context else { return }
                let layer = Unmanaged<MPVVideoLayer>.fromOpaque(context).takeUnretainedValue()
                layer.update()
            }, context: Unmanaged.passUnretained(self).toOpaque())
        }
        CGLUnlockContext(cglContext)
        return success
    }

    /// Stops drawing and frees the render context. Must run before mpv quits.
    func uninit() {
        stateLock.lock()
        if isUninited {
            stateLock.unlock()
            return
        }
        isUninited = true
        stateLock.unlock()
        controller.setRenderUpdateCallback(nil, context: nil)
        // `destroyRenderContext` takes the CGL lock, which is also held by
        // Core Animation for the duration of `draw(inCGLContext:)`; that is
        // what serialises the free against an in-flight render.
        controller.destroyRenderContext()
    }

    var isRenderingUninited: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isUninited
    }

    // MARK: - Draw

    override func canDraw(
        inCGLContext ctx: CGLContextObj,
        pixelFormat pf: CGLPixelFormatObj,
        forLayerTime t: CFTimeInterval,
        displayTime ts: UnsafePointer<CVTimeStamp>?
    ) -> Bool {
        if inLiveResize && Thread.isMainThread { return false }
        guard !isRenderingUninited else { return false }
        if !inLiveResize { isAsynchronous = false }
        return forceDraw || controller.shouldRenderUpdateFrame()
    }

    override func draw(
        inCGLContext ctx: CGLContextObj,
        pixelFormat pf: CGLPixelFormatObj,
        forLayerTime t: CFTimeInterval,
        displayTime ts: UnsafePointer<CVTimeStamp>?
    ) {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !isUninited else { return }
        needsFlip = false
        forceDraw = false

        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))

        var drawFBO: GLint = 0
        glGetIntegerv(GLenum(GL_DRAW_FRAMEBUFFER_BINDING), &drawFBO)
        var viewport = [GLint](repeating: 0, count: 4)
        glGetIntegerv(GLenum(GL_VIEWPORT), &viewport)
        if drawFBO != 0 { fbo = drawFBO }

        guard let renderContext = controller.renderContext else {
            glClearColor(0, 0, 0, 1)
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
            return
        }

        var flip: CInt = 1
        var fboData = mpv_opengl_fbo(
            fbo: Int32(fbo),
            w: Int32(viewport[2]),
            h: Int32(viewport[3]),
            internal_format: 0
        )
        var depth = bufferDepth
        withUnsafeMutablePointer(to: &fboData) { fboPointer in
            withUnsafeMutablePointer(to: &flip) { flipPointer in
                withUnsafeMutablePointer(to: &depth) { depthPointer in
                    var params = [
                        mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: UnsafeMutableRawPointer(fboPointer)),
                        mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: UnsafeMutableRawPointer(flipPointer)),
                        mpv_render_param(type: MPV_RENDER_PARAM_DEPTH, data: UnsafeMutableRawPointer(depthPointer)),
                        mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                    ]
                    let code = mpv_render_context_render(renderContext, &params)
                    if code < 0 && ProcessInfo.processInfo.environment["OPENFUSE_DEBUG_GL"] != nil {
                        print("[gl] render failed: \(String(cString: mpv_error_string(code)))")
                    }
                }
            }
        }
        glFlush()

        if ProcessInfo.processInfo.environment["OPENFUSE_DEBUG_GL"] != nil {
            // Unbuffered stderr: `Scripts/run-player-pipeline.sh` timestamps
            // these lines to measure frame pacing.
            let stamp = DispatchTime.now().uptimeNanoseconds
            let target = ts.map { String($0.pointee.hostTime) } ?? "0"
            let line = "[gl] draw \(stamp) present=\(target) \(viewport[2])x\(viewport[3]) fbo=\(fbo)\n"
            FileHandle.standardError.write(Data(line.utf8))
        }

        if let url = pendingCaptureURL {
            pendingCaptureURL = nil
            captureFramebuffer(to: url, width: Int(viewport[2]), height: Int(viewport[3]))
        }
    }

    /// Ported from IINA's `ViewLayer.display()`. When AppKit decides not to
    /// draw (the window is on another space, or occluded), libmpv still needs a
    /// render call to release the frame it handed us, otherwise playback stalls
    /// and then jumps.
    override func display() {
        mainThreadPriorityLock.beforeLocking()
        displayLock.lock()
        defer { displayLock.unlock() }
        mainThreadPriorityLock.afterLocked()

        let isUpdate = needsFlip

        if Thread.isMainThread {
            super.display()
        } else {
            // Explicit transaction: CA_ASSERT_MAIN_THREAD_TRANSACTIONS builds
            // abort when an implicit transaction is created off-main.
            CATransaction.begin()
            super.display()
            CATransaction.commit()
        }
        // A nested implicit transaction is not rendered by `commit`.
        CATransaction.flush()

        guard isUpdate, needsFlip else { return }

        controller.lockAndSetOpenGLContext()
        defer { controller.unlockOpenGLContext() }
        guard !isRenderingUninited,
              let renderContext = controller.renderContext,
              controller.shouldRenderUpdateFrame()
        else { return }

        var skip: CInt = 1
        var blockForTargetTime: CInt = 0
        withUnsafeMutablePointer(to: &skip) { skipPointer in
            withUnsafeMutablePointer(to: &blockForTargetTime) { blockPointer in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_SKIP_RENDERING, data: UnsafeMutableRawPointer(skipPointer)),
                    mpv_render_param(type: MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME, data: UnsafeMutableRawPointer(blockPointer)),
                    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                ]
                mpv_render_context_render(renderContext, &params)
            }
        }
    }

    func update(force: Bool = false) {
        mpvGLQueue.async { [weak self] in
            guard let self else { return }
            if force { self.forceDraw = true }
            self.needsFlip = true
            self.display()
        }
    }

    // MARK: - Capture

    /// Ask for one PNG of the next rendered frame. Mirrors the old
    /// `MPVGLView.requestFrameCapture` behaviour used by the acceptance
    /// scripts.
    func requestFrameCapture(to url: URL) {
        stateLock.lock()
        pendingCaptureURL = url
        stateLock.unlock()
        update(force: true)
    }

    private func captureFramebuffer(to url: URL, width: Int, height: Int) {
        guard width > 0, height > 0 else { return }
        let rowBytes = width * 4
        var pixels = [UInt8](repeating: 0, count: rowBytes * height)

        var previousReadFBO: GLint = 0
        glGetIntegerv(GLenum(GL_READ_FRAMEBUFFER_BINDING), &previousReadFBO)
        defer { glBindFramebuffer(GLenum(GL_READ_FRAMEBUFFER), GLuint(previousReadFBO)) }
        glBindFramebuffer(GLenum(GL_READ_FRAMEBUFFER), GLuint(fbo))
        glReadBuffer(fbo == 0 ? GLenum(GL_BACK) : GLenum(GL_COLOR_ATTACHMENT0))
        glPixelStorei(GLenum(GL_PACK_ALIGNMENT), 1)
        glReadPixels(0, 0, GLsizei(width), GLsizei(height), GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), &pixels)

        var flipped = [UInt8](repeating: 0, count: pixels.count)
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

    override func copyCGLPixelFormat(forDisplayMask mask: UInt32) -> CGLPixelFormatObj {
        cglPixelFormat
    }

    override func copyCGLContext(forPixelFormat pf: CGLPixelFormatObj) -> CGLContextObj {
        cglContext
    }

    // MARK: - Pixel format / context

    private static func createPixelFormat() -> (pixelFormat: CGLPixelFormatObj, depth: GLint) {
        let base: [CGLPixelFormatAttribute] = [
            kCGLPFAOpenGLProfile,
            CGLPixelFormatAttribute(kCGLOGLPVersion_3_2_Core.rawValue),
            kCGLPFAAccelerated,
            kCGLPFADoubleBuffer,
            kCGLPFABackingStore,
            kCGLPFAAllowOfflineRenderers,
        ]
        let tenBit: [CGLPixelFormatAttribute] = [
            kCGLPFAColorSize, CGLPixelFormatAttribute(rawValue: 64),
            kCGLPFAColorFloat,
        ]
        let autoGPU: [CGLPixelFormatAttribute] = [kCGLPFASupportsAutomaticGraphicsSwitching]

        var variants: [[CGLPixelFormatAttribute]] = [
            base + tenBit + autoGPU,
            base + tenBit,
            base + autoGPU,
            base,
        ]
        // Legacy profile fallback for machines that reject a 3.2 core context.
        let legacyBase: [CGLPixelFormatAttribute] = [
            kCGLPFAOpenGLProfile,
            CGLPixelFormatAttribute(kCGLOGLPVersion_Legacy.rawValue),
            kCGLPFAAccelerated,
            kCGLPFADoubleBuffer,
        ]
        variants.append(legacyBase)

        for attributes in variants {
            var format = attributes
            format.append(CGLPixelFormatAttribute(rawValue: 0))
            var pixelFormat: CGLPixelFormatObj?
            var count: GLint = 0
            let error = CGLChoosePixelFormat(format, &pixelFormat, &count)
            if error == kCGLNoError, let pixelFormat {
                let depth: GLint = attributes.contains(kCGLPFAColorFloat) ? 16 : 8
                return (pixelFormat, depth)
            }
        }
        fatalError("Cannot create an OpenGL pixel format")
    }

    private static func createContext(_ pixelFormat: CGLPixelFormatObj) -> CGLContextObj {
        var context: CGLContextObj?
        CGLCreateContext(pixelFormat, nil, &context)
        guard let context else {
            fatalError("Cannot create an OpenGL context")
        }
        var swapInterval: GLint = 1
        CGLSetParameter(context, kCGLCPSwapInterval, &swapInterval)
        CGLEnable(context, kCGLCEMPEngine)
        CGLSetCurrentContext(context)
        return context
    }
}

/// Port of IINA's `MainThreadPriorityLock` (`ViewLayer.swift`).
///
/// The main thread creates the implicit Core Animation transaction that the
/// GL queue's `display()` call depends on. If the GL queue holds `displayLock`
/// while the main thread waits for it, the UI thread is descheduled and the
/// video misses refresh deadlines. Background threads wait here while the main
/// thread is on its way into the lock.
private final class MainThreadPriorityLock {
    private let condition = NSCondition()
    private var needsLock = false

    func beforeLocking() {
        condition.lock()
        defer { condition.unlock() }
        guard Thread.isMainThread else {
            while needsLock { condition.wait() }
            return
        }
        needsLock = true
    }

    func afterLocked() {
        guard Thread.isMainThread else { return }
        condition.lock()
        defer { condition.unlock() }
        needsLock = false
        condition.broadcast()
    }
}
