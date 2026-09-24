import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var currentPoint = CGPoint.zero
        var lineHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentPoint.x + size.width > width && currentPoint.x > 0 {
                currentPoint.x = 0
                currentPoint.y += lineHeight + spacing
                lineHeight = 0
            }
            currentPoint.x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxWidth = max(maxWidth, currentPoint.x - spacing)
        }

        return CGSize(width: proposal.width == nil ? maxWidth : width, height: currentPoint.y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentPoint = CGPoint(x: bounds.minX, y: bounds.minY)
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentPoint.x + size.width > bounds.maxX && currentPoint.x > bounds.minX {
                currentPoint.x = bounds.minX
                currentPoint.y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: currentPoint, proposal: ProposedViewSize(size))
            currentPoint.x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
