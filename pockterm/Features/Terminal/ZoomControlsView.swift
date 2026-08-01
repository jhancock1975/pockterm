import SwiftUI
import UIKit

/// Session-only zoom controls overlaid on the terminal: a reset pill shown
/// only while the session is zoomed away from its baseline, and a transient
/// "Default size" HUD (plus a light haptic) confirming a reset.
struct ZoomControlsView: View {
    let session: TerminalSession

    @State private var showHUD = false
    @State private var hudDismissTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            // Reset pill — top-trailing, only while zoomed.
            if session.isZoomed {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: reset) {
                            Label("\(session.currentFontSize)pt",
                                  systemImage: "arrow.counterclockwise")
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(.regularMaterial, in: Capsule())
                        }
                        .tint(.primary)
                        .accessibilityLabel("Reset zoom to default size")
                    }
                    Spacer()
                }
                .padding(.top, 8)
                .padding(.trailing, 12)
                .transition(.opacity.combined(with: .scale))
            }

            // Transient confirmation HUD — centered, non-interactive.
            if showHUD {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 34, weight: .semibold))
                    Text("Default size")
                        .font(.callout.weight(.medium))
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .transition(.opacity)
                .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: session.isZoomed)
        .animation(.easeInOut(duration: 0.2), value: showHUD)
        .onDisappear { hudDismissTask?.cancel() }
    }

    private func reset() {
        session.resetZoom()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // Show the HUD, cancelling any in-flight dismiss so rapid taps don't
        // stack or clip the confirmation.
        hudDismissTask?.cancel()
        showHUD = true
        hudDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.9))
            if !Task.isCancelled { showHUD = false }
        }
    }
}
