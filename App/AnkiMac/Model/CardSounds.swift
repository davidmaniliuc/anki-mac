import AnkiKit
import Foundation

/// The sound players on the card a reviewer page shows. It gives the page
/// each sound's waveform and length, tells it how far the one playing has
/// got, and answers the page's pause and seek commands. A play button
/// whose sound has no file here (speech, a missing file) stays a button.
final class CardSounds {
    private let audio: AudioPlayer
    private let web: ReviewerWebController
    /// The card's sounds by the page's name for them: "q:0" is the first
    /// on the question.
    private var sounds: [String: (tag: Anki_CardRendering_AVTag, file: URL)] = [:]
    private var loading: Task<Void, Never>?
    private var ticker: Task<Void, Never>?

    init(audio: AudioPlayer, web: ReviewerWebController) {
        self.audio = audio
        self.web = web
        audio.onChange = { [weak self] in self?.playbackChanged() }
    }

    /// Call after each side of a card is put on the page, which replaces
    /// its buttons.
    func show(_ card: RenderedCard) {
        sounds = [:]
        guard let folder = web.mediaFolder else { return }
        for (side, tags) in [("q", card.questionAV), ("a", card.answerAV)] {
            for (index, tag) in tags.enumerated() {
                guard case .soundOrVideo(let name) = tag.value else { continue }
                let file = folder.appending(path: name)
                if FileManager.default.fileExists(atPath: file.path) { sounds["\(side):\(index)"] = (tag, file) }
            }
        }
        loading?.cancel()
        let shown = sounds
        loading = Task {
            var players: [String: Any] = [:]
            for (ref, sound) in shown {
                let waveform = await SoundWaveforms.shared.waveform(sound.file)
                if Task.isCancelled { return }
                let levels = waveform.levels.isEmpty ? [Float](repeating: 0, count: Theme.Sound.bars) : waveform.levels
                players[ref] = ["levels": levels.map { Double($0) }, "duration": waveform.duration as Any? ?? NSNull()]
            }
            web.showSounds(Self.json(players))
            pushPlayback()
        }
    }

    /// Handles the page's "audiopause" and "seek:q:0:0.42"; false for any
    /// other command.
    func handle(_ command: String) -> Bool {
        if command == "audiopause" {
            if audio.isPaused { audio.resume() } else { audio.pause() }
            return true
        }
        guard command.hasPrefix("seek:") else { return false }
        let parts = command.split(separator: ":")
        guard parts.count == 4, let progress = Double(parts[3]), let sound = sounds["\(parts[1]):\(parts[2])"],
            let folder = web.mediaFolder
        else { return true }
        let length = SoundWaveforms.shared.cached(sound.file)?.duration
        if audio.currentFile == sound.file {
            audio.seek(toProgress: progress, of: length)
        } else {
            audio.play([sound.tag], mediaFolder: folder, from: progress * (length ?? 0))
        }
        return true
    }

    private func playbackChanged() {
        ticker?.cancel()
        pushPlayback()
        guard audio.currentFile != nil, !audio.isPaused else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Theme.Sound.redraw)
                if Task.isCancelled { return }
                self?.pushPlayback()
            }
        }
    }

    private func pushPlayback() {
        guard let file = audio.currentFile else { return web.showPlayback("null") }
        let length = audio.duration ?? SoundWaveforms.shared.cached(file)?.duration
        let elapsed = audio.currentTime
        web.showPlayback(Self.json([
            "refs": sounds.filter { $0.value.file == file }.map(\.key),
            "progress": length.map { min(1, elapsed / max($0, 0.01)) } ?? 0,
            "elapsed": elapsed,
            "playing": !audio.isPaused,
        ]))
    }

    private static func json(_ object: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: object)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
    }
}
