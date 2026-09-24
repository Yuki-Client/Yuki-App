import AVFoundation

/// Silent playback mixes with other apps' audio; anything with sound takes over and then hands
/// it back. Calls manage the session themselves.
@MainActor
public enum AudioSessionPolicy {
    private static var claims = 0

    public static func prepareForSilentPlayback() {
        guard claims == 0 else { return }
        let session = AVAudioSession.sharedInstance()
        guard session.category != .ambient else { return }
        try? session.setCategory(.ambient)
    }

    public static func begin(
        _ category: AVAudioSession.Category = .playback,
        options: AVAudioSession.CategoryOptions = []
    ) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(category, mode: .default, options: options)
        try session.setActive(true)
        claims += 1
    }

    public static func end() {
        guard claims > 0 else { return }
        claims -= 1
        guard claims == 0 else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try? session.setCategory(.ambient)
    }
}
