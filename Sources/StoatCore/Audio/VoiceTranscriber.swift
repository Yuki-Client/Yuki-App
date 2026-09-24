import Foundation
import AVFoundation
import Speech

public enum VoiceTranscriber {
    public enum Failure: LocalizedError {
        case unsupportedLanguage
        case unavailable
        case denied
        case unreadable
        case noSpeech

        public var errorDescription: String? {
            switch self {
            case .unsupportedLanguage: "Transcription isn't available in your language yet."
            case .unavailable: "Transcription isn't available on this device."
            case .denied: "Allow Speech Recognition for Yuki in Settings to transcribe voice messages."
            case .unreadable: "Yuki can't read this recording."
            case .noSpeech: "No speech was found in this recording."
            }
        }
    }

    @MainActor private static var transcripts: [String: String] = [:]

    @MainActor
    public static func cachedTranscript(for id: String) -> String? {
        transcripts[id]
    }

    @MainActor
    public static func transcribe(id: String, url: URL, filename: String) async throws -> String {
        if let known = transcripts[id] { return known }
        let file = try await download(url, filename: filename)
        defer { try? FileManager.default.removeItem(at: file) }

        let text: String
        if #available(iOS 26, *), SpeechTranscriber.isAvailable {
            text = try await transcribeOnDevice(file)
        } else {
            text = try await transcribeWithRecognizer(file)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Failure.noSpeech }
        transcripts[id] = trimmed
        return trimmed
    }

    private static func download(_ url: URL, filename: String) async throws -> URL {
        let (temporary, _) = try await URLSession.shared.download(from: url)
        let ext = (filename as NSString).pathExtension
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcribe-\(UUID().uuidString)")
            .appendingPathExtension(ext.isEmpty ? "m4a" : ext)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    @available(iOS 26, *)
    private static func transcribeOnDevice(_ file: URL) async throws -> String {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else {
            throw Failure.unsupportedLanguage
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        if let install = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await install.downloadAndInstall()
        }
        guard let audio = try? AVAudioFile(forReading: file) else { throw Failure.unreadable }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        async let text = transcriber.results.reduce(into: "") { text, result in
            text += String(result.text.characters)
        }
        if let end = try await analyzer.analyzeSequence(from: audio) {
            try await analyzer.finalizeAndFinish(through: end)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return try await text
    }

    private static func transcribeWithRecognizer(_ file: URL) async throws -> String {
        guard await authorize() else { throw Failure.denied }
        guard let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(),
              recognizer.supportsOnDeviceRecognition else {
            throw Failure.unavailable
        }
        guard recognizer.isAvailable else { throw Failure.unavailable }

        let request = SFSpeechURLRecognitionRequest(url: file)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true

        let once = ResumeOnce()
        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    once.run { continuation.resume(returning: result.bestTranscription.formattedString) }
                } else if let error {
                    once.run { continuation.resume(throwing: (error as NSError).code == 1110 ? Failure.noSpeech : error) }
                }
            }
        }
    }

    private static func authorize() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
        default: return false
        }
    }
}

private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        body()
    }
}
