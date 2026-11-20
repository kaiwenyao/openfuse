import AppKit
import CoreVideo
import Foundation
import QuartzCore

/// Hosts `MPVVideoLayer` and drives libmpv's swap reporting from a
/// `CVDisplayLink`. Port of IINA's `VideoView.swift` subset
/// (https://github.com/iina/iina, GPL-3.0).
///
/// Two things happen here that the old `NSOpenGLView` implementation did not do:
/// 1. `mpv_render_context_report_swap()` runs on the display link's own thread,
///    once per real refresh, so mpv can pace frames against the panel instead
///    of guessing the display rate (the old code reported swap from inside
///    `draw(_:)`, after a main-thread round trip).
/// 2. The panel's actual refresh rate is pushed to mpv as
///    `display-fps-override`, which is what keeps 23.976 fps content even on a
///    120 Hz MacBook display.
public final class MPVVideoView: NSView {
    let engine: MPVEngine
    private let videoLayer: MPVVideoLayer

    private var displayLink: CVDisplayLink?
    private var currentDisplay: CGDirectDisplayID?
    private var idleWorkItem: DispatchWorkItem?
    private var isUninited = false
    private var isPlaybackActive = true

    public init(engine: MPVEngine) {
        self.engine = engine
        self.videoLayer = MPVVideoLayer(controller: engine.controller)
        super.init(frame: .zero)
        wantsLayer = true
        layer = videoLayer
        videoLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        wantsBestResolutionOpenGLSurface = true
        wantsExtendedDynamicRangeOpenGLSurface = true
        autoresizingMask = [.width, .height]
        engine.attachRenderer(layer: videoLayer)
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

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            stopDisplayLink()
            return
        }
        videoLayer.contentsScale = window?.backingScaleFactor ?? 2
        videoLayer.update(force: true)
        updateDisplayLink()
        startDisplayLink()
    }

    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            stopDisplayLink()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        videoLayer.contentsScale = window?.backingScaleFactor ?? 2
        videoLayer.update(force: true)
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        videoLayer.update(force: true)
    }

    public override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        videoLayer.inLiveResize = false
    }

    public override func viewWillStartLiveResize() {
        super.viewWillStartLiveResize()
        videoLayer.inLiveResize = true
    }

    // MARK: - Public surface

    public func requestFrameCapture(to url: URL) {
        videoLayer.requestFrameCapture(to: url)
    }

    /// Called when playback pauses/resumes. The display link is a high
    /// priority thread at the panel refresh rate, so it is stopped after a
    /// short grace period while paused (same trade-off as IINA's
    /// `displayIdle`).
    func setPlaybackActive(_ active: Bool) {
        isPlaybackActive = active
        guard !isUninited else { return }
        idleWorkItem?.cancel()
        if active {
            startDisplayLink()
            videoLayer.update(force: true)
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isPlaybackActive else { return }
            self.stopDisplayLink()
        }
        idleWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: work)
    }

    /// Stops drawing and releases the mpv render context. Runs before mpv is
    /// told to quit; the event loop must not touch a freed render context.
    func uninit() {
        guard !isUninited else { return }
        isUninited = true
        idleWorkItem?.cancel()
        idleWorkItem = nil
        stopDisplayLink()
        videoLayer.uninit()
    }

    // MARK: - Display link

    private func startDisplayLink() {
        guard !isUninited else { return }
        let link = obtainDisplayLink()
        guard !CVDisplayLinkIsRunning(link) else { return }
        updateDisplayLink()
        CVDisplayLinkSetOutputCallback(link, openfuseDisplayLinkCallback, Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkStart(link)
    }

    private func stopDisplayLink() {
        guard let link = displayLink, CVDisplayLinkIsRunning(link) else { return }
        CVDisplayLinkStop(link)
    }

    private func obtainDisplayLink() -> CVDisplayLink {
        if let displayLink { return displayLink }
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else {
            fatalError("Cannot create a CVDisplayLink")
        }
        displayLink = link
        return link
    }

    /// Points the display link at the panel the window is on and forwards the
    /// real refresh rate to mpv.
    private func updateDisplayLink() {
        guard let link = displayLink, let screen = window?.screen ?? NSScreen.main else { return }
        let displayID = Self.displayID(for: screen)
        if let displayID, currentDisplay != displayID {
            currentDisplay = displayID
            CVDisplayLinkSetCurrentCGDisplay(link, displayID)
        }

        let actual = CVDisplayLinkGetActualOutputVideoRefreshPeriod(link)
        let nominal = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(link)
        var fps: Double = 0
        if nominal.flags & Int32(CVTimeFlags.isIndefinite.rawValue) == 0, nominal.timeValue > 0 {
            let nominalFPS = Double(nominal.timeScale) / Double(nominal.timeValue)
            if actual > 0 {
                fps = 1 / actual
            }
            if fps == 0 || abs(fps - nominalFPS) > 1 {
                fps = nominalFPS
            }
        } else {
            fps = 60
        }
        guard fps > 1 else { return }
        engine.setProperty("display-fps-override", String(format: "%.3f", fps))
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
    }
}

/// Runs on the display link thread once per refresh.
private let openfuseDisplayLinkCallback: CVDisplayLinkOutputCallback = { _, _, _, _, _, context in
    guard let context else { return kCVReturnSuccess }
    let view = Unmanaged<MPVVideoView>.fromOpaque(context).takeUnretainedValue()
    view.engine.reportSwap()
    return kCVReturnSuccess
}
