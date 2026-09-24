import SwiftUI
import UIKit
import StoatCore

public struct YukiTheme {
    @MainActor public static var accent: Color { YukiAppearance.shared.accent }
    @MainActor public static var accentDeep: Color { YukiAppearance.shared.accentDeep }
    public static var cardSurface: Color {
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .light
                ? UIColor(red: 0.93, green: 0.94, blue: 0.96, alpha: 1.0)
                : UIColor(red: 0.14, green: 0.16, blue: 0.21, alpha: 1.0)
        })
    }

    public static let cornerRadiusMedium: CGFloat = 12
    public static let cornerRadiusSmall: CGFloat = 8

    public static var systemBackground: Color {
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .light ? .systemBackground : UIColor(red: 0.06, green: 0.07, blue: 0.09, alpha: 1.0)
        })
    }

    public static var secondaryBackground: Color {
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .light ? .secondarySystemBackground : UIColor(red: 0.10, green: 0.11, blue: 0.15, alpha: 1.0)
        })
    }

    public static var tertiaryBackground: Color {
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .light ? .tertiarySystemBackground : UIColor(red: 0.14, green: 0.16, blue: 0.21, alpha: 1.0)
        })
    }

    public static var groupedBackground: Color {
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .light ? .systemGroupedBackground : UIColor(red: 0.04, green: 0.05, blue: 0.07, alpha: 1.0)
        })
    }
}

public extension Color {
    /// A Stoat role colour as a single colour. Gradients use their first stop; see `stoatPaint(_:)`
    /// to draw the whole gradient.
    init?(stoatColour raw: String?) {
        guard let paint = CSSPaint(css: raw) else { return nil }
        self.init(rgba: paint.primaryColor)
    }

    init(rgba: CSSPaint.RGBA) {
        self.init(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }

    init(hex: String) {
        let cleanHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch cleanHex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 200, 200, 200)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

public extension ShapeStyle where Self == AnyShapeStyle {
    static func stoatPaint(_ raw: String?) -> AnyShapeStyle? {
        guard let paint = CSSPaint(css: raw) else { return nil }
        func gradient(_ stops: [CSSPaint.Stop]) -> Gradient {
            let locations = CSSPaint.resolvedLocations(stops)
            return Gradient(stops: zip(stops, locations).map { Gradient.Stop(color: Color(rgba: $0.color), location: $1) })
        }
        switch paint {
        case .solid(let color):
            return AnyShapeStyle(Color(rgba: color))
        case .linear(let angle, let stops):
            let radians = angle * .pi / 180
            let dx = sin(radians) / 2, dy = -cos(radians) / 2
            return AnyShapeStyle(LinearGradient(
                gradient: gradient(stops),
                startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy),
                endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy)
            ))
        case .radial(let stops):
            return AnyShapeStyle(EllipticalGradient(gradient: gradient(stops)))
        case .conic(let angle, let stops):
            // CSS conic gradients start at the top; SwiftUI's start at the trailing edge.
            return AnyShapeStyle(AngularGradient(gradient: gradient(stops), center: .center, angle: .degrees(angle - 90)))
        }
    }
}
