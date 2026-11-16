import AnkiKit
import Foundation

/// Check Media's Render LaTeX, as desktop's `render_all_latex`: makes the
/// image of every note's LaTeX that the media folder lacks, with the TeX
/// install's latex, then dvipng, or dvisvgm for a note type set to SVG.
nonisolated enum LatexRenderer {
    /// The first note whose LaTeX didn't render, and why; desktop stops there.
    struct Failure: LocalizedError, Sendable {
        let noteID: Int64
        let message: String
        var errorDescription: String? { message }
    }

    private static let pngCommands = [
        ["latex", "-interaction=nonstopmode", "tmp.tex"],
        ["dvipng", "-bg", "Transparent", "-D", "200", "-T", "tight", "tmp.dvi", "-o", "tmp.png"],
    ]
    private static let svgCommands = [
        ["latex", "-interaction=nonstopmode", "tmp.tex"],
        ["dvisvgm", "--no-fonts", "--exact", "-Z", "2", "tmp.dvi", "-o", "tmp.svg"],
    ]
    /// Where TeX installs on a Mac, which an app's PATH doesn't reach.
    private static let texFolders = ["/Library/TeX/texbin", "/usr/texbin", "/opt/homebrew/bin", "/usr/local/bin"]
    /// How often the count of checked notes is passed on, as desktop's.
    private static let progressInterval: TimeInterval = 0.3

    /// Renders the LaTeX missing from the media folder, passing on how many
    /// notes have been checked.
    static func renderMissing(_ backend: AnkiBackend, mediaFolder: URL, progress: @Sendable (Int) -> Void) throws {
        var setting = Anki_Config_GetConfigBoolRequest()
        setting.key = .renderLatex
        let enabled = try backend.getConfigBool(setting).val
        let query: [String: Any] = [
            "kind": "query", "args": [], "first_row_only": false,
            "sql": "select id, mid, flds from notes where flds like '%[%'",
        ]
        let reply = try backend.dbCommand(try JSONSerialization.data(withJSONObject: query))
        let rows = (try JSONSerialization.jsonObject(with: reply) as? [[Any]]) ?? []
        let folder = FileManager.default.temporaryDirectory.appending(path: "AnkiMac LaTeX", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var notetypes: [Int64: Anki_Notetypes_Notetype.Config] = [:]
        var reported = Date()
        for (checked, row) in rows.enumerated() {
            guard row.count == 3, let nid = (row[0] as? NSNumber)?.int64Value,
                let mid = (row[1] as? NSNumber)?.int64Value, let fields = row[2] as? String
            else { continue }
            if notetypes[mid] == nil {
                var id = Anki_Notetypes_NotetypeId()
                id.ntid = mid
                notetypes[mid] = try backend.getNotetype(id).config
            }
            guard let config = notetypes[mid] else { continue }
            var request = Anki_CardRendering_ExtractLatexRequest()
            request.text = fields
            request.svg = config.latexSvg
            request.expandClozes = true
            for latex in try backend.extractLatex(request).latex
            where !FileManager.default.fileExists(atPath: mediaFolder.appending(path: latex.filename).path) {
                guard enabled else { throw Failure(noteID: nid, message: Tr.preferencesLatexGenerationDisabled) }
                var add = Anki_Media_AddMediaFileRequest()
                add.desiredName = latex.filename
                add.data = try render(
                    "\(config.latexPre)\n\(latex.latexBody)\n\(config.latexPost)",
                    svg: config.latexSvg, in: folder, note: nid)
                _ = try backend.addMediaFile(add)
            }
            if Date().timeIntervalSince(reported) >= progressInterval {
                reported = Date()
                progress(checked + 1)
            }
        }
    }

    /// The image for one piece of LaTeX, made in `folder`, which keeps the
    /// .tex and the log of the last attempt to look at when it fails.
    private static func render(_ tex: String, svg: Bool, in folder: URL, note: Int64) throws -> Data {
        let texFile = folder.appending(path: "tmp.tex")
        let log = folder.appending(path: "latex_log.txt")
        try tex.write(to: texFile, atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: log)
        defer { try? logHandle.close() }

        for command in svg ? svgCommands : pngCommands {
            guard let tool = executable(command[0]) else {
                throw Failure(noteID: note, message: failure(command[0], detail: Tr.mediaHaveYouInstalledLatexAndDvipngdvisvgm))
            }
            let process = Process()
            process.executableURL = tool
            process.arguments = Array(command.dropFirst())
            process.currentDirectoryURL = folder
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = logHandle
            process.standardError = logHandle
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                // LaTeX starts its errors with "!"; the rest is in the log.
                let firstError = (try? String(contentsOf: log, encoding: .utf8))?
                    .split(separator: "\n").first { $0.hasPrefix("!") }.map(String.init)
                let detail = [firstError, Tr.mediaGeneratedFile(val: texFile.path)].compactMap { $0 }.joined(separator: " ")
                throw Failure(noteID: note, message: failure(command[0], detail: detail))
            }
        }
        let image = folder.appending(path: svg ? "tmp.svg" : "tmp.png")
        defer { try? FileManager.default.removeItem(at: image) }
        return try Data(contentsOf: image)
    }

    private static func failure(_ tool: String, detail: String) -> String {
        "\(Tr.mediaErrorExecuting(val: tool)) \(detail)"
    }

    private static func executable(_ name: String) -> URL? {
        let path = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        return (path + texFolders)
            .map { URL(filePath: $0).appending(path: name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
