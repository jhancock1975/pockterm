import CoreGraphics

/// Pure zoom math for the terminal's pinch gesture, factored out for testing.
enum TerminalZoom {
    static let minSize = 8
    static let maxSize = 32

    /// Multiplies `base` by the gesture `scale`, rounds to the nearest point,
    /// and clamps to the legible `minSize…maxSize` band.
    static func clamped(base: Int, scale: CGFloat) -> Int {
        let scaled = Int((CGFloat(base) * scale).rounded())
        return min(maxSize, max(minSize, scaled))
    }
}
