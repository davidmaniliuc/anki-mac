import AppKit
import WebKit

/// Owns the one web view that shows cards. It is created at launch and loads
/// upstream's reviewer page (reviewer.js, reviewer.css) straight away, so the
/// first card only has to swap HTML into an already-painted page, as desktop
/// does with `_showQuestion` / `_showAnswer`.
final class ReviewerWebController: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    /// Created by `prepare`; creating a WKWebView takes tens of milliseconds.
    private(set) var webView: WKWebView?
    private let schemeHandler = AnkiSchemeHandler()
    private var isReady = false
    private var pendingScripts: [String] = []
    private var nightMode = false
    private var shownCallbacks: [() -> Void] = []

    /// Commands from the page: `ans` (Return in the typing box), `play:q:0`.
    var onCommand: ((String) -> Void)?
    /// True while a text box on the card (type-in-the-answer) has focus, so
    /// study shortcuts let keys through.
    private(set) var isEditingText = false

    var mediaFolder: URL? {
        get { schemeHandler.mediaFolder }
        set { schemeHandler.mediaFolder = newValue }
    }

    func prepare() {
        guard webView == nil else { return }
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: AnkiSchemeHandler.scheme)
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.addUserScript(WKUserScript(
            source: Self.bridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView = webView
        configuration.userContentController.add(WeakMessageHandler(self), name: "anki")
        webView.navigationDelegate = self
        #if DEBUG
        webView.isInspectable = true
        #endif
        schemeHandler.reviewerPage = { [unowned self] in Self.page(nightMode: nightMode) }
        webView.load(URLRequest(url: AnkiSchemeHandler.reviewerURL))
    }

    func showQuestion(_ question: String, answer: String, bodyClass: String) {
        call("_showQuestion", question, answer, "\(bodyClass) \(themeClasses)")
    }

    func showAnswer(_ answer: String) {
        call("_showAnswer", answer, "")
    }

    /// Runs `done` once everything queued so far is in the page.
    func whenShown(_ done: @escaping () -> Void) {
        shownCallbacks.append(done)
        // Same point desktop's bench add-on measures: the card's HTML is in
        // the page. Painting follows on the next frame.
        evaluate("_queueAction(() => pycmd('_shown'));")
    }

    func drawFlag(_ flag: Int) {
        evaluate("_drawFlag(\(flag));")
    }

    func clear() {
        isEditingText = false
        evaluate("_queueAction(() => { document.getElementById('qa').innerHTML = ''; });")
    }

    func setNightMode(_ enabled: Bool) {
        guard enabled != nightMode else { return }
        nightMode = enabled
        let classes = Self.themeBodyClasses(nightMode: enabled)
        evaluate("""
            document.documentElement.classList.toggle('night-mode', \(enabled));
            document.documentElement.dataset.bsTheme = '\(enabled ? "dark" : "light")';
            document.body.classList.remove('nightMode', 'night_mode', 'macos-dark-mode');
            document.body.classList.add(...'\(classes)'.split(' ').filter(Boolean));
            """)
    }

    // MARK: Page

    private var themeClasses: String { Self.themeBodyClasses(nightMode: nightMode) }

    /// As aqt's `theme_manager.body_class()` on macOS, following the system appearance.
    private static func themeBodyClasses(nightMode: Bool) -> String {
        nightMode ? "isMac nightMode night_mode macos-dark-mode fancy" : "isMac fancy"
    }

    /// Desktop's `Reviewer.revHtml` inside `AnkiWebView.stdHtml`.
    private static func page(nightMode: Bool) -> String {
        """
        <!doctype html>
        <html class="\(nightMode ? "night-mode" : "")" dir="ltr" data-bs-theme="\(nightMode ? "dark" : "light")">
        <head>
        <meta charset="utf-8">
        <link rel="stylesheet" href="/_anki/css/webview.css">
        <style>
        body { background-color: var(--canvas); }
        html { font-family: -apple-system, "Helvetica Neue", sans-serif; }
        </style>
        <link rel="stylesheet" href="/_anki/css/reviewer.css">
        </head>
        <body class="\(themeBodyClasses(nightMode: nightMode))">
        <script src="/_anki/js/webview.js"></script>
        <script src="/_anki/js/reviewer.js"></script>
        <div id="_mark" hidden>&#x2605;</div>
        <div id="_flag" hidden>&#x2691;</div>
        <div id="qa" dir="auto"></div>
        </body>
        </html>
        """
    }

    /// Desktop gets `pycmd` / `bridgeCommand` from Qt's web channel.
    private static let bridgeScript = """
        window.pycmd = function (cmd) { window.webkit.messageHandlers.anki.postMessage(cmd); return false; };
        window.bridgeCommand = function (cmd) { window.webkit.messageHandlers.anki.postMessage(cmd); };
        const isText = (el) => el && (el.tagName === "INPUT" || el.tagName === "TEXTAREA" || el.isContentEditable);
        document.addEventListener("focusin", (e) => { if (isText(e.target)) pycmd("_editing:1"); });
        document.addEventListener("focusout", (e) => { if (isText(e.target)) pycmd("_editing:0"); });
        """

    // MARK: Script calls

    private func call(_ function: String, _ arguments: String...) {
        guard let data = try? JSONSerialization.data(withJSONObject: arguments),
              let json = String(data: data, encoding: .utf8)
        else { return }
        evaluate("\(function).apply(null, \(json));")
    }

    private func evaluate(_ script: String) {
        guard isReady else {
            pendingScripts.append(script)
            return
        }
        webView?.evaluateJavaScript(script) { _, error in
            if let error { print("reviewer script failed: \(error)") }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        BenchDriver.trace("reviewer_page_loaded")
        isReady = true
        let scripts = pendingScripts
        pendingScripts = []
        scripts.forEach(evaluate)
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        // Links on cards open in the browser instead of replacing the reviewer.
        if action.navigationType == .linkActivated, let url = action.request.url,
           url.scheme != AnkiSchemeHandler.scheme
        {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isReady = false
        isEditingText = false
        webView.load(URLRequest(url: AnkiSchemeHandler.reviewerURL))
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let command = message.body as? String else { return }
        if command == "_shown" {
            if !shownCallbacks.isEmpty { shownCallbacks.removeFirst()() }
            return
        }
        if command.hasPrefix("_editing:") {
            isEditingText = command == "_editing:1"
            return
        }
        onCommand?(command)
    }
}

/// WKUserContentController retains its handlers; this breaks the cycle.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?

    init(_ target: any WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
