import SwiftUI

struct LaunchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSpinning = false

    var body: some View {
        // Matches the system launch screen, so the snowflake just starts turning when Yuki takes over.
        Image("Snowflake")
            .rotationEffect(.degrees(isSpinning && !reduceMotion ? 360 : 0))
            .opacity(isSpinning && reduceMotion ? 0.5 : 1)
            .animation(
                reduceMotion
                    ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                    : .linear(duration: 2.4).repeatForever(autoreverses: false),
                value: isSpinning
            )
            .onAppear { isSpinning = true }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color("LaunchBackground").ignoresSafeArea())
            .accessibilityLabel("Loading")
    }
}
