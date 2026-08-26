import SwiftUI

/// Stabiler Dauer-Puls: repeatForever-Animation, die NICHT an einen
/// sich ändernden Wert gebunden ist (umgeht SwiftUI-Gesture-Crash macOS 26.6).
struct PulseForever: ViewModifier {
    var intensity: Double

    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(!reduceMotion && pulsing ? max(1 - intensity, 0.05) : 1)
            .onAppear { pulsing = !reduceMotion }
            .onChange(of: reduceMotion) { _, reduced in pulsing = !reduced }
            .animation(
                reduceMotion ? nil
                    : Animation.easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                value: pulsing
            )
    }
}

extension View {
    func pulseForever(intensity: Double = 0.4) -> some View {
        modifier(PulseForever(intensity: intensity))
    }
}
