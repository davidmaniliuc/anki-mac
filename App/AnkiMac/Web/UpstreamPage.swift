import AppKit
import SwiftUI
import WebKit

/// A page of upstream's SvelteKit build (statistics, card info, and later CSV
/// import, change notetype, image occlusion) in its own web view.
///
/// The page's `POST /_anki/<method>` calls go to `backendRequest`, normally
/// `CollectionModel.pageRequest`, and `bridgeCommand(...)` calls arrive in
/// `onBridgeCommand`, as desktop's `pycmd` bridge does. The page follows the
/// system light/dark appearance the way desktop's `load_sveltekit_page` does.
final class UpstreamPage: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let webView: PageWebView
    private let schemeHandler = AnkiSchemeHandler()

    /// Commands the page sends through `bridgeCommand`, such as `browserSearch: deck:x`.
    var onBridgeCommand: ((String) -> Void)?

    init(backendRequest: @escaping (String, Data) throws -> Data) {
        schemeHandler.servesPages = true
        schemeHandler.backendRequest = backendRequest
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: AnkiSchemeHandler.scheme)
        configuration.userContentController.addUserScript(WKUserScript(
            source: Self.bridgeScript + Self.styleScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = PageWebView(frame: .zero, configuration: configuration)
        super.init()
        configuration.userContentController.add(WeakMessageHandler(self), name: "anki")
        webView.navigationDelegate = self
        webView.onAppearanceChange = { [weak self] in self?.applyTheme() }
        #if DEBUG
        webView.isInspectable = true
        #endif
    }

    /// Loads a route such as `graphs` or `card-info/123`. The query string
    /// busts WebKit's cache so reloading shows fresh data.
    func load(_ route: String) {
        var components = URLComponents()
        components.scheme = AnkiSchemeHandler.scheme
        components.host = "localhost"
        components.path = "/" + route
        components.queryItems = [URLQueryItem(name: "cb", value: String(Date.now.timeIntervalSince1970))]
        components.fragment = webView.isDark ? "night" : nil
        if let url = components.url { webView.load(URLRequest(url: url)) }
    }

    func evaluate(_ script: String) {
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    /// Saves the page as one tall PDF page, as desktop's Save PDF does.
    func savePDF(named name: String, in window: NSWindow?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = name
        let save: (NSApplication.ModalResponse) -> Void = { [webView] response in
            guard response == .OK, let url = panel.url else { return }
            // Like desktop, print from the top: a scrolled dark page would otherwise start with a white strip.
            webView.evaluateJavaScript("window.scrollTo(0, 0);") { _, _ in
                webView.createPDF { result in
                    if let data = try? result.get() { try? data.write(to: url) }
                }
            }
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: save) } else { save(panel.runModal()) }
    }

    // MARK: Theme

    private func applyTheme() {
        let dark = webView.isDark
        evaluate("""
        (function() {
            const doc = document.documentElement, body = document.body.classList;
            doc.dataset.bsTheme = \(dark ? "'dark'" : "'light'");
            doc.classList.toggle('night-mode', \(dark));
            body.toggle('night_mode', \(dark)); body.toggle('nightMode', \(dark));
            body.toggle('macos-dark-mode', \(dark));
        })();
        """)
    }

    // MARK: WKNavigationDelegate, WKScriptMessageHandler

    func webView(
        _ webView: WKWebView, decidePolicyFor action: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        // Links in a page (the manual, forum posts) open in the browser.
        if action.navigationType == .linkActivated, let url = action.request.url, url.scheme != AnkiSchemeHandler.scheme {
            NSWorkspace.shared.open(url)
            return .cancel
        }
        return .allow
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if let command = message.body as? String { onBridgeCommand?(command) }
    }

    /// Upstream's pages get their font from the Qt host's stylesheet (webview.py's
    /// `standard_css`); without it they render in WebKit's default serif.
    private static let styleScript = """
    (function() {
        const style = document.createElement('style');
        style.textContent = 'html { font-family: -apple-system, "Helvetica Neue", sans-serif; } button { font-family: inherit; }';
        document.documentElement.appendChild(style);
    })();
    """

    /// What upstream's `bridgeCommand` expects of its host.
    private static let bridgeScript = """
    window.bridgeCommand = function(command, callback) {
        window.webkit.messageHandlers.anki.postMessage(command);
    };
    """
}

/// A web view without the right-click menu's Reload, Back and Inspect noise;
/// only Copy stays, which statistics and card info text needs.
final class PageWebView: WKWebView {
    var onAppearanceChange: (() -> Void)?

    var isDark: Bool {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        menu.items.removeAll { $0.identifier?.rawValue != "WKMenuItemIdentifierCopy" }
        super.willOpenMenu(menu, with: event)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }
}

/// Puts an `UpstreamPage`'s web view into the SwiftUI hierarchy.
struct UpstreamPageView: NSViewRepresentable {
    let page: UpstreamPage

    func makeNSView(context: Context) -> PageWebView { page.webView }
    func updateNSView(_ webView: PageWebView, context: Context) {}
}
