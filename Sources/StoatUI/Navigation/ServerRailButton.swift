import SwiftUI

enum RailCall { case active, joined }

struct ServerRailButton<Icon: View, MenuItems: View>: View {
    let title: String
    let isSelected: Bool
    let isUnread: Bool
    let mentionCount: Int
    var call: RailCall? = nil
    var dragId: String? = nil
    var onDrop: ((String) -> Bool)? = nil
    @ViewBuilder let icon: () -> Icon
    let action: () -> Void
    @ViewBuilder let menu: () -> MenuItems

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            Capsule()
                .fill(Color.primary)
                .frame(width: 4, height: isSelected ? 36 : (isUnread ? 8 : 0))
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: isSelected)

            Spacer(minLength: 0)

            Button {
                YukiHaptics.selection()
                action()
            } label: {
                icon()
                    .clipShape(RoundedRectangle(cornerRadius: isSelected ? 14 : 24, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        if mentionCount > 0 {
                            Text(mentionCount > 99 ? "99+" : "\(mentionCount)")
                                .font(.system(size: 11, weight: .bold).monospacedDigit())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .frame(minWidth: 18, minHeight: 18)
                                .background(Capsule().fill(Color.red))
                                .overlay(Capsule().stroke(YukiTheme.groupedBackground, lineWidth: 2))
                                .offset(x: 4, y: 4)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if let call {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(call == .joined ? .white : .green)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(call == .joined ? Color.green : YukiTheme.cardSurface))
                                .overlay(Circle().stroke(YukiTheme.groupedBackground, lineWidth: 2))
                                .offset(x: 4, y: -4)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
                    .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: call)
            }
            .buttonStyle(YukiPressStyle())
            // On the icon rather than the whole row, which touches the screen edge and makes iOS
            // shift the lifted preview sideways.
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: isSelected ? 14 : 24, style: .continuous))
            .contextMenu { menu() }
            .modifier(RailDragAndDrop(id: dragId, onDrop: onDrop))

            Spacer(minLength: 0)
        }
        .frame(height: 52)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

extension ServerRailButton where MenuItems == EmptyView {
    init(title: String, isSelected: Bool, isUnread: Bool, mentionCount: Int, call: RailCall? = nil, @ViewBuilder icon: @escaping () -> Icon, action: @escaping () -> Void) {
        self.init(title: title, isSelected: isSelected, isUnread: isUnread, mentionCount: mentionCount, call: call, icon: icon, action: action) {
            EmptyView()
        }
    }
}

private struct RailDragAndDrop: ViewModifier {
    let id: String?
    let onDrop: ((String) -> Bool)?

    func body(content: Content) -> some View {
        if let id, let onDrop {
            content
                .draggable(id)
                .dropDestination(for: String.self) { ids, _ in
                    ids.first.map(onDrop) ?? false
                }
        } else {
            content
        }
    }
}

extension ServerRailButton {
    private var accessibilityValue: String {
        [
            mentionCount > 0 ? "\(mentionCount) mentions" : isUnread ? "Unread" : nil,
            call == .joined ? "You're in a call here" : call == .active ? "Call in progress" : nil
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}
