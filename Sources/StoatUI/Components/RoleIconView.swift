import SwiftUI
import StoatCore

/// A role's icon, drawn as a small rounded square like Stoat for Web.
struct RoleIconView: View {
    let icon: Attachment
    let roleName: String
    var size: CGFloat = 16

    var body: some View {
        RemoteImage(url: icon.downloadURL(), maxPixelSize: size * 3, animates: true, animatedContentMode: .scaleAspectFit) { image in
            image.resizable().scaledToFit()
        } placeholder: { _ in
            Color.clear
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size / 4, style: .continuous))
        .accessibilityLabel(roleName)
    }
}

/// The role's icon if it has one, otherwise its colour.
struct RoleMarker: View {
    let role: Role
    var size: CGFloat = 14

    var body: some View {
        if let icon = role.icon {
            RoleIconView(icon: icon, roleName: role.name, size: size)
                .accessibilityHidden(true)
        } else {
            RoleColourDot(colour: role.colour, size: size)
        }
    }
}
