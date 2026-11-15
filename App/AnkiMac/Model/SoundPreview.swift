import AVFoundation
import FieldEditor

/// The players that stand for `[sound:]` tags in the editor's fields, and
/// the one that is playing. One sound plays at a time, whichever editor
/// it is in.
final class SoundPreview {
    static let shared = SoundPreview()
    /// A waveform arrived, or the playing sound moved on: fields redraw.
    static let didChange = Notification.Name("SoundPreviewDidChange")

    private let audio = AudioPlayer()
    private var requested: Set<URL> = []
    /// The sound playing or paused. Kept apart from the player's own file,
    /// which is nil for a moment after it is asked to play.
    private var current: URL?
    private var ticker: Task<Void, Never>?

    private init() {
        audio.onFinished = { [weak self] in self?.stop() }
    }

    /// What a file's player shows now. The first call for a file starts
    /// reading its waveform.
    func playback(_ url: URL) -> SoundPlayback {
        let waveform = SoundWaveforms.shared.cached(url)
        if waveform == nil, requested.insert(url).inserted {
            Task {
                _ = await SoundWaveforms.shared.waveform(url)
                changed()
            }
        }
        let isCurrent = url == current
        let duration = (isCurrent ? audio.duration : nil) ?? waveform?.duration
        return SoundPlayback(
            levels: waveform?.levels, duration: duration,
            progress: isCurrent ? duration.map { min(1, audio.currentTime / max($0, 0.01)) } ?? 0 : nil,
            playing: isCurrent && !audio.isPaused)
    }

    /// A click on a player: plays it, pauses it or carries on.
    func toggle(_ url: URL) {
        if url != current {
            play(url, from: 0)
        } else if audio.isPaused {
            audio.resume()
            tick()
        } else {
            audio.pause()
            ticker?.cancel()
        }
        changed()
    }

    /// A drag or swipe along a player's waveform: moves to `progress`
    /// (0 to 1) of the file. A playing sound plays on from there, a paused
    /// one waits there, and one at rest starts there.
    func scrub(_ url: URL, to progress: Double) {
        let progress = max(0, min(1, progress))
        if url != current {
            play(url, from: progress * (SoundWaveforms.shared.cached(url)?.duration ?? 0))
        } else {
            audio.seek(toProgress: progress, of: SoundWaveforms.shared.cached(url)?.duration)
        }
        changed()
    }

    func stop() {
        guard current != nil else { return }
        current = nil
        ticker?.cancel()
        audio.stop()
        changed()
    }

    private func play(_ url: URL, from position: TimeInterval) {
        audio.play(file: url, from: position)
        current = url
        tick()
    }

    /// Redraws the players while one plays, so its waveform fills.
    private func tick() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Theme.Sound.redraw)
                if Task.isCancelled { return }
                self?.changed()
            }
        }
    }

    private func changed() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
