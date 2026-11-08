import Foundation
import UniformTypeIdentifiers
import WebKit

/// Serves the card web view, standing in for desktop's local media server:
///
///   anki://localhost/_reviewer.html   the reviewer page
///   anki://localhost/_anki/<path>     upstream's built web assets (bundle "web" folder)
///   anki://localhost/<file>           a file from the collection's media folder
final class AnkiSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "anki"
    static let reviewerURL = URL(string: "anki://localhost/_reviewer.html")!

    var mediaFolder: URL?
    var reviewerPage: () -> String = { "" }
    private let webRoot = Bundle.main.url(forResource: "web", withExtension: nil)

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else {
            task.didFailWithError(URLError(.badURL))
            return
        }
        let path = url.path(percentEncoded: false)
        if path == Self.reviewerURL.path() {
            respond(task, url: url, data: Data(reviewerPage().utf8), mimeType: "text/html")
            return
        }

        let file: URL?
        if path.hasPrefix("/_anki/") {
            file = webRoot.flatMap { Self.resolve(String(path.dropFirst("/_anki/".count)), in: $0) }
        } else {
            file = mediaFolder.flatMap { Self.resolve(String(path.dropFirst()), in: $0) }
        }
        // Media files are small and memory-mapped, so reading on the main
        // thread costs about as much as hopping off it.
        guard let file, let data = try? Data(contentsOf: file, options: .mappedIfSafe) else {
            task.didReceive(HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!)
            task.didFinish()
            return
        }
        let mimeType = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        respond(task, url: url, data: data, mimeType: mimeType)
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {
        // Every request finishes synchronously in start, so there is nothing to cancel.
    }

    private func respond(_ task: any WKURLSchemeTask, url: URL, data: Data, mimeType: String) {
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": mimeType, "Content-Length": String(data.count)])!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    /// The file under `root`, refusing paths that climb out of it.
    private static func resolve(_ relative: String, in root: URL) -> URL? {
        let file = root.appending(path: relative).standardizedFileURL
        guard file.path.hasPrefix(root.standardizedFileURL.path + "/") else { return nil }
        return file
    }
}
