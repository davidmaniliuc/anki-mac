import Foundation
import UniformTypeIdentifiers
import WebKit

/// Serves the card web view, standing in for desktop's local media server:
///
///   anki://localhost/_reviewer.html   the reviewer page
///   anki://localhost/_anki/<path>     upstream's built web assets (bundle "web" folder)
///   anki://localhost/<file>           a file from the collection's media folder
///   anki://localhost/graphs, /card-info/<id>, /_app/...
///                                     upstream's SvelteKit pages (see `sveltekitRoutes`)
///   POST anki://localhost/_anki/<method>
///                                     a backend call from a page, answered by `backendRequest`
final class AnkiSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "anki"
    static let reviewerURL = URL(string: "anki://localhost/_reviewer.html")!

    var mediaFolder: URL?
    var reviewerPage: () -> String = { "" }
    /// Answers a page's `POST /_anki/<method>` with the method name and the
    /// protobuf body. Left unset, every call fails, so card web views (which show
    /// third-party JS) can't reach the backend; only `UpstreamPage` sets it. Pages the app
    /// shows are trusted, unlike card content, hence no allowlist beyond `PageBackendRPC`'s.
    var backendRequest: (String, Data) throws -> Data = { _, _ in
        throw PageRPCError(message: "Page calls are not allowed here")
    }
    /// Whether SvelteKit routes and /_app assets are served; only upstream-page web views want them.
    var servesPages = false
    /// The top-level paths mediasrv.py's `get_sveltekit_route` serves from the SvelteKit build.
    private static let sveltekitRoutes: Set<String> = [
        "graphs", "congrats", "card-info", "change-notetype", "deck-options", "import-anki-package",
        "import-csv", "import-page", "image-occlusion", "preferences", "editor",
    ]
    private let webRoot = Bundle.main.url(forResource: "web", withExtension: nil)

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else {
            task.didFailWithError(URLError(.badURL))
            return
        }
        let path = url.path(percentEncoded: false)
        if path.hasPrefix("/_anki/"), task.request.httpMethod == "POST" {
            let method = String(path.dropFirst("/_anki/".count))
            do {
                let data = try backendRequest(method, Self.body(of: task.request))
                respond(task, url: url, data: data, mimeType: "application/binary")
            } catch {
                // Like mediasrv: a 500 whose body is the message, which the page shows.
                respond(task, url: url, status: 500, data: Data(String(describing: error).utf8), mimeType: "text/plain; charset=utf-8")
            }
            return
        }
        if path == Self.reviewerURL.path() {
            respond(task, url: url, data: Data(reviewerPage().utf8), mimeType: "text/html")
            return
        }

        // SvelteKit pages: the route is served the app shell, and /_app holds its assets.
        let first = path.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
        if servesPages, Self.sveltekitRoutes.contains(first) {
            respondShell(task, url: url)
            return
        }

        let file: URL?
        if servesPages, path.hasPrefix("/_app/") {
            file = webRoot.flatMap { Self.resolve("sveltekit" + path, in: $0) }
        } else if path.hasPrefix("/_anki/") {
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
        // Module scripts are only run with a JavaScript type, which UTType doesn't give .mjs.
        let mimeType = ["mjs": "text/javascript", "js": "text/javascript"][file.pathExtension]
            ?? UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        respond(task, url: url, data: data, mimeType: mimeType)
    }

    /// The SvelteKit app shell. Its CSP meta tag is dropped, as mediasrv does,
    /// since it names the dev server's origin rather than ours.
    private func respondShell(_ task: any WKURLSchemeTask, url: URL) {
        guard let shell = webRoot?.appending(path: "sveltekit/index.html"),
            var html = try? String(contentsOf: shell, encoding: .utf8)
        else {
            respond(task, url: url, status: 404, data: Data(), mimeType: "text/plain")
            return
        }
        html = html.replacingOccurrences(
            of: #"<meta http-equiv="content-security-policy"[^>]*>"#, with: "", options: .regularExpression)
        respond(task, url: url, data: Data(html.utf8), mimeType: "text/html")
    }

    /// WebKit hands bodies of requests made by `fetch` over as a stream.
    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {
        // Every request finishes synchronously in start, so there is nothing to cancel.
    }

    private func respond(_ task: any WKURLSchemeTask, url: URL, status: Int = 200, data: Data, mimeType: String) {
        let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/1.1",
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
