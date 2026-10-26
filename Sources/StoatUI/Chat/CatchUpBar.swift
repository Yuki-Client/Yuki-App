import SwiftUI

struct CatchUpBar: View {
    let count: Int
    let hasMore: Bool
    let since: Date?
    let onCatchUp: () -> Void
    let onDismiss: () -> Void

    private var title: String {
        let amount = hasMore ? "\(count)+" : "\(count)"
        return count == 1 && !hasMore ? "1 new message" : "\(amount) new messages"
    }

    private var subtitle: String? {
        guard let since else { return nil }
        let time = Calendar.current.isDateInToday(since)
            ? since.formatted(date: .omitted, time: .shortened)
            : since.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        return "Since \(time)"
    }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                YukiHaptics.selection()
                onCatchUp()
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                        if let subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .opacity(0.85)
                        }
                    }
                    Spacer(minLength: 8)
                    Text("Catch Up")
                        .font(.subheadline.weight(.bold))
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                }
                .padding(.leading, 14)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title). \(subtitle ?? "")")
            .accessibilityHint("Jumps to the first message you missed")

            Button {
                YukiHaptics.selection()
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .foregroundStyle(.white)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(YukiTheme.accentDeep)
                .shadow(radius: 4, y: 2)
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}

/// iOS 17 can't tell when a row is on screen, so it uses onAppear instead.
struct UnreadDividerSeen: ViewModifier {
    let onSeen: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollVisibilityChange(threshold: 0.5) { visible in
                if visible { onSeen() }
            }
        } else {
            content.onAppear { onSeen() }
        }
    }
}
