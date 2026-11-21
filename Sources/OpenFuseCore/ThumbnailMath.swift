import Foundation

/// Pure geometry/bucketing for the scrubber hover preview.
public enum ThumbnailMath {
    public static func hoverTime(x: CGFloat, width: CGFloat, duration: Double) -> Double {
        guard duration > 0, width > 0 else { return 0 }
        let ratio = min(max(x / width, 0), 1)
        return Double(ratio) * duration
    }

    /// Two-second buckets keep the cache small and match the precision of a
    /// keyframe-accurate preview.
    public static func bucket(for time: Double, seconds: Double = 2) -> Int {
        guard seconds > 0 else { return 0 }
        return Int(floor(max(0, time) / seconds))
    }

    public static func bucketTime(_ bucket: Int, seconds: Double = 2) -> Double {
        Double(max(0, bucket)) * seconds
    }

    /// Clamps the preview's left edge so it never leaves the scrubber width.
    public static func previewOrigin(hoverX: CGFloat, width: CGFloat, previewWidth: CGFloat) -> CGFloat {
        guard width > previewWidth else { return 0 }
        return min(max(hoverX - previewWidth / 2, 0), width - previewWidth)
    }
}
