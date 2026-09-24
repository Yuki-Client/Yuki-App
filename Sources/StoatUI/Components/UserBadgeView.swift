import SwiftUI
import StoatCore

public struct UserBadgeChip: View {
    public let badge: UserBadge
    public var style: Style = .full

    @State private var showInfo = false

    public enum Style {
        case compact
        case full
    }

    public init(badge: UserBadge, style: Style = .full) {
        self.badge = badge
        self.style = style
    }

    private var badgeColor: Color {
        Color(hex: badge.colorHex)
    }

    public var body: some View {
        Button {
            YukiHaptics.impact(.light)
            showInfo = true
        } label: {
            switch style {
            case .compact:
                ZStack {
                    Circle()
                        .fill(badgeColor.opacity(0.18))
                        .frame(width: 28, height: 28)

                    Image(systemName: badge.iconSystemName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(badgeColor)
                }
                .overlay(
                    Circle()
                        .stroke(badgeColor.opacity(0.4), lineWidth: 1)
                )

            case .full:
                HStack(spacing: 6) {
                    Image(systemName: badge.iconSystemName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(badgeColor)

                    Text(badge.name)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(YukiTheme.cardSurface)
                        .overlay(
                            Capsule()
                                .stroke(badgeColor.opacity(0.35), lineWidth: 1)
                        )
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Badge: \(badge.name), \(badge.description)")
        .popover(isPresented: $showInfo) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(badgeColor.opacity(0.2))
                        .frame(width: 50, height: 50)
                    Image(systemName: badge.iconSystemName)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(badgeColor)
                }

                Text(badge.name)
                    .font(.headline.weight(.bold))
                    .foregroundColor(.primary)

                Text(badge.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(16)
            .frame(width: 220)
            .presentationCompactAdaptation(.popover)
        }
    }
}

public struct BotTagView: View {
    public var isVerified: Bool = false

    public init(isVerified: Bool = false) {
        self.isVerified = isVerified
    }

    public var body: some View {
        HStack(spacing: 2) {
            if isVerified {
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .black))
            }
            Text("BOT")
                .font(.system(size: 9, weight: .heavy))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(red: 0.35, green: 0.40, blue: 0.95))
        )
        .accessibilityLabel(isVerified ? "Verified Bot" : "Bot")
    }
}

public struct StaffTagView: View {
    public init() {}

    public var body: some View {
        Image(systemName: "checkmark.shield.fill")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.orange)
            .accessibilityLabel("Stoat Staff")
    }
}
