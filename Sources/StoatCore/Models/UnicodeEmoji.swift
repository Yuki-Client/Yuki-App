import Foundation

/// Unicode emoji handling that follows Stoat for Web's emoji renderer.
public enum UnicodeEmoji {
    /// Stoat for Web puts one of U+E0E0–U+E0E6 in front of an emoji to pick the pack it's drawn
    /// from. iOS has no glyph for them, so they're dropped and the system emoji shown instead.
    private static let packMarkers: ClosedRange<UInt32> = 0xE0E0...0xE0E6

    public static func removingPackMarkers(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { packMarkers.contains($0.value) }) else { return text }
        let scalars = Array(text.unicodeScalars)
        var result = String.UnicodeScalarView()
        for (index, scalar) in scalars.enumerated() {
            if packMarkers.contains(scalar.value), index + 1 < scalars.count, startsEmoji(scalars[index + 1]) {
                continue
            }
            result.append(scalar)
        }
        return String(result)
    }

    private static func startsEmoji(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isEmojiPresentation || (scalar.properties.isEmoji && !scalar.isASCII)
    }

    private static let regionalIndicators: ClosedRange<UInt32> = 0x1F1E6...0x1F1FF

    public static func isRegionalIndicator(_ scalar: Unicode.Scalar) -> Bool {
        regionalIndicators.contains(scalar.value)
    }

    /// The letter a regional indicator stands for, A to Z.
    public static func letter(of scalar: Unicode.Scalar) -> Character? {
        guard isRegionalIndicator(scalar), let letter = Unicode.Scalar(scalar.value - 0x1F1E6 + 0x41) else { return nil }
        return Character(letter)
    }

    public enum Piece: Equatable, Sendable {
        case text(String)
        /// A regional indicator that isn't half of a flag, which iOS draws as a dashed box.
        case letter(Character)
    }

    /// The letters to draw as tiles when `character` is a regional indicator on its own, or a
    /// pair that isn't a flag. Empty for anything else, real flags included.
    public static func loneRegionalIndicatorLetters(in character: Character) -> [Character] {
        let scalars = Array(character.unicodeScalars)
        guard (1...2).contains(scalars.count), scalars.allSatisfy(isRegionalIndicator) else { return [] }
        if scalars.count == 2, isFlag(scalars[0], scalars[1]) { return [] }
        return scalars.compactMap(letter(of:))
    }

    /// Splits text so regional indicators that don't make a flag can be drawn as letter tiles,
    /// as Stoat for Web does.
    public static func splittingLoneRegionalIndicators(_ text: String) -> [Piece] {
        guard text.unicodeScalars.contains(where: isRegionalIndicator) else { return [.text(text)] }
        var pieces: [Piece] = []
        var run = ""
        for character in text {
            let letters = loneRegionalIndicatorLetters(in: character)
            if letters.isEmpty {
                run.append(character)
                continue
            }
            if !run.isEmpty {
                pieces.append(.text(run))
                run = ""
            }
            pieces.append(contentsOf: letters.map(Piece.letter))
        }
        if !run.isEmpty { pieces.append(.text(run)) }
        return pieces
    }

    private static let flagRegions: Set<String> = {
        var codes = Set(Locale.Region.isoRegions.map(\.identifier).filter { $0.count == 2 })
        // Flags with an emoji that aren't countries.
        codes.formUnion(["EU", "UN", "AC", "CP", "DG", "EA", "IC", "TA", "XK"])
        return codes
    }()

    private static func isFlag(_ first: Unicode.Scalar, _ second: Unicode.Scalar) -> Bool {
        guard let a = letter(of: first), let b = letter(of: second) else { return false }
        return flagRegions.contains("\(a)\(b)")
    }
}
