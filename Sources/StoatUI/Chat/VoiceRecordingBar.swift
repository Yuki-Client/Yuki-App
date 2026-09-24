import SwiftUI
import StoatState

struct VoiceRecordingBar: View {
    let recorder: VoiceRecorder
    let onDiscard: () -> Void
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onDiscard) {
                Image(systemName: "trash.fill")
                    .foregroundColor(.red)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.red.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Discard recording")

            Circle().fill(Color.red).frame(width: 8, height: 8)
            Text(String(format: "%d:%02d", Int(recorder.duration) / 60, Int(recorder.duration) % 60))
                .font(.system(.footnote, design: .monospaced).weight(.semibold))

            HStack(spacing: 2) {
                ForEach(Array(recorder.audioLevels.enumerated()), id: \.offset) { _, level in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(YukiTheme.accent)
                        .frame(width: 3, height: max(4, level * 26))
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)

            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(YukiTheme.accent)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Send voice message")
        }
    }
}
