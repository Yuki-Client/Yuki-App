import SwiftUI
import StoatCore

public struct StatusBadge: View {
    public let presence: Presence?
    public let size: CGFloat

    public init(presence: Presence?, size: CGFloat = 12) {
        self.presence = presence
        self.size = size
    }

    public var body: some View {
        // A shape per status as well as a colour, so it reads without telling colours apart.
        mark
            .frame(width: size * 0.8, height: size * 0.8)
            .frame(width: size, height: size)
            .background(Circle().fill(YukiTheme.systemBackground))
            .accessibilityLabel(StatusBadge.label(for: presence))
    }

    @ViewBuilder
    private var mark: some View {
        let color = StatusBadge.color(for: presence)
        switch presence {
        case .online:
            Circle().fill(color)
        case .idle:
            Image(systemName: "moon.fill").resizable().scaledToFit().foregroundStyle(color)
        case .busy:
            Image(systemName: "minus.circle.fill").resizable().scaledToFit().foregroundStyle(color)
        case .focus:
            Image(systemName: "circle.circle.fill").resizable().scaledToFit().foregroundStyle(color)
        case .invisible, .none:
            Circle().strokeBorder(color, lineWidth: max(1.5, size * 0.2))
        }
    }

    public static func color(for presence: Presence?) -> Color {
        switch presence {
        case .online: return .green
        case .idle: return .orange
        case .busy: return .red
        case .focus: return .blue
        case .invisible, .none: return .gray
        }
    }

    public static func label(for presence: Presence?) -> String {
        switch presence {
        case .online: return "Online"
        case .idle: return "Idle"
        case .busy: return "Do Not Disturb"
        case .focus: return "Focus"
        case .invisible, .none: return "Offline"
        }
    }
}
