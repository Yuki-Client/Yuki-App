import Foundation
import AVFoundation

/// Short tones generated in code, so Yuki doesn't need to bundle sound files.
enum ToneGenerator {
    struct Note {
        /// Frequencies played together, in hertz; empty for silence.
        var frequencies: [Double]
        var duration: Double
    }

    /// A mono 16-bit WAV of the notes in order, with short fades so they don't click.
    static func wav(_ notes: [Note], volume: Double = 0.5) -> Data {
        let sampleRate = 44_100
        let fade = Int(Double(sampleRate) * 0.008)
        var samples: [Int16] = []
        var elapsed = 0
        for note in notes {
            let count = Int(Double(sampleRate) * note.duration)
            for index in 0..<count {
                guard !note.frequencies.isEmpty else {
                    samples.append(0)
                    continue
                }
                let time = Double(elapsed + index) / Double(sampleRate)
                let envelope = min(1, Double(min(index, count - index)) / Double(max(fade, 1)))
                let mixed = note.frequencies.reduce(0) { $0 + sin(2 * .pi * $1 * time) } / Double(note.frequencies.count)
                samples.append(Int16(mixed * envelope * volume * Double(Int16.max)))
            }
            elapsed += count
        }

        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        let byteCount = samples.count * 2
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + byteCount))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(byteCount))
        for sample in samples {
            append(sample)
        }
        return data
    }
}

/// These play through the call's own audio session, so they only make sense while connected.
@MainActor
final class CallSounds {
    enum Sound: CaseIterable {
        case joined, left, muted, unmuted

        var notes: [ToneGenerator.Note] {
            switch self {
            case .joined: [.init(frequencies: [587.33], duration: 0.09), .init(frequencies: [880], duration: 0.14)]
            case .left: [.init(frequencies: [880], duration: 0.09), .init(frequencies: [587.33], duration: 0.14)]
            case .muted: [.init(frequencies: [440], duration: 0.08)]
            case .unmuted: [.init(frequencies: [660], duration: 0.08)]
            }
        }
    }

    private var players: [Sound: AVAudioPlayer] = [:]

    func play(_ sound: Sound) {
        let player = players[sound] ?? {
            let player = try? AVAudioPlayer(data: ToneGenerator.wav(sound.notes, volume: 0.35))
            player?.prepareToPlay()
            players[sound] = player
            return player
        }()
        player?.currentTime = 0
        player?.play()
    }
}

/// For incoming calls when the system call screen isn't used. Follows the silent switch.
@MainActor
public final class RingtonePlayer {
    private var player: AVAudioPlayer?

    public init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        let burst = ToneGenerator.Note(frequencies: [440, 480], duration: 0.4)
        player = try? AVAudioPlayer(data: ToneGenerator.wav([burst, .init(frequencies: [], duration: 0.2), burst]))
        player?.volume = 0.6
        player?.prepareToPlay()
    }

    public func play() {
        player?.currentTime = 0
        player?.play()
    }

    public func stop() {
        player?.stop()
    }
}
