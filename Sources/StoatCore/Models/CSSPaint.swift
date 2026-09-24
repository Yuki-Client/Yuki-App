import Foundation

/// A Stoat role or masquerade colour: any CSS colour, or a CSS gradient (see `RE_COLOUR` in
/// stoatchat `server_members.rs`). Stoat for Web paints role names with the whole gradient.
public enum CSSPaint: Equatable, Sendable {
    case solid(RGBA)
    /// `angle` in CSS degrees: 0 points up, 90 right, 180 (the default) down.
    case linear(angle: Double, stops: [Stop])
    case radial(stops: [Stop])
    /// `angle` is where the sweep starts, in CSS degrees (`from 90deg`).
    case conic(angle: Double, stops: [Stop])

    public struct RGBA: Equatable, Sendable {
        public var red: Double
        public var green: Double
        public var blue: Double
        public var alpha: Double

        public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
            self.red = red
            self.green = green
            self.blue = blue
            self.alpha = alpha
        }
    }

    public struct Stop: Equatable, Sendable {
        public var color: RGBA
        /// 0...1; nil when the stop gave no position.
        public var location: Double?
    }

    /// The first colour, for places that can only show one (dots, inline mentions).
    public var primaryColor: RGBA {
        switch self {
        case .solid(let color): color
        case .linear(_, let stops), .radial(let stops), .conic(_, let stops): stops.first?.color ?? RGBA(red: 1, green: 1, blue: 1)
        }
    }

    /// Stop locations with gaps filled evenly between known positions, as CSS does.
    public static func resolvedLocations(_ stops: [Stop]) -> [Double] {
        guard !stops.isEmpty else { return [] }
        var locations = stops.map(\.location)
        if locations[0] == nil { locations[0] = 0 }
        if locations[locations.count - 1] == nil { locations[locations.count - 1] = 1 }
        var index = 0
        while index < locations.count {
            guard locations[index] == nil else {
                index += 1
                continue
            }
            let start = index - 1
            var end = index
            while locations[end] == nil { end += 1 }
            let from = locations[start]!, to = locations[end]!
            for gap in index..<end {
                locations[gap] = from + (to - from) * Double(gap - start) / Double(end - start)
            }
            index = end
        }
        return locations.map { min(max($0!, 0), 1) }
    }

    public init?(css raw: String?) {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let lower = raw.lowercased()

        guard let open = lower.firstIndex(of: "("), lower.hasSuffix(")"), lower.contains("gradient(") else {
            guard let color = Self.color(lower) else { return nil }
            self = .solid(color)
            return
        }

        let kind = String(lower[..<open]).replacingOccurrences(of: "repeating-", with: "")
        let inner = String(lower[lower.index(after: open)..<lower.index(before: lower.endIndex)])
        var parts = Self.splitTopLevel(inner)
        guard !parts.isEmpty else { return nil }

        // The first part is either configuration (an angle, a direction, a shape) or a colour stop.
        var angle: Double?
        if Self.stop(parts[0]) == nil {
            angle = Self.angle(fromConfiguration: parts.removeFirst(), kind: kind)
        }
        let stops = parts.compactMap(Self.stop)
        guard !stops.isEmpty else { return nil }
        if stops.count == 1 {
            self = .solid(stops[0].color)
            return
        }

        switch kind {
        case "linear-gradient": self = .linear(angle: angle ?? 180, stops: stops)
        case "radial-gradient": self = .radial(stops: stops)
        case "conic-gradient": self = .conic(angle: angle ?? 0, stops: stops)
        default: return nil
        }
    }

    /// Splits on commas that aren't inside parentheses, e.g. in `rgb(1, 2, 3)`.
    private static func splitTopLevel(_ text: String) -> [String] {
        var parts: [String] = []
        var depth = 0
        var current = ""
        for character in text {
            switch character {
            case "(": depth += 1; current.append(character)
            case ")": depth -= 1; current.append(character)
            case "," where depth == 0:
                parts.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            default: current.append(character)
            }
        }
        let last = current.trimmingCharacters(in: .whitespaces)
        if !last.isEmpty { parts.append(last) }
        return parts
    }

    private static func angle(fromConfiguration text: String, kind: String) -> Double? {
        // Drop colour interpolation hints like "in oklab" or "in hsl longer hue".
        let text = text.components(separatedBy: " in ").first ?? text
        if let match = text.range(of: #"-?\d+(\.\d+)?deg"#, options: .regularExpression) {
            return Double(text[match].dropLast(3))
        }
        let directions: [String: Double] = [
            "to top": 0, "to top right": 45, "to right top": 45, "to right": 90,
            "to bottom right": 135, "to right bottom": 135, "to bottom": 180,
            "to bottom left": 225, "to left bottom": 225, "to left": 270,
            "to top left": 315, "to left top": 315
        ]
        return directions[text.trimmingCharacters(in: .whitespaces)]
    }

    private static func stop(_ text: String) -> Stop? {
        var colorText = text
        var location: Double?
        if let match = text.range(of: #"\s+(\d{1,3}(\.\d+)?%|0)$"#, options: .regularExpression) {
            let value = text[match].trimmingCharacters(in: .whitespaces)
            location = value == "0" ? 0 : Double(value.dropLast()).map { $0 / 100 }
            colorText = String(text[..<match.lowerBound])
        }
        guard let color = color(colorText) else { return nil }
        return Stop(color: color, location: location)
    }

    static func color(_ text: String) -> RGBA? {
        let text = text.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") {
            return hex(String(text.dropFirst()))
        }
        if text.hasPrefix("rgb"), let open = text.firstIndex(of: "("), text.hasSuffix(")") {
            let values = text[text.index(after: open)..<text.index(before: text.endIndex)]
                .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
                .compactMap { Double($0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "")) }
            guard values.count >= 3 else { return nil }
            let alpha = values.count >= 4 ? (values[3] > 1 ? values[3] / 100 : values[3]) : 1
            return RGBA(red: values[0] / 255, green: values[1] / 255, blue: values[2] / 255, alpha: alpha)
        }
        if text.hasPrefix("var(") {
            // Theme variables from Stoat for Web; the closest stand-in is the accent colour.
            return RGBA(red: 0.22, green: 0.72, blue: 0.98)
        }
        return named[text.replacingOccurrences(of: " ", with: "")]
    }

    private static func hex(_ digits: String) -> RGBA? {
        guard digits.allSatisfy(\.isHexDigit), let value = UInt64(digits, radix: 16) else { return nil }
        switch digits.count {
        case 3:
            return RGBA(red: Double(value >> 8 & 0xF) / 15, green: Double(value >> 4 & 0xF) / 15, blue: Double(value & 0xF) / 15)
        case 4:
            return RGBA(red: Double(value >> 12 & 0xF) / 15, green: Double(value >> 8 & 0xF) / 15, blue: Double(value >> 4 & 0xF) / 15, alpha: Double(value & 0xF) / 15)
        case 6:
            return RGBA(red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
        case 8:
            // CSS order is RRGGBBAA.
            return RGBA(red: Double(value >> 24 & 0xFF) / 255, green: Double(value >> 16 & 0xFF) / 255, blue: Double(value >> 8 & 0xFF) / 255, alpha: Double(value & 0xFF) / 255)
        default:
            return nil
        }
    }

    private static let named: [String: RGBA] = {
        let table: [String: UInt32] = [
            "black": 0x000000, "white": 0xFFFFFF, "red": 0xFF0000, "green": 0x008000, "lime": 0x00FF00,
            "blue": 0x0000FF, "yellow": 0xFFFF00, "cyan": 0x00FFFF, "aqua": 0x00FFFF, "magenta": 0xFF00FF,
            "fuchsia": 0xFF00FF, "orange": 0xFFA500, "purple": 0x800080, "pink": 0xFFC0CB, "gray": 0x808080,
            "grey": 0x808080, "silver": 0xC0C0C0, "maroon": 0x800000, "navy": 0x000080, "teal": 0x008080,
            "olive": 0x808000, "brown": 0xA52A2A, "gold": 0xFFD700, "indigo": 0x4B0082, "violet": 0xEE82EE,
            "coral": 0xFF7F50, "crimson": 0xDC143C, "salmon": 0xFA8072, "tomato": 0xFF6347, "turquoise": 0x40E0D0,
            "orchid": 0xDA70D6, "plum": 0xDDA0DD, "lavender": 0xE6E6FA, "khaki": 0xF0E68C, "tan": 0xD2B48C,
            "skyblue": 0x87CEEB, "hotpink": 0xFF69B4, "deeppink": 0xFF1493, "royalblue": 0x4169E1,
            "dodgerblue": 0x1E90FF, "limegreen": 0x32CD32, "seagreen": 0x2E8B57, "chartreuse": 0x7FFF00,
            "mediumpurple": 0x9370DB, "rebeccapurple": 0x663399, "slateblue": 0x6A5ACD, "steelblue": 0x4682B4,
            "darkred": 0x8B0000, "darkblue": 0x00008B, "darkgreen": 0x006400, "darkorange": 0xFF8C00,
            "lightblue": 0xADD8E6, "lightgreen": 0x90EE90, "lightpink": 0xFFB6C1, "mintcream": 0xF5FFFA,
            "transparent": 0x000000
        ]
        var result: [String: RGBA] = [:]
        for (name, value) in table {
            result[name] = RGBA(
                red: Double(value >> 16 & 0xFF) / 255,
                green: Double(value >> 8 & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255,
                alpha: name == "transparent" ? 0 : 1
            )
        }
        return result
    }()
}
