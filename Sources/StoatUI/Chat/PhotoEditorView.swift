import SwiftUI
import SwiftyCrop
import UIKit
import StoatState

struct PhotoEditorView: View {
    let attachment: OutgoingAttachment
    let limit: Int
    let onSave: (OutgoingAttachment) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image = UIImage(data: attachment.data) {
                SwiftyCropView(
                    imageToCrop: image,
                    maskShape: .rectangle,
                    configuration: SwiftyCropConfiguration(
                        maxMagnificationScale: 8,
                        maskRadius: 500,
                        rotateImage: true,
                        rotateImageWithButtons: true,
                        showsZoomSlider: true,
                        rectAspectRatio: image.size.width / max(image.size.height, 1),
                        allowAspectRatioResizing: true,
                        texts: SwiftyCropConfiguration.Texts(
                            cancelButton: "Cancel",
                            interactionInstructions: "Pinch, drag and rotate",
                            saveButton: "Done"
                        )
                    ),
                    onCancel: { dismiss() },
                    onComplete: { cropped in
                        guard let cropped else {
                            dismiss()
                            return
                        }
                        save(cropped)
                    }
                )
            } else {
                ContentUnavailableView("Can't edit this photo", systemImage: "photo")
                    .onAppear { dismiss() }
            }
            if isSaving {
                Color.black.opacity(0.4).ignoresSafeArea()
                ProgressView().tint(.white)
            }
        }
        .statusBarHidden()
    }

    private func save(_ image: UIImage) {
        isSaving = true
        Task {
            // Re-encoded like picked photos so it still fits Stoat's size limit.
            if let data = image.jpegData(compressionQuality: 0.92),
               let edited = try? await AttachmentPreparation.image(data: data, type: .jpeg, limit: limit) {
                onSave(edited)
            }
            isSaving = false
            dismiss()
        }
    }
}
