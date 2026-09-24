import SwiftUI
import StoatCore
import StoatState

struct PermissionSections: View {
    enum Style {
        case toggles
        case overrides
    }

    let context: PermissionContext
    let style: Style
    @Binding var value: PermissionOverrideValue
    /// Permissions the current user holds, and so may change.
    let grantable: Permission
    var isEditable = true

    var body: some View {
        ForEach(PermissionCatalog.groups) { group in
            let entries = group.entries.filter { $0.description(for: context) != nil }
            if !entries.isEmpty {
                Section(group.title) {
                    ForEach(entries) { entry in
                        row(entry)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ entry: PermissionEntry) -> some View {
        let enabled = isEditable && grantable.contains(entry.permission)
        let description = entry.description(for: context) ?? ""
        switch style {
        case .toggles:
            Toggle(isOn: Binding(
                get: { value.state(of: entry.permission) == .allow },
                set: { value.set(entry.permission, to: $0 ? .allow : .neutral) }
            )) {
                PermissionLabel(title: entry.title, description: description, isLocked: isEditable && !enabled)
            }
            .disabled(!enabled)
        case .overrides:
            HStack(spacing: 12) {
                PermissionLabel(title: entry.title, description: description, isLocked: isEditable && !enabled)
                Spacer(minLength: 8)
                OverrideStateControl(state: Binding(
                    get: { value.state(of: entry.permission) },
                    set: { value.set(entry.permission, to: $0) }
                ))
            }
            .disabled(!enabled)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(entry.title)
            .accessibilityHint(description)
            .accessibilityValue(OverrideStateControl.label(for: value.state(of: entry.permission)))
            .accessibilityAdjustableAction { direction in
                guard enabled else { return }
                let order: [OverrideState] = [.deny, .neutral, .allow]
                let index = order.firstIndex(of: value.state(of: entry.permission)) ?? 1
                let next = direction == .increment ? min(index + 1, 2) : max(index - 1, 0)
                value.set(entry.permission, to: order[next])
            }
        }
    }
}

private struct PermissionLabel: View {
    let title: String
    let description: String
    let isLocked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(title)
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("You don't have this permission")
                }
            }
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct OverrideStateControl: View {
    @Binding var state: OverrideState
    @Environment(\.isEnabled) private var isEnabled

    static func label(for state: OverrideState) -> String {
        switch state {
        case .allow: "Allowed"
        case .neutral: "Inherited"
        case .deny: "Denied"
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            segment(.deny, symbol: "xmark", tint: .red)
            segment(.neutral, symbol: "minus", tint: Color(.systemGray))
            segment(.allow, symbol: "checkmark", tint: .green)
        }
        .padding(2)
        .background(Capsule().fill(Color(.tertiarySystemFill)))
        .opacity(isEnabled ? 1 : 0.5)
    }

    private func segment(_ value: OverrideState, symbol: String, tint: Color) -> some View {
        let selected = state == value
        return Button {
            guard state != value else { return }
            YukiHaptics.selection()
            state = value
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(selected ? Color.white : Color.secondary)
                .frame(width: 32, height: 26)
                .background(Capsule().fill(selected ? tint : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.borderless)
    }
}
