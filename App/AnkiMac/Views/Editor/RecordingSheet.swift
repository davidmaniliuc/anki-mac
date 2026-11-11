import AppKit
import SwiftUI

/// Desktop's recording dialog as a sheet: a microphone, the elapsed time,
/// Save and Cancel.
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

    var body: some View {
        VStack(spacing: Theme.Spacing.large) {
            HStack(spacing: Theme.Spacing.large) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                    Text(Tr.mediaRecordingtime(secs: String(format: "%0.1f", recording.elapsed))
                        .replacingOccurrences(of: "<br>", with: "\n"))
                        .monospacedDigit()
                }
            }
            HStack {
                Spacer()
                Button(Tr.actionsCancel) { finish(false) }
                    .keyboardShortcut(.cancelAction)
                Button(Tr.actionsSave) { finish(true) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.large)
        .frame(minWidth: 280)
    }
}
