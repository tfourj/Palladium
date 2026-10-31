import AVFoundation
import Foundation

/// Keeps Palladium running in the background by playing silence through an audio session.
///
/// iOS does not suspend apps with the audio background mode while they play audio. This works where background
/// tasks are unavailable, such as in LiveContainer, whose Info.plist declares the audio mode for every guest app.
/// The session mixes with other audio, so music the user plays keeps going.
final class SilentAudioKeepAlive {
    static let shared = SilentAudioKeepAlive()

    private static let sampleRate = 44_100.0
    private static let bufferDuration = 1.0

    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var observers: [NSObjectProtocol] = []
    private var log: (String) -> Void = { _ in }

    private(set) var isActive = false

    private init() {}

    /// Starts playing silence. Returns false when the audio session or engine cannot start.
    func start(log: @escaping (String) -> Void) -> Bool {
        self.log = log
        guard !isActive else { return true }
        do {
            try startPlayback()
        } catch {
            log("[palladium] silent audio unavailable: \(error.localizedDescription)\n")
            stopPlayback()
            return false
        }
        isActive = true
        addObservers()
        log("[palladium] silent audio background mode started\n")
        return true
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        removeObservers()
        stopPlayback()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        log("[palladium] silent audio background mode stopped\n")
    }

    /// Restores the silent audio session after other playback, such as a saved video, changed or deactivated it.
    func resumeIfActive() {
        guard isActive else { return }
        restart(reason: "audio session reused")
    }

    private func startPlayback() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 2),
              let buffer = Self.silentBuffer(format: format) else {
            throw CocoaError(.featureUnsupported)
        }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        player.play()

        self.engine = engine
        self.player = player
    }

    private func stopPlayback() {
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
    }

    private func restart(reason: String) {
        stopPlayback()
        do {
            try startPlayback()
            log("[palladium] silent audio restarted after \(reason)\n")
        } catch {
            log("[palladium] silent audio could not restart after \(reason): \(error.localizedDescription)\n")
        }
    }

    private static func silentBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(sampleRate * bufferDuration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else {
            return nil
        }
        buffer.frameLength = frameCount
        for channel in 0..<Int(format.channelCount) {
            channels[channel].update(repeating: 0, count: Int(frameCount))
        }
        return buffer
    }

    private func addObservers() {
        let center = NotificationCenter.default
        // Calls and Siri interrupt the session, and playback has to start again once they end.
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard rawType.flatMap(AVAudioSession.InterruptionType.init) == .ended else { return }
            self?.restart(reason: "interruption")
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.restart(reason: "media services reset")
        })
        // Route changes, such as headphones disconnecting, stop the engine.
        observers.append(center.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, notification.object as? AVAudioEngine === self.engine else { return }
            self.restart(reason: "audio route change")
        })
    }

    private func removeObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }
}
