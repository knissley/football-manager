/// Rounding that does not reach for libm.
///
/// `Double.rounded()` resolves to libm's `round`, and none of the simulation
/// modules link libm — they import nothing at all, not even Foundation, so that
/// any client can link them. A test target hides the problem by linking the
/// testing library; a plain executable does not, which is what `Tools/playsize`
/// exists to catch.
///
/// Conversion, subtraction and comparison are enough, and they are exactly
/// specified by IEEE 754, so the result is identical on every platform.
public enum Rounding {

    /// Round half away from zero.
    public static func toNearest(_ value: Double) -> Int64 {
        let truncated = Int64(value)
        let fraction = value - Double(truncated)
        if fraction >= 0.5 { return truncated + 1 }
        if fraction <= -0.5 { return truncated - 1 }
        return truncated
    }

    /// Round half away from zero, then clamp into a range.
    public static func toNearest(_ value: Double, clampedTo range: ClosedRange<Int>) -> Int {
        let rounded = Int(toNearest(value))
        return min(max(rounded, range.lowerBound), range.upperBound)
    }
}
