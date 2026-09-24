import SwiftUI

struct NSFWGateView: View {
    let channelName: String
    let onConfirm: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Mature Content", systemImage: "exclamationmark.shield.fill")
        } description: {
            Text("\(channelName) may contain content not suitable for everyone. You must be 18 or older to view it.")
        } actions: {
            Button("I'm 18 or older, continue", action: onConfirm)
                .buttonStyle(.borderedProminent)
        }
    }
}
