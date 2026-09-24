import SwiftUI
import StoatCore

struct AppearanceSettingsView: View {
    @State private var appearance = YukiAppearance.shared

    private let columns = [GridItem(.adaptive(minimum: 52), spacing: 14)]

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: Binding(get: { appearance.scheme }, set: { appearance.scheme = $0 })) {
                    ForEach(YukiAppearance.Scheme.allCases) { scheme in
                        Text(scheme.title).tag(scheme)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            } footer: {
                Text("Automatic follows your iPhone's light or dark setting.")
            }

            Section("Accent") {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(YukiAppearance.palette, id: \.self) { hex in
                        let isSelected = appearance.accentHex.caseInsensitiveCompare(hex) == .orderedSame
                        Button {
                            YukiHaptics.selection()
                            appearance.accentHex = hex
                        } label: {
                            Circle()
                                .fill(Color(stoatColour: hex) ?? .gray)
                                .frame(width: 44, height: 44)
                                .overlay {
                                    if isSelected {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .overlay(Circle().stroke(Color.primary.opacity(isSelected ? 0.8 : 0.1), lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(name(for: hex))
                        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .padding(.vertical, 6)

                ColorPicker("Custom Colour", selection: Binding(
                    get: { appearance.accent },
                    set: { appearance.accentHex = YukiAppearance.hex(from: $0) }
                ), supportsOpacity: false)
            }

            Section {
                preview
            } header: {
                Text("Preview")
            } footer: {
                Text("Yuki's colours only change on this device; they aren't shared with Stoat for Web.")
            }

            if appearance.scheme != .dark || !appearance.isDefaultAccent {
                Section {
                    Button("Reset to Yuki's Look", role: .destructive) {
                        appearance.reset()
                    }
                }
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(LinearGradient(colors: [YukiTheme.accent, YukiTheme.accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 34, height: 34)
                    .overlay(Image(systemName: "snowflake").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Yuki")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(YukiTheme.accent)
                    Text("This is how messages look.")
                        .font(.subheadline)
                }
            }
            HStack(spacing: 8) {
                Text("#general")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(YukiTheme.accent.opacity(0.18)))
                    .foregroundStyle(YukiTheme.accent)
                MentionBadge(count: 3)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(YukiTheme.cardSurface))
        .accessibilityElement(children: .combine)
    }

    private func name(for hex: String) -> String {
        switch hex {
        case "#38B8FA": "Arctic (Yuki)"
        case "#5A6BFF": "Indigo"
        case "#8B5CF6": "Violet"
        case "#EC4899": "Pink"
        case "#F43F5E": "Rose"
        case "#F59E0B": "Amber"
        case "#22C55E": "Green"
        case "#14B8A6": "Teal"
        default: "Grey"
        }
    }
}
