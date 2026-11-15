import AppKit
import SwiftUI

/// Desktop's recording dialog as a sheet: that it is recording, for how
/// long, what the microphone hears, and Save and Cancel.
enum RecordingSheet {
    /// Shows the sheet over a window. Calls back with the recorded file on
    /// Save, or nil after Cancel, with the recording already discarded.
    static func present(_ recording: AudioRecording, over window: NSWindow, completion: @escaping (URL?) -> Void) {
        let host = NSHostingController(rootView: RecordingView(recording: recording) { save in
            if let sheet = window.attachedSheet { window.endSheet(sheet) }
            if save {
                completion(recording.stop())
            } else {
                recording.discard()
                completion(nil)
            }
        })
        let content = NSWindow(contentViewController: host)
        content.styleMask = [.titled]
        window.beginSheet(content)
    }
}

private struct RecordingView: View {
    let recording: AudioRecording
    let finish: (_ save: Bool) -> Void
    @State private var elapsed: TimeInterval = 0
    /// The input level at each sample, oldest first, as many as the meter has bars for.
    @State private var levels: [Double] = []
    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Upstream's "Recording...<br>Time: 5.2", as its two lines.
    private var lines: (title: String, time: String) {
        let parts = Tr.mediaRecordingtime(secs: String(format: "%0.1f", elapsed)).components(separatedBy: "<br>")
        return (parts[0], parts.dropFirst().joined(separator: " "))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.large) {
            VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.small) {
                    Image(systemName: "mic.fill")
                        .font(Theme.Recording.symbol)
                        .foregroundStyle(Theme.Recording.live)
                        .opacity(pulsing ? 0.45 : 1)
                        .accessibilityHidden(true)
                    Text(lines.title)
                        .font(Theme.Fonts.panelTitle)
                        .foregroundStyle(Theme.Palette.text)
                    Spacer(minLength: Theme.Spacing.medium)
                    Text(lines.time)
                        .font(Theme.Recording.time)
                        .foregroundStyle(Theme.Palette.secondary)
                }
                .accessibilityElement(children: .combine)
                LevelMeter(levels: levels)
                    .frame(height: Theme.Recording.meterHeight)
                    .accessibilityHidden(true)
            }
            HStack {
                Spacer()
                DialogButtons(action: Tr.actionsSave, cancel: { finish(false) }, submit: { finish(true) })
            }
        }
        .padding(Theme.Spacing.large)
        .frame(width: Theme.Recording.width)
        .background(Theme.Palette.canvas.ignoresSafeArea())
        .task {
            if !reduceMotion {
                withAnimation(.easeInOut(duration: Theme.Recording.pulse).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
            let bars = LevelMeter.bars(in: Theme.Recording.width - Theme.Spacing.large * 2)
            while !Task.isCancelled {
                elapsed = recording.elapsed
                levels.append(recording.level(floor: Theme.Recording.floor))
                if levels.count > bars { levels.removeFirst(levels.count - bars) }
                try? await Task.sleep(for: Theme.Recording.sampleInterval)
            }
        }
    }
}

/// What the microphone hears: a bar per sample, the newest at the trailing
/// edge, so speech moves across it and silence is a row of dots.
private struct LevelMeter: View {
    let levels: [Double]

    static func bars(in width: CGFloat) -> Int {
        Int((width + Theme.Recording.barGap) / (Theme.Recording.barWidth + Theme.Recording.barGap))
    }

    var body: some View {
        Canvas { context, size in
            let step = Theme.Recording.barWidth + Theme.Recording.barGap
            let count = Self.bars(in: size.width)
            let heard = levels.suffix(count)
            for slot in 0..<count {
                // Slots fill from the trailing edge; the ones not reached yet stay faint.
                let sample = slot - (count - heard.count)
                let level = sample >= 0 ? heard[heard.startIndex + sample] : 0
                let height = max(Theme.Recording.barMinHeight, size.height * level)
                let bar = CGRect(
                    x: size.width - CGFloat(count - slot) * step + Theme.Recording.barGap,
                    y: (size.height - height) / 2, width: Theme.Recording.barWidth, height: height)
                context.fill(
                    Path(roundedRect: bar, cornerRadius: Theme.Recording.barWidth / 2),
                    with: .color(sample >= 0 ? Theme.Recording.live : Theme.Palette.hairline))
            }
        }
    }
}
