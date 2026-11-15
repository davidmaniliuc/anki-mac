import AVFoundation

/// The shape and length of a sound file, for the players that stand for
/// sounds in the editor's fields and on cards.
nonisolated struct Waveform: Sendable {
    /// Loudness from start to end, each from 0 to 1; empty for a file
    /// AVFoundation can't read as audio.
    var levels: [Float]
    var duration: TimeInterval?
}

/// Reads each file's waveform once, off the main thread.
final class SoundWaveforms {
    static let shared = SoundWaveforms()

    private var read: [URL: Waveform] = [:]
    private var reading: [URL: Task<Waveform, Never>] = [:]

    /// A waveform read earlier, without waiting.
    func cached(_ url: URL) -> Waveform? { read[url] }

    func waveform(_ url: URL) async -> Waveform {
        if let waveform = read[url] { return waveform }
        if let task = reading[url] { return await task.value }
        let bars = Theme.Sound.bars
        let task = Task.detached { Self.read(url, bars: bars) ?? Waveform(levels: [], duration: nil) }
        reading[url] = task
        let waveform = await task.value
        read[url] = waveform
        reading[url] = nil
        return waveform
    }

    /// The loudness (RMS) of each of `bars` equal stretches of a file,
    /// against the loudest stretch, so a quiet recording still has a shape
    /// and one click doesn't flatten the rest.
    private nonisolated static func read(_ url: URL, bars: Int) -> Waveform? {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0,
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1 << 15)
        else { return nil }
        let perBar = max(1, Int(file.length) / bars)
        var squares = [Float](repeating: 0, count: bars)
        var position = 0
        while file.framePosition < file.length, (try? file.read(into: buffer)) != nil, buffer.frameLength > 0,
            let samples = buffer.floatChannelData?[0]
        {
            for index in 0..<Int(buffer.frameLength) {
                let bar = min(bars - 1, (position + index) / perBar)
                squares[bar] += samples[index] * samples[index]
            }
            position += Int(buffer.frameLength)
        }
        let loudness = squares.map { ($0 / Float(perBar)).squareRoot() }
        let loudest = loudness.max() ?? 0
        return Waveform(
            // The root lifts quiet stretches, as loudness is heard.
            levels: loudest > 0 ? loudness.map { ($0 / loudest).squareRoot() } : loudness,
            duration: Double(file.length) / file.processingFormat.sampleRate)
    }
}
