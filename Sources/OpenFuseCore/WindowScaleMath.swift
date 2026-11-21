import CoreGraphics
import Foundation

/// IINA-style window-size commands.
public enum WindowScaleAction: String, Sendable {
    case half
    case normal
    case doubleSize
    case fit
    case smaller
    case bigger
}

public enum WindowScaleMath {
    /// Returns the content size for `action`, clamped to `maxContent` while
    /// preserving the aspect ratio and never going below 320×180.
    public static func targetSize(
        action: WindowScaleAction,
        videoSize: CGSize?,
        current: CGSize,
        maxContent: CGSize
    ) -> CGSize {
        let currentAspect = current.height > 0 ? current.width / current.height : 16.0 / 9.0
        let videoAspect = videoSize.map { $0.height > 0 ? $0.width / $0.height : currentAspect } ?? currentAspect

        var target: CGSize
        switch action {
        case .half:
            let base = videoSize ?? current
            target = CGSize(width: base.width * 0.5, height: base.height * 0.5)
        case .normal:
            target = videoSize ?? current
        case .doubleSize:
            let base = videoSize ?? current
            target = CGSize(width: base.width * 2, height: base.height * 2)
        case .fit:
            target = fit(aspect: videoAspect, in: maxContent)
        case .smaller:
            target = CGSize(width: current.width * 0.9, height: current.height * 0.9)
        case .bigger:
            target = CGSize(width: current.width * 1.1, height: current.height * 1.1)
        }

        let scale = min(1, maxContent.width / max(target.width, 1), maxContent.height / max(target.height, 1))
        return CGSize(
            width: max(320, target.width * scale),
            height: max(180, target.height * scale)
        )
    }

    public static func fit(aspect: CGFloat, in maxContent: CGSize) -> CGSize {
        guard aspect > 0 else { return maxContent }
        var width = maxContent.width
        var height = width / aspect
        if height > maxContent.height {
            height = maxContent.height
            width = height * aspect
        }
        return CGSize(width: width, height: height)
    }
}
