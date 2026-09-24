import SwiftUI

/// Tracks how far the flipped chat scroll view is from the newest message (iOS 18+).
struct BottomDistanceTracking: ViewModifier {
    @Binding var isAtBottom: Bool
    @Binding var isNearBottom: Bool

    private enum Distance: Equatable {
        case atBottom
        case near
        case far
    }

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: Distance.self) { geometry in
                // The content is flipped, so offset zero is the newest message.
                let distance = geometry.contentOffset.y + geometry.contentInsets.top
                if distance < 120 { return .atBottom }
                return distance < geometry.containerSize.height * 3 ? .near : .far
            } action: { _, distance in
                isAtBottom = distance == .atBottom
                isNearBottom = distance != .far
            }
        } else {
            content
        }
    }
}

/// iOS 17 has no scroll geometry callback, so fall back to watching a marker row at the newest end.
struct LegacyBottomSentinel: ViewModifier {
    @Binding var isAtBottom: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
        } else {
            content
                .onAppear { isAtBottom = true }
                .onDisappear { isAtBottom = false }
        }
    }
}

extension View {
    /// Flips content vertically; applied to a scroll view and again to each row so rows read upright.
    func flippedForChat() -> some View {
        scaleEffect(x: 1, y: -1, anchor: .center)
    }

    /// iOS 26 blurs scroll content near bars; on a flipped scroll view that blur covers the whole feed.
    @ViewBuilder
    func hidingScrollEdgeEffects() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectHidden(true, for: .all)
        } else {
            self
        }
    }
}
