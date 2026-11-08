import AVFoundation
import AnkiKit

/// Plays a card's [sound:] files and TTS tags in order, natively. Desktop
/// uses mpv for this; AVFoundation covers the common formats (mp3, m4a, wav,
/// aac, flac, opus).
@MainActor
final class AudioPlayer: NSObject, AVSpeechSynthesizerDelegate {
    private var player: AVPlayer?
    private let synthesizer = AVSpeechSynthesizer()
    private var playback: Task<Void, Never>?
    private var speechFinished: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func play(_ tags: [Anki_CardRendering_AVTag], mediaFolder: URL) {
        stop()
        guard !tags.isEmpty else { return }
        playback = Task {
            for tag in tags {
                if Task.isCancelled { return }
                switch tag.value {
                case .soundOrVideo(let file):
                    await playFile(mediaFolder.appending(path: file))
                case .tts(let tts):
                    await speak(tts)
                case nil:
                    continue
                }
            }
        }
    }

    func stop() {
        playback?.cancel()
        playback = nil
        player?.pause()
        player = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    private func playFile(_ url: URL) async {
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        player.play()
        let ended = NotificationCenter.default.notifications(named: AVPlayerItem.didPlayToEndTimeNotification, object: item)
        let failed = NotificationCenter.default.notifications(named: AVPlayerItem.failedToPlayToEndTimeNotification, object: item)
        await withTaskGroup(of: Void.self) { group in
            group.addTask { for await _ in ended { return } }
            group.addTask { for await _ in failed { return } }
            // A file that can't be decoded never posts either notification.
            group.addTask {
                while !Task.isCancelled, item.status != .failed {
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
            await group.next()
            group.cancelAll()
        }
    }

    private func speak(_ tag: Anki_CardRendering_TTSTag) async {
        let utterance = AVSpeechUtterance(string: tag.fieldText)
        // Anki writes languages as en_US; AVSpeech wants en-US.
        let language = tag.lang.replacingOccurrences(of: "_", with: "-")
        utterance.voice = tag.voices.lazy.compactMap { AVSpeechSynthesisVoice(identifier: $0) }.first
            ?? AVSpeechSynthesisVoice(language: language)
        if tag.speed > 0 {
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * tag.speed
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                speechFinished = continuation
                synthesizer.speak(utterance)
            }
        } onCancel: {
            Task { @MainActor in self.synthesizer.stopSpeaking(at: .immediate) }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.resumeSpeech() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.resumeSpeech() }
    }

    private func resumeSpeech() {
        speechFinished?.resume()
        speechFinished = nil
    }
}
