import SwiftUI

struct RoleColourDot: View {
    let colour: String?
    var size: CGFloat = 14

    var body: some View {
        if let paint = AnyShapeStyle.stoatPaint(colour) {
            Circle().fill(paint).frame(width: size, height: size)
        } else {
            Circle()
                .strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                .frame(width: size, height: size)
        }
    }
}
