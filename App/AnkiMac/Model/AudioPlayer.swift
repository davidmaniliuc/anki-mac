import AVFoundation
import AnkiKit
import os

/// Plays a card's [sound:] files and TTS tags in order, natively. Desktop
/// uses mpv for this; AVFoundation covers the common formats (mp3, m4a, wav,
/// aac, flac, opus).
@MainActor
final class AudioPlayer: NSObject, AVSpeechSynthesizerDelegate {
    private var player: AVPlayer?
    private let synthesizer = AVSpeechSynthesizer()
    private var playback: Task<Void, Never>?
    /// Keyed by utterance: a stopped utterance's late didCancel must not
    /// resume the next one's continuation.
    private var speechFinished: [ObjectIdentifier: CheckedContinuation<Void, Never>] = [:]
    private let log = Logger(subsystem: "AnkiMac", category: "audio")

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Something is playing or paused, as desktop's `current_player`.
    private(set) var isPlaying = false
    private(set) var isPaused = false
    /// The file playing or paused now; nil between files and during speech.
    private(set) var currentFile: URL?
    /// Called when a file starts or ends, and on pause, resume and stop,
    /// for whatever draws the playback.
    var onChange: (() -> Void)?
    /// Called when everything `play` queued has played to the end, not when it is stopped.
    var onFinished: (() -> Void)?
    /// Counts `play` and `stop` calls, so a stopped run doesn't report finishing.
    private var generation = 0

    /// `position` is how many seconds into the first tag's file to start.
    func play(_ tags: [Anki_CardRendering_AVTag], mediaFolder: URL, from position: TimeInterval = 0) {
        guard !tags.isEmpty else { return stop() }
        start {
            for (index, tag) in tags.enumerated() {
                if Task.isCancelled { return }
                switch tag.value {
                case .soundOrVideo(let file):
                    await self.playFile(mediaFolder.appending(path: file), from: index == 0 ? position : 0)
                case .tts(let tts):
                    await self.speak(tts)
                case nil:
                    continue
                }
            }
        }
    }

    /// One file on its own, such as the reviewer's recorded voice or a
    /// sound in the editor, from `position` seconds in.
    func play(file url: URL, from position: TimeInterval = 0) {
        start { await self.playFile(url, from: position) }
    }

    private func start(_ body: @escaping @MainActor () async -> Void) {
        stop()
        let current = generation
        isPlaying = true
        playback = Task {
            await body()
            guard generation == current else { return }
            isPlaying = false
            playback = nil
            onFinished?()
        }
    }

    func stop() {
        generation += 1
        isPlaying = false
        isPaused = false
        currentFile = nil
        defer { onChange?() }
        playback?.cancel()
        playback = nil
        player?.pause()
        player = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    func pause() {
        isPaused = true
        player?.pause()
        synthesizer.pauseSpeaking(at: .immediate)
        onChange?()
    }

    func resume() {
        isPaused = false
        player?.play()
        synthesizer.continueSpeaking()
        onChange?()
    }

    /// Desktop's 6 and 7: jumps back or forward in the file playing, within
    /// its length. Speech has no position to move.
    func seek(by seconds: Double) {
        guard let player, let item = player.currentItem else { return }
        var target = max(0, player.currentTime().seconds + seconds)
        if item.duration.isNumeric { target = min(target, item.duration.seconds) }
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    /// Where the file playing has got to, and its length once known.
    var currentTime: TimeInterval {
        guard let seconds = player?.currentTime().seconds, seconds.isFinite else { return 0 }
        return seconds
    }

    var duration: TimeInterval? {
        guard let duration = player?.currentItem?.duration, duration.isNumeric else { return nil }
        return duration.seconds
    }

    /// Jumps to a fraction of the file playing; `length` stands in until
    /// the player knows its own.
    func seek(toProgress progress: Double, of length: TimeInterval?) {
        guard let player, let length = duration ?? length else { return }
        player.seek(
            to: CMTime(seconds: length * progress, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func playFile(_ url: URL, from position: TimeInterval = 0) async {
        log.notice("play file \(url.lastPathComponent, privacy: .public)")
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        currentFile = url
        if position > 0 {
            await player.seek(
                to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            if Task.isCancelled { return }
        }
        // Paused while it was seeking: it waits there.
        if !isPaused { player.play() }
        onChange?()
        defer {
            if currentFile == url, self.player === player {
                currentFile = nil
                onChange?()
            }
        }
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
        log.notice("file \(url.lastPathComponent, privacy: .public) done, status \(item.status.rawValue)")
    }

    private func speak(_ tag: Anki_CardRendering_TTSTag) async {
        if Task.isCancelled { return }
        log.notice("speak \(tag.lang, privacy: .public)")
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
                speechFinished[ObjectIdentifier(utterance)] = continuation
                synthesizer.speak(utterance)
            }
        } onCancel: {
            Task { @MainActor in self.synthesizer.stopSpeaking(at: .immediate) }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.resumeSpeech(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.resumeSpeech(id) }
    }

    private func resumeSpeech(_ id: ObjectIdentifier) {
        speechFinished.removeValue(forKey: id)?.resume()
    }
}
