import AVFoundation

/// A microphone recording in progress, written to a temporary file that
/// the caller either keeps (`stop`) or throws away (`discard`). Desktop
/// records a wav and encodes it to mp3 with lame; AVFoundation has no mp3
/// encoder, so this records AAC in an .m4a, which Anki plays everywhere.
final class AudioRecording {
    let url: URL
    private let recorder: AVAudioRecorder

    var elapsed: TimeInterval { recorder.currentTime }

    /// Asks for microphone access if needed, then starts recording.
    static func start() async throws -> AudioRecording {
        guard await AVCaptureDevice.requestAccess(for: .audio) else { throw RecordingError.accessDenied }
        let url = FileManager.default.temporaryDirectory
            .appending(path: "rec\(Int(Date().timeIntervalSince1970)).m4a")
        let recorder = try AVAudioRecorder(
            url: url,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ])
        guard recorder.record() else { throw RecordingError.noInput }
        return AudioRecording(url: url, recorder: recorder)
    }

    private init(url: URL, recorder: AVAudioRecorder) {
        self.url = url
        self.recorder = recorder
    }

    /// Ends the recording, leaving the file for the caller to use and delete.
    func stop() -> URL {
        recorder.stop()
        return url
    }

    func discard() {
        recorder.stop()
        try? FileManager.default.removeItem(at: url)
    }
}

enum RecordingError: LocalizedError {
    case accessDenied
    case noInput

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "Microphone access is off for AnkiMac. Allow it in System Settings > Privacy & Security > Microphone."
        case .noInput:
            "The microphone could not be opened."
        }
    }
}
