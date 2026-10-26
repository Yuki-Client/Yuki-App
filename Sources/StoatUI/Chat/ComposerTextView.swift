import SwiftUI
import UIKit

/// TextField sometimes ignored being cleared while the keyboard was mid-autocorrect, leaving text
/// behind with the send button greyed out. Using UITextView directly avoids that.
struct ComposerTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let placeholder: String
    var maxLines = 8
    /// Return true to throw away text the keyboard puts back after sending.
    var isLeftover: (_ old: String, _ new: String) -> Bool = { _, _ in false }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = .label
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 9, left: 0, bottom: 9, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false
        textView.returnKeyType = .default
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let placeholderLabel = UILabel()
        placeholderLabel.font = textView.font
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.isAccessibilityElement = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        textView.addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: textView.textContainerInset.top),
            placeholderLabel.widthAnchor.constraint(lessThanOrEqualTo: textView.widthAnchor)
        ])
        context.coordinator.placeholderLabel = placeholderLabel

        textView.text = text
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        textView.tintColor = UIColor(YukiTheme.accent)
        textView.accessibilityLabel = placeholder

        if textView.text != text {
            // Don't let these come back through the delegate as typing.
            context.coordinator.isSettingText = true
            defer { context.coordinator.isSettingText = false }
            if text.isEmpty {
                // Commit any half-typed word first so the keyboard has nothing left to finish.
                textView.unmarkText()
                textView.text = ""
            } else if textView.markedTextRange == nil {
                // Skipped mid-composition so it doesn't break IME input.
                textView.text = text
            }
            context.coordinator.textDidChange(in: textView)
        }
        context.coordinator.updatePlaceholder(in: textView)

        if isFocused, !textView.isFirstResponder {
            // Async because this reports focus back straight away, which can't happen mid-update.
            DispatchQueue.main.async { textView.becomeFirstResponder() }
        } else if !isFocused, textView.isFirstResponder {
            DispatchQueue.main.async { textView.resignFirstResponder() }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView textView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? textView.bounds.width
        guard width > 0 else { return nil }
        let fitting = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let lineHeight = textView.font?.lineHeight ?? 20
        let maxHeight = lineHeight * CGFloat(maxLines) + textView.textContainerInset.top + textView.textContainerInset.bottom
        return CGSize(width: width, height: min(fitting.height, maxHeight).rounded(.up))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ComposerTextView
        weak var placeholderLabel: UILabel?
        var isSettingText = false

        init(_ parent: ComposerTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isSettingText else { return }
            let new = textView.text ?? ""
            if parent.isLeftover(parent.text, new) {
                // Wait for the keyboard to finish or it puts the text back again.
                DispatchQueue.main.async { [weak self] in
                    // They've started typing again, so leave it.
                    guard textView.text == new else { return }
                    self?.isSettingText = true
                    textView.unmarkText()
                    textView.text = ""
                    self?.isSettingText = false
                    self?.textDidChange(in: textView)
                }
                return
            }
            if parent.text != new {
                parent.text = new
            }
            textDidChange(in: textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFocused { parent.isFocused = true }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isFocused { parent.isFocused = false }
        }

        func textDidChange(in textView: UITextView) {
            updatePlaceholder(in: textView)
            let lineHeight = textView.font?.lineHeight ?? 20
            let maxHeight = lineHeight * CGFloat(parent.maxLines) + textView.textContainerInset.top + textView.textContainerInset.bottom
            let fitting = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude))
            textView.isScrollEnabled = textView.bounds.width > 0 && fitting.height > maxHeight
            textView.invalidateIntrinsicContentSize()
        }

        func updatePlaceholder(in textView: UITextView) {
            placeholderLabel?.text = parent.placeholder
            placeholderLabel?.isHidden = !textView.text.isEmpty
        }
    }
}
