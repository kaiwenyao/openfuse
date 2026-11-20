import AppKit
import SwiftUI

/// Forces the hosting window into the dark Aqua appearance for as long as the
/// player is on screen.
///
/// OpenFuse defaults to the light theme (0.4.0). The player surface is black,
/// but AppKit draws borderless `Menu` labels, `NSButton` images and the
/// `Slider` track with `labelColor`/`controlTextColor` — black in light mode.
/// That made the subtitle, audio and speed menus of the control bar invisible
/// (the click targets were still there). SwiftUI's `foregroundStyle` does not
/// reach those AppKit-drawn pieces, so the window appearance is switched while
/// the player is mounted and restored to the user's theme afterwards.
struct PlayerChromeHost: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { AppearanceView() }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class AppearanceView: NSView {
    private weak var hostWindow: NSWindow?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        hostWindow = window
        // SwiftUI's window-level `preferredColorScheme` from the root view wins
        // over a nested preference, so the player drives the app appearance
        // directly. This is what turns the titlebar dark as well; the menus and
        // symbol buttons are AppKit-drawn and follow it.
        NSApp.appearance = NSAppearance(named: .darkAqua)
        window.appearance = NSAppearance(named: .darkAqua)
        if ProcessInfo.processInfo.environment["OPENFUSE_DEBUG_GL"] != nil {
            FileHandle.standardError.write(Data("[gl] chrome host attached, window appearance=\(window.appearance?.name.rawValue ?? "nil") nsapp=\(NSApp.appearance?.name.rawValue ?? "nil")\n".utf8))
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            let theme = AppTheme.stored
            NSApp.appearance = theme.appearance
            (hostWindow ?? self.window)?.appearance = theme.appearance
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override var isOpaque: Bool { false }

    /// Never intercept clicks; the control overlay above must keep receiving
    /// them (see `MPVVideoView.hitTest`).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
