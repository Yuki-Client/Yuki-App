import SwiftUI
import StoatCore

struct RoleColourPicker: View {
    @Binding var colour: String?
    var previewName = "Role"

    private enum Style: String, CaseIterable {
        case solid = "Solid"
        case gradient = "Gradient"
    }

    private static let directions: [(label: String, angle: Int)] = [
        ("Left to Right", 90), ("Top to Bottom", 180), ("Diagonal Down", 135), ("Diagonal Up", 45)
    ]

    private static let palette: [String] = [
        "#fca5a5", "#fdba74", "#fcd34d", "#86efac", "#6ee7b7", "#67e8f9", "#93c5fd", "#c4b5fd", "#f0abfc", "#f9a8d4", "#cbd5e1",
        "#ef4444", "#f97316", "#f59e0b", "#22c55e", "#10b981", "#06b6d4", "#3b82f6", "#8b5cf6", "#d946ef", "#ec4899", "#64748b",
        "#991b1b", "#9a3412", "#92400e", "#166534", "#065f46", "#155e75", "#1e40af", "#5b21b6", "#86198f", "#9d174d", "#1e293b"
    ]

    @Environment(\.isEnabled) private var isEnabled
    @State private var style: Style = .solid

    private var paint: CSSPaint? { CSSPaint(css: colour) }

    private var isGradient: Bool {
        if case .solid = paint { return false }
        return paint != nil
    }

    private var isCustom: Bool {
        guard let colour, !isGradient else { return false }
        return !Self.palette.contains(colour.lowercased())
    }

    /// The two stops and angle of a simple linear gradient, or nil for anything Yuki can't edit.
    private var editableGradient: (start: Color, end: Color, angle: Int)? {
        guard case .linear(let angle, let stops) = paint, stops.count == 2 else { return nil }
        return (Color(rgba: stops[0].color), Color(rgba: stops[1].color), Int(angle))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Style", selection: $style) {
                ForEach(Style.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: style) { _, newStyle in
                switch newStyle {
                case .gradient where !isGradient:
                    let start = Color(stoatColour: colour) ?? Color(hex: "#3b82f6")
                    setGradient(start: start, end: Color(hex: "#d946ef"), angle: 90)
                case .solid where isGradient:
                    colour = (Color(stoatColour: colour) ?? .white).hexString
                default:
                    break
                }
            }

            if style == .solid {
                solidControls
            } else {
                gradientControls
            }

            HStack {
                Text("Preview")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(previewName)
                    .font(.headline)
                    .foregroundStyle(AnyShapeStyle.stoatPaint(colour) ?? AnyShapeStyle(.primary))
                    .lineLimit(1)
            }

            if colour != nil {
                Button("Remove Colour", role: .destructive) {
                    colour = nil
                    style = .solid
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
        .opacity(isEnabled ? 1 : 0.6)
        .onAppear {
            style = isGradient ? .gradient : .solid
        }
    }

    private var solidControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 11), spacing: 6) {
                ForEach(Self.palette, id: \.self) { swatch in
                    let selected = colour?.lowercased() == swatch
                    Button {
                        YukiHaptics.selection()
                        colour = swatch
                    } label: {
                        Circle()
                            .fill(Color(hex: swatch))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay {
                                if selected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .heavy))
                                        .foregroundStyle(.white)
                                        .shadow(radius: 1)
                                }
                            }
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Colour \(swatch)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }

            ColorPicker(selection: Binding(
                get: { Color(stoatColour: colour) ?? .white },
                set: { colour = $0.hexString }
            ), supportsOpacity: false) {
                HStack(spacing: 8) {
                    Text("Custom")
                    if isCustom, let colour {
                        Text(colour.hasPrefix("#") ? colour.uppercased() : colour)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var gradientControls: some View {
        let current = editableGradient
        VStack(alignment: .leading, spacing: 12) {
            if isGradient, current == nil {
                Text("This role has a gradient Yuki can't edit. Changing it below replaces it with a two-colour gradient.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ColorPicker("Start Colour", selection: Binding(
                get: { current?.start ?? Color(stoatColour: colour) ?? .white },
                set: { setGradient(start: $0, end: current?.end ?? .white, angle: current?.angle ?? 90) }
            ), supportsOpacity: false)
            ColorPicker("End Colour", selection: Binding(
                get: { current?.end ?? .white },
                set: { setGradient(start: current?.start ?? .white, end: $0, angle: current?.angle ?? 90) }
            ), supportsOpacity: false)
            Picker("Direction", selection: Binding(
                get: { current?.angle ?? 90 },
                set: { setGradient(start: current?.start ?? .white, end: current?.end ?? .white, angle: $0) }
            )) {
                ForEach(Self.directions, id: \.angle) { direction in
                    Text(direction.label).tag(direction.angle)
                }
                if let angle = current?.angle, !Self.directions.contains(where: { $0.angle == angle }) {
                    Text("\(angle)°").tag(angle)
                }
            }
        }
    }

    /// Stoat accepts CSS gradients such as `linear-gradient(90deg, #ff0000, #0000ff)`.
    private func setGradient(start: Color, end: Color, angle: Int) {
        colour = "linear-gradient(\(angle)deg, \(start.hexString), \(end.hexString))"
    }
}
