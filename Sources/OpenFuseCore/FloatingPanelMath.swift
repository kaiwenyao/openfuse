import CoreGraphics

/// Geometry for the floating player panel.
///
/// The panel is positioned by the player chrome and can be dragged. Keeping the
/// clamping pure makes "the panel never leaves the window" testable without a
/// running app, and lets window resize / native fullscreen reuse the same rule.
public enum FloatingPanelMath {
    /// Horizontal inset between the panel and the player edge.
    public static func panelInset(containerWidth: CGFloat) -> CGFloat {
        if containerWidth < 420 { return 8 }
        if containerWidth < 720 { return 12 }
        return 16
    }

    /// The panel starts at 480–560 pt on a normal window and shrinks with it.
    public static func panelWidth(containerWidth: CGFloat) -> CGFloat {
        guard containerWidth > 0 else { return 0 }
        let inset = panelInset(containerWidth: containerWidth)
        return max(0, min(560, containerWidth - inset * 2))
    }

    /// Two-row panel height: transport row + timeline + insets. Used before
    /// the first geometry pass and as the drag clamp while measuring.
    public static func panelHeight(compact: Bool) -> CGFloat {
        compact ? 82 : 94
    }

    /// Vertical space above the default panel position. Leaves room for the
    /// compact title bar; QuickTime-style floating controls sit near the top
    /// rather than over the subtitle area at the bottom.
    public static func topInset(containerWidth: CGFloat) -> CGFloat {
        containerWidth < 420 ? 54 : 64
    }

    /// Default origin: horizontally centred, below the title bar.
    public static func baseOrigin(containerSize: CGSize, panelSize: CGSize) -> CGPoint {
        let width = containerSize.width
        let inset = panelInset(containerWidth: width)
        let x = max(inset, (width - panelSize.width) / 2)
        return CGPoint(x: x, y: topInset(containerWidth: width))
    }

    /// Keeps `offset` such that the whole panel stays inside the player rect.
    /// The returned offset is relative to `baseOrigin`, so the caller can keep
    /// one drag state across window resizes and fullscreen transitions.
    public static func clampedOffset(
        offset: CGSize,
        panelSize: CGSize,
        containerSize: CGSize,
        edge: CGFloat = 8
    ) -> CGSize {
        let base = baseOrigin(containerSize: containerSize, panelSize: panelSize)
        let target = CGPoint(x: base.x + offset.width, y: base.y + offset.height)
        let minX = edge
        let maxX = max(minX, containerSize.width - panelSize.width - edge)
        let minY = edge
        let maxY = max(minY, containerSize.height - panelSize.height - edge)
        let clamped = CGPoint(
            x: min(max(target.x, minX), maxX),
            y: min(max(target.y, minY), maxY)
        )
        return CGSize(width: clamped.x - base.x, height: clamped.y - base.y)
    }

    /// Hover previews open above the timeline unless that would leave the
    /// window. A panel near the top (its default position) opens downward.
    public static func previewOpensDownward(panelOriginY: CGFloat) -> Bool {
        panelOriginY < 190
    }
}
