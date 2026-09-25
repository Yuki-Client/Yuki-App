import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import StoatCore
import StoatState
import StoatVoice

public struct MessageComposerView: View {
    @Bindable var store: AppStore
    public let channel: Channel
    @Binding var text: String

    @State private var attachments: [OutgoingAttachment] = []
    @State private var preparing: [PreparingAttachment] = []
    @State private var editingAttachment: OutgoingAttachment?
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var showFilePicker = false
    @State private var showEmojiPicker = false
    @State private var showGifPicker = false
    @State private var now = Date()
    @State private var voiceRecorder = VoiceRecorder()
    @State private var isRecording = false
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(store: AppStore, channel: Channel, text: Binding<String>) {
        self.store = store
        self.channel = channel
        self._text = text
    }

    private var permissions: Permission { store.store.permissions(in: channel) }
    private var isEditing: Bool { store.editingMessage != nil }

    private var attachmentLimit: Int {
        store.instanceConfiguration?.features.limits?.default?.messageAttachments ?? 5
    }

    private var messageLimit: Int {
        store.instanceConfiguration?.features.limits?.default?.messageLength ?? 2000
    }

    private var placeholder: String {
        if isEditing { return "Edit message" }
        switch channel.channelType {
        case .textChannel: return "Message #\(channel.name ?? "channel")"
        case .savedMessages: return "Save a note"
        default: return "Message \(channel.displayName(withUsers: store.store.users, currentUserId: store.store.currentUserId))"
        }
    }

    private var slowmodeRemaining: Int {
        isEditing ? 0 : store.slowmodeRemaining(channelId: channel.id, now: now)
    }

