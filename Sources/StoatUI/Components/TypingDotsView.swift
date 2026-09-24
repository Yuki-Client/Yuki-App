import SwiftUI

public struct TypingDotsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 0.35)) { context in
            let step = reduceMotion ? -1 : Int(context.date.timeIntervalSinceReferenceDate / 0.35) % 3
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(YukiTheme.accent)
                        .frame(width: 6, height: 6)
                        .offset(y: step == index ? -3 : 0)
                        .opacity(step == index || reduceMotion ? 1.0 : 0.4)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: step)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(YukiTheme.cardSurface)
        .cornerRadius(12)
        .accessibilityHidden(true)
    }
}
