import Foundation

/// Pure helpers for the player volume so the clamping/step rules can be unit
/// tested without an mpv instance or a UI.
public enum VolumeMath {
    public static let range: ClosedRange<Double> = 0...100

    public static func clamp(_ value: Double) -> Double {
        guard !value.isNaN else { return 0 }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    public static func stepped(_ value: Double, by delta: Double) -> Double {
        clamp(clamp(value) + delta)
    }

    /// Restores a sensible level when unmuting: never jumps above 100 and never
    /// returns 0 unless the stored level itself was 0.
    public static func unmuted(stored: Double, fallback: Double = 60) -> Double {
        let level = clamp(stored)
        return level > 0 ? level : clamp(fallback)
    }
}
