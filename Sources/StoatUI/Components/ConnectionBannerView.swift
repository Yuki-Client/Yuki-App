import SwiftUI
import StoatCore
import StoatState

public struct ConnectionBannerView: View {
    @Environment(AppStore.self) private var appStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        if appStore.connectionState != .authenticated && appStore.isLoggedIn {
            HStack(spacing: 10) {
                switch appStore.connectionState {
                case .connecting, .connected:
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.yellow)
                        .scaleEffect(0.85)

                    Text("Reconnecting to Stoat...")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.yellow)

                case .disconnected:
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)

                    Text("Disconnected from Stoat")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.secondary)

                    Spacer()

                    Button {
                        YukiHaptics.impact()
                        Task {
                            await appStore.reconnectGateway()
                        }
                    } label: {
                        Text("Retry")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(YukiTheme.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(YukiTheme.accent.opacity(0.18))
                                    .overlay(Capsule().stroke(YukiTheme.accent.opacity(0.35), lineWidth: 1))
                            )
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
                default:
                    EmptyView()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        appStore.connectionState == .disconnected ? Color.red.opacity(0.4) : Color.yellow.opacity(0.4),
                                        Color.white.opacity(0.08)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: appStore.connectionState)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(appStore.connectionState == .disconnected ? "Disconnected from Stoat. Double tap Retry to reconnect." : "Reconnecting to Stoat.")
        }
    }
}
