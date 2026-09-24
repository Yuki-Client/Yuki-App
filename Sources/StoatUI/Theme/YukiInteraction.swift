import SwiftUI
import UIKit

public enum YukiHaptics {
    public typealias ImpactStyle = UIImpactFeedbackGenerator.FeedbackStyle
    public typealias NotificationType = UINotificationFeedbackGenerator.FeedbackType

    public static let enabledKey = "yuki.haptics"

    public static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    @MainActor
    public static func impact(_ style: ImpactStyle = .light) {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    @MainActor
    public static func selection() {
        guard isEnabled else { return }
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    @MainActor
    public static func notification(_ type: NotificationType) {
        guard isEnabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
}

/// Whether Yuki plays its own transitions, such as sliding between channels. On unless turned
/// off in Settings, and always off when iOS's Reduce Motion is on.
public enum YukiMotion {
    public static let enabledKey = "yuki.animations"

    public static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    @MainActor
    public static func transition(reduceMotion: Bool, enabled: Bool) -> Animation? {
        guard enabled, !reduceMotion else { return nil }
        return .easeOut(duration: 0.22)
    }
}

/// Remembers when a screen-wide swipe happened (going back, opening the member list), so taps
/// that land under the finger during or just after it are ignored instead of opening something.
@MainActor
public enum YukiSwipeGuard {
    private static var lastSwipe = Date.distantPast
    /// Long enough to cover the finger lifting at the end of a swipe.
    private static let quietPeriod: TimeInterval = 0.4

    public static func noteSwiping() {
        lastSwipe = Date()
    }

    public static var acceptsTaps: Bool {
        Date().timeIntervalSince(lastSwipe) > quietPeriod
    }
}

public struct YukiPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(YukiMotion.enabledKey) private var animationsEnabled = true

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        let shouldMove = animationsEnabled && !reduceMotion
        return configuration.label
            .scaleEffect(configuration.isPressed && shouldMove ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

public extension View {
    func yukiPop<V: Equatable>(on value: V) -> some View {
        modifier(YukiPopModifier(value: value))
    }
}

private struct YukiPopModifier<V: Equatable>: ViewModifier {
    let value: V

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(YukiMotion.enabledKey) private var animationsEnabled = true
    @State private var popped = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(popped ? 1.18 : 1)
            .onChange(of: value) { _, _ in
                guard animationsEnabled, !reduceMotion else { return }
                withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) { popped = true }
                Task {
                    try? await Task.sleep(for: .milliseconds(140))
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.7)) { popped = false }
                }
            }
    }
}
