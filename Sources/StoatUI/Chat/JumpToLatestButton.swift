import SwiftUI

struct JumpToLatestButton: View {
    let isViewingHistory: Bool
    let action: () -> Void

    var body: some View {
        Button {
            YukiHaptics.selection()
            action()
        } label: {
            Image(systemName: "arrow.down")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(YukiTheme.accentDeep))
                .shadow(radius: 4, y: 2)
        }
        .padding(16)
        .accessibilityLabel(isViewingHistory ? "Jump to present" : "Jump to latest messages")
    }
}
