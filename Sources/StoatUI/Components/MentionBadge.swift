import SwiftUI

struct MentionBadge: View {
    let count: Int

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 11, weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 20)
            .background(Capsule().fill(Color.red))
            .yukiPop(on: count)
            .transition(.scale.combined(with: .opacity))
            .accessibilityHidden(true)
    }
}
