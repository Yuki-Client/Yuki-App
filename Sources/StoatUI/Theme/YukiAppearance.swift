import SwiftUI
import UIKit
import StoatCore

@MainActor
@Observable
public final class YukiAppearance {
    public static let shared = YukiAppearance()

    public enum Scheme: String, CaseIterable, Identifiable, Sendable {
        case system, light, dark

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .system: "Automatic"
            case .light: "Light"
            case .dark: "Dark"
            }
        }
    }

    public static let defaultAccentHex = "#38B8FA"
    public static let palette = ["#38B8FA", "#5A6BFF", "#8B5CF6", "#EC4899", "#F43F5E", "#F59E0B", "#22C55E", "#14B8A6", "#94A3B8"]

    private static let schemeKey = "yuki.appearance.scheme"
    private static let accentKey = "yuki.appearance.accent"

    public var scheme: Scheme {
        didSet {
            UserDefaults.standard.set(scheme.rawValue, forKey: Self.schemeKey)
            applyToWindows()
        }
    }

    /// `preferredColorScheme` doesn't reach sheets that are already open, and can stick on dark
    /// after going back to Automatic.
    public func applyToWindows() {
        let style: UIUserInterfaceStyle = switch scheme {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
        for case let windowScene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in windowScene.windows where window.overrideUserInterfaceStyle != style {
                window.overrideUserInterfaceStyle = style
            }
        }
    }

    /// The accent as a hex string, so it can be stored and compared with the palette.
    public var accentHex: String {
        didSet { UserDefaults.standard.set(accentHex, forKey: Self.accentKey) }
    }

    public var accent: Color {
        Color(stoatColour: accentHex) ?? Color(red: 0.22, green: 0.72, blue: 0.98)
    }

    public var accentDeep: Color {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(accent).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return accent }
        return Color(uiColor: UIColor(hue: hue, saturation: min(1, saturation * 1.15), brightness: brightness * 0.72, alpha: alpha))
    }

    public var isDefaultAccent: Bool {
        accentHex.caseInsensitiveCompare(Self.defaultAccentHex) == .orderedSame
    }

    private init() {
        let defaults = UserDefaults.standard
        scheme = Scheme(rawValue: defaults.string(forKey: Self.schemeKey) ?? "") ?? .dark
        accentHex = defaults.string(forKey: Self.accentKey) ?? Self.defaultAccentHex
    }

    public func reset() {
        scheme = .dark
        accentHex = Self.defaultAccentHex
    }

    public static func hex(from color: Color) -> String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "#%02X%02X%02X", Int(round(red * 255)), Int(round(green * 255)), Int(round(blue * 255)))
    }
}
