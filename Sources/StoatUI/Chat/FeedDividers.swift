import SwiftUI

struct DateSeparatorRow: View {
    let date: Date

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
            Text(date.formatted(date: .complete, time: .omitted))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize()
            Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

struct UnreadDividerRow: View {
    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color.red.opacity(0.7)).frame(height: 1)
            Text("NEW")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.red))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .accessibilityLabel("New messages")
    }
}
