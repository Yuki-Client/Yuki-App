import Foundation
import AVFoundation
import Observation
import StoatCore

@Observable
@MainActor
public final class VoiceRecorder: NSObject, AVAudioRecorderDelegate {
    public private(set) var isRecording: Bool = false
    public private(set) var duration: TimeInterval = 0.0
    public private(set) var currentAudioLevel: CGFloat = 0.0
    public private(set) var audioLevels: [CGFloat] = []

    private var audioRecorder: AVAudioRecorder?
    private var recordingTimer: Timer?
    private var tempFileURL: URL?
    private var holdsAudio = false

    public override init() {
        super.init()
    }

    public func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    public func startRecording() throws {
        cancelRecording()

        try AudioSessionPolicy.begin(.playAndRecord, options: [.defaultToSpeaker, .allowBluetoothHFP])
        holdsAudio = true

        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "voice_note_\(UUID().uuidString).m4a"
        let fileURL = tempDir.appendingPathComponent(fileName)
        self.tempFileURL = fileURL

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true

        guard recorder.record() else {
            throw NSError(domain: "VoiceRecorder", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to begin recording."])
        }

        self.audioRecorder = recorder
        self.isRecording = true
        self.duration = 0.0
        self.audioLevels = []
        self.currentAudioLevel = 0.0

        startMeteringTimer()
    }

    public func stopRecording() -> (data: Data, duration: TimeInterval, url: URL)? {
        guard isRecording, let recorder = audioRecorder, let fileURL = tempFileURL else {
            return nil
        }

        stopMeteringTimer()
        recorder.stop()
        self.isRecording = false
        releaseAudio()
        self.audioRecorder = nil

        let finalDuration = self.duration

        guard let data = try? Data(contentsOf: fileURL) else {
            try? FileManager.default.removeItem(at: fileURL)
            self.tempFileURL = nil
            return nil
        }

        return (data: data, duration: finalDuration, url: fileURL)
    }

    private func releaseAudio() {
        guard holdsAudio else { return }
        holdsAudio = false
        AudioSessionPolicy.end()
    }

    public func cancelRecording() {
        stopMeteringTimer()
        if let recorder = audioRecorder {
            recorder.stop()
            self.audioRecorder = nil
        }
        if let fileURL = tempFileURL {
            try? FileManager.default.removeItem(at: fileURL)
            self.tempFileURL = nil
        }
        releaseAudio()
        self.isRecording = false
        self.duration = 0.0
        self.audioLevels.removeAll()
        self.currentAudioLevel = 0.0
    }

    private func startMeteringTimer() {
        stopMeteringTimer()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateMetering()
            }
        }
    }

    private func stopMeteringTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    private func updateMetering() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }

        duration = recorder.currentTime
        recorder.updateMeters()

        let power = recorder.averagePower(forChannel: 0)
        let minDb: Float = -50.0
        let clampedPower = max(minDb, min(0.0, power))
        let normalizedLevel = CGFloat((clampedPower - minDb) / (0.0 - minDb))

        self.currentAudioLevel = normalizedLevel

        self.audioLevels.append(normalizedLevel)
        if self.audioLevels.count > 30 {
            self.audioLevels.removeFirst()
        }
    }

    // MARK: - AVAudioRecorderDelegate

    public nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            if !flag {
                self.cancelRecording()
            }
        }
    }

    public nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            self.cancelRecording()
        }
    }
}
