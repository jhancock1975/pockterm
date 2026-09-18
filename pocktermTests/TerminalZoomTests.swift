import Testing
import CoreGraphics
@testable import pockterm

@Test @MainActor func zoomClampsToLowerBound() {
    #expect(TerminalZoom.clamped(base: 10, scale: 0.1) == 8)
}

@Test @MainActor func zoomClampsToUpperBound() {
    #expect(TerminalZoom.clamped(base: 20, scale: 10) == 32)
}

@Test @MainActor func zoomRoundsMidRange() {
    // 14 * 1.2 = 16.8 -> 17
    #expect(TerminalZoom.clamped(base: 14, scale: 1.2) == 17)
    // 14 * 1.0 stays 14
    #expect(TerminalZoom.clamped(base: 14, scale: 1.0) == 14)
}