    private var canSend: Bool {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasText || (!attachments.isEmpty && !isEditing)) && text.count <= messageLimit && slowmodeRemaining == 0
            && (isEditing || preparing.isEmpty)
    }

    private var uploadLimit: Int {
        store.instanceConfiguration?.features.limits?.default?.fileUploadSizeLimits?["attachments"] ?? 20_000_000
    }

    @ViewBuilder
    private var slowmodeNotice: some View {
        let seconds = channel.slowmode ?? 0
        if seconds > 0, !store.store.hasPermission(.bypassSlowmode, in: channel) {
            HStack(spacing: 6) {
                Image(systemName: "timer")
                if slowmodeRemaining > 0 {
                    Text("Slowmode · you can send again in \(slowmodeRemaining)s")
                        .monospacedDigit()
                } else {
                    Text("Slowmode is on: one message every \(Channel.slowmodeLabel(seconds))")
                }
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        }
    }

    public var body: some View {
        VStack(spacing: 6) {
            if !suggestions.isEmpty {
                ComposerSuggestionList(store: store, serverId: channel.server, suggestions: suggestions, onSelect: apply)
            }

            slowmodeNotice

            if !attachments.isEmpty || !preparing.isEmpty {
                attachmentTray
            }

            if isRecording {
                VoiceRecordingBar(recorder: voiceRecorder) {
                    voiceRecorder.cancelRecording()
                    withAnimation { isRecording = false }
                } onSend: {
                    finishRecording(sendNow: true)
                }
            } else {
                inputBar
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(YukiTheme.systemBackground)
        .simultaneousGesture(
            DragGesture(minimumDistance: 20).onEnded { value in
                if value.translation.height > 30, abs(value.translation.width) < value.translation.height {
                    isFocused = false
                }
            }
        )
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $photoSelection,
            maxSelectionCount: max(1, attachmentLimit - attachments.count - preparing.count),
            matching: .any(of: [.images, .videos])
        )
        .onChange(of: photoSelection) { _, items in
            guard !items.isEmpty else { return }
            photoSelection = []
            Task { await loadPhotos(items) }
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                loadFiles(urls)
            }
        }
        .onDisappear {
            for item in preparing { item.task?.cancel() }
        }
        .fullScreenCover(item: $editingAttachment) { attachment in
            PhotoEditorView(attachment: attachment, limit: uploadLimit) { edited in
                replace(attachment, with: edited)
            }
        }
        .sheet(isPresented: $showEmojiPicker) {
            EmojiPickerSheet(sections: store.store.emojiSections(for: channel), title: "Emoji") { emoji in
                text += Emoji.isCustomEmojiId(emoji) ? ":\(emoji): " : emoji
            }
            .presentationDetents([.medium, .large])
        }
        .task(id: store.slowmodeUntil[channel.id]) {
            now = Date()
            while store.slowmodeRemaining(channelId: channel.id, now: now) > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                now = Date()
            }
        }
        .sheet(isPresented: $showGifPicker) {
            GifPickerSheet(store: store) { gif in
                store.sendMessage(content: gif.url, in: channel.id)
            }
            .presentationDetents([.medium, .large])
        }
        .onChange(of: text) { oldValue, newValue in
            guard !isEditing else { return }
            if newValue.count > oldValue.count {
                store.noteTyping(in: channel.id)
            } else if newValue.isEmpty {
                store.endTyping(in: channel.id)
            }
        }
        .onChange(of: store.editingMessage) { _, editing in
            if editing != nil {
                isFocused = true
            }
        }
        .onChange(of: store.replyingTo.count) { oldCount, newCount in
            if newCount > oldCount {
                isFocused = true
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if permissions.contains(.uploadFiles), !isEditing {
                Menu {
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("Photos & Videos", systemImage: "photo.on.rectangle")
                    }
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Files", systemImage: "folder")
                    }
                    Button {
                        startRecording()
                    } label: {
                        Label("Voice Message", systemImage: "mic")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(YukiTheme.accent)
                        .frame(width: 40, height: 40)
                }
                .disabled(attachments.count + preparing.count >= attachmentLimit)
                .accessibilityLabel("Add attachment")
            }

            HStack(alignment: .bottom, spacing: 4) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(1...8)
                    .focused($isFocused)
                    .padding(.vertical, 9)
                    .padding(.leading, 14)
                    .submitLabel(.return)

                if !isEditing {
                    Button {
                        showGifPicker = true
                    } label: {
                        Text("GIF")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary, lineWidth: 1.5))
                            .frame(width: 38, height: 38)
                    }
                    .buttonStyle(.plain)
                    .disabled(slowmodeRemaining > 0)
                    .accessibilityLabel("Send a GIF")
                }

                Button {
                    showEmojiPicker = true
                } label: {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 19))
                        .foregroundColor(.secondary)
                        .frame(width: 36, height: 38)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Insert emoji")
            }
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(YukiTheme.cardSurface))
            .overlay(alignment: .topTrailing) {
                if text.count > messageLimit - 200 {
                    Text("\(messageLimit - text.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(text.count > messageLimit ? .red : .secondary)
                        .padding(.trailing, 12)
                        .offset(y: -14)
                }
            }

            Button(action: send) {
                Image(systemName: isEditing ? "checkmark.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? YukiTheme.accent : Color.secondary.opacity(0.4))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel(isEditing ? "Save edit" : "Send message")
        }
    }

    private func send() {
        guard canSend else { return }
        YukiHaptics.impact(.medium)
        if let editing = store.editingMessage {
            let content = text
            clearText(sent: content)
            Task { await store.editMessage(messageId: editing.id, content: content, in: channel.id) }
        } else {
            store.sendMessage(content: text, in: channel.id, attachments: attachments)
            clearText(sent: text)
            attachments = []
        }
    }

    // Keyboards (autocorrect, dictation, marked IME text) can commit lingering text
    // just after the field is cleared. Clear it if it was only part of the sent message.
    private func clearText(sent: String) {
        text = ""
        guard !sent.isEmpty else { return }
        Task { @MainActor in
            for delay in [0, 150] {
                try? await Task.sleep(for: .milliseconds(delay))
                if !text.isEmpty, sent.hasSuffix(text) {
                    text = ""
                }
            }
        }
    }

    private var attachmentTray: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    trayTile(onRemove: {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
                            attachments.removeAll { $0.id == attachment.id }
                        }
                    }, removeLabel: "Remove \(attachment.filename)", isSpoiler: attachment.isSpoiler) {
                        if attachment.kind == .image {
                            Button {
                                editingAttachment = attachment
                            } label: {
                                AttachmentThumbnail(attachment: attachment)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Edit photo")
                            .accessibilityHint("Crop or straighten before sending")
                        } else {
                            AttachmentThumbnail(attachment: attachment)
                        }
                    }
                    .contextMenu {
                        Button {
                            toggleSpoiler(attachment)
                        } label: {
                            if attachment.isSpoiler {
                                Label("Remove Spoiler", systemImage: "eye")
                            } else {
                                Label("Mark as Spoiler", systemImage: "eye.slash")
                            }
                        }
                    }
                    .accessibilityAction(named: attachment.isSpoiler ? "Remove Spoiler" : "Mark as Spoiler") {
                        toggleSpoiler(attachment)
                    }
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
                ForEach(preparing) { item in
                    trayTile(onRemove: { cancelPreparing(item.id) }, removeLabel: "Cancel") {
                        PreparingThumbnail(item: item)
                    }
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .padding(.top, 6)
            .padding(.horizontal, 4)
        }
    }

    private func replace(_ original: OutgoingAttachment, with edited: OutgoingAttachment) {
        guard let index = attachments.firstIndex(where: { $0.id == original.id }) else { return }
        attachments[index] = edited.markedAsSpoiler(original.isSpoiler)
        YukiHaptics.notification(.success)
    }

    private func toggleSpoiler(_ attachment: OutgoingAttachment) {
        guard let index = attachments.firstIndex(where: { $0.id == attachment.id }) else { return }
        attachments[index] = attachment.markedAsSpoiler(!attachment.isSpoiler)
        YukiHaptics.selection()
    }

    private func trayTile<Content: View>(onRemove: @escaping () -> Void, removeLabel: String, isSpoiler: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        ZStack(alignment: .topTrailing) {
            content()
                .blur(radius: isSpoiler ? 8 : 0)
                .overlay {
                    if isSpoiler {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(Circle().fill(.black.opacity(0.55)))
                            .allowsHitTesting(false)
                            .accessibilityLabel("Spoiler")
                    }
                }
                .frame(width: 76, height: 76)
                .background(YukiTheme.cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.7))
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
            .accessibilityLabel(removeLabel)
        }
    }

    private func add(_ attachment: OutgoingAttachment) {
        guard attachment.data.count <= uploadLimit else {
            store.showError(StoatAPIError.fileTooLarge(limit: uploadLimit))
            return
        }
        guard attachments.count < attachmentLimit else {
            store.showError("You can attach up to \(attachmentLimit) files per message.")
            return
        }
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
            attachments.append(attachment)
        }
    }

    private func beginPreparing(kind: PreparingAttachment.Kind, work: @escaping @Sendable (_ progress: @escaping @Sendable (Double) -> Void) async throws -> OutgoingAttachment) {
        let id = UUID()
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
            preparing.append(PreparingAttachment(id: id, kind: kind))
        }
        let task = Task {
            do {
                let attachment = try await work { fraction in
                    Task { @MainActor in
                        guard let index = preparing.firstIndex(where: { $0.id == id }) else { return }
                        if fraction - (preparing[index].progress ?? 0) >= 0.02 || fraction >= 1 {
                            preparing[index].progress = fraction
                        }
                    }
                }
                guard preparing.contains(where: { $0.id == id }) else { return }
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
                    preparing.removeAll { $0.id == id }
                }
                add(attachment)
            } catch {
                guard preparing.contains(where: { $0.id == id }) else { return }
                withAnimation { preparing.removeAll { $0.id == id } }
                if !(error is CancellationError) {
                    store.showError(error)
                }
            }
        }
        if let index = preparing.firstIndex(where: { $0.id == id }) {
            preparing[index].task = task
        }
    }

    private func cancelPreparing(_ id: UUID) {
        preparing.first { $0.id == id }?.task?.cancel()
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
            preparing.removeAll { $0.id == id }
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        let limit = uploadLimit
        for item in items {
            let type = item.supportedContentTypes.first ?? .jpeg
            if type.conforms(to: .movie) {
                beginPreparing(kind: .video) { progress in
                    // Copied to a file rather than loaded into memory; large videos can be hundreds of MB.
                    guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                        throw AttachmentPreparationError.unreadable
                    }
                    return try await AttachmentPreparation.video(at: movie.url, limit: limit, progress: progress)
                }
            } else {
                beginPreparing(kind: .image) { _ in
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw AttachmentPreparationError.unreadable
                    }
                    return try await AttachmentPreparation.image(data: data, type: type, limit: limit)
                }
            }
        }
    }

    private func loadFiles(_ urls: [URL]) {
        let limit = uploadLimit
        for url in urls {
            let type = UTType(filenameExtension: url.pathExtension)
            if type?.conforms(to: .movie) == true {
                beginPreparing(kind: .video) { progress in
                    // The importer's URL is only readable briefly, so copy it before compressing.
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(url.pathExtension)
                    try FileManager.default.copyItem(at: url, to: copy)
                    return try await AttachmentPreparation.video(at: copy, limit: limit, progress: progress)
                }
            } else {
                beginPreparing(kind: type?.conforms(to: .image) == true ? .image : .file) { _ in
                    try await AttachmentPreparation.file(at: url, limit: limit)
                }
            }
        }
    }

    private func startRecording() {
        guard !VoiceCallController.isCallActive else {
            store.showError("You can't record a voice message during a call.")
            return
        }
        Task {
            guard await voiceRecorder.requestPermission() else {
                store.showError("Microphone access is needed to record voice messages. You can allow it in Settings.")
                return
            }
            do {
                try voiceRecorder.startRecording()
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) { isRecording = true }
                YukiHaptics.notification(.success)
            } catch {
                store.showError("Couldn't start recording.")
            }
        }
    }

    private func finishRecording(sendNow: Bool) {
        guard let result = voiceRecorder.stopRecording() else {
            withAnimation { isRecording = false }
            return
        }
        withAnimation { isRecording = false }
        try? FileManager.default.removeItem(at: result.url)
        let attachment = OutgoingAttachment(data: result.data, filename: "Voice Message.m4a", contentType: "audio/mp4", kind: .audio, duration: result.duration)
        if sendNow {
            store.sendMessage(content: text, in: channel.id, attachments: attachments + [attachment])
            clearText(sent: text)
            attachments = []
        } else {
            add(attachment)
        }
    }

    private var suggestions: [ComposerSuggestion] {
        ComposerQuery(text: text)?.suggestions(store: store.store, channel: channel) ?? []
    }

    private func apply(_ suggestion: ComposerSuggestion) {
        guard let active = ComposerQuery(text: text) else { return }
        text.removeLast(active.query.count + 1)
        text += suggestion.insertion
        YukiHaptics.selection()
    }
}
