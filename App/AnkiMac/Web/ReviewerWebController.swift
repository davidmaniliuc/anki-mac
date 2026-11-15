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

    /// Desktop's `onCopy`: copies the selected text with its formatting.
    func copySelection() {
        guard let webView else { return }
        NSApp.sendAction(#selector(NSText.copy(_:)), to: webView, from: nil)
    }

    func showQuestion(_ question: String, answer: String, bodyClass: String) {
        call("_showQuestion", question, answer, "\(bodyClass) \(themeClasses)")
    }

    /// `bodyClass` is for a card shown straight on its answer, as the previewer's Back Side Only.
    func showAnswer(_ answer: String, bodyClass: String? = nil) {
        // The typing box is replaced, and a removed element sends no focusout.
        isEditingText = false
        call("_showAnswer", answer, bodyClass.map { "\($0) \(themeClasses)" } ?? "")
    }

    /// What is in the type-in-the-answer box ("" when there is none).
    func typedAnswer() async -> String {
        guard isReady, let webView else { return "" }
        let value = try? await webView.evaluateJavaScript("getTypedAnswer();")
        return value as? String ?? ""
    }

    /// Runs `done` once everything queued so far is in the page.
    func whenShown(_ done: @escaping () -> Void) {
        shownCallbacks.append(done)
        // Same point desktop's bench add-on measures: the card's HTML is in
        // the page. Painting follows on the next frame.
        evaluate("_queueAction(() => pycmd('_shown'));")
    }

    /// The card layout editor's "Add Mobile Class".
    func emulateMobile(_ enabled: Bool) {
        evaluate("_emulateMobile(\(enabled));")
    }

    /// The card's sounds that get a player in place of their play button:
    /// JSON of each one's waveform and length by its name ("q:0"). Runs
    /// once the card queued before it is on the page.
    func showSounds(_ json: String) {
        evaluate("_queueAction(() => _ankiMacSounds(\(json)));")
    }

    /// Which players are playing and how far they are, as JSON, or "null".
    func showPlayback(_ json: String) {
        evaluate("_ankiMacPlayback(\(json));")
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
        <style>
        /* The main window's canvas, so the card sits on it with no edge. */
        html:root { --canvas: \(Theme.Palette.css(Theme.Palette.canvasHex.light)); }
        html.night-mode:root { --canvas: \(Theme.Palette.css(Theme.Palette.canvasHex.dark)); }
        /* No rubber-banding: the card sits in a fixed column, not a page. */
        html, body { overscroll-behavior: none; }
        /* The play button as a quiet control: a raised disc and a soft
           triangle that darkens under the pointer and dips when pressed. Each rule is no more
           specific than upstream's, so a note type's own styling still wins. */
        html:root {
            --replay-disc: \(Theme.Palette.css(Theme.Palette.raisedHex.light));
            --replay-edge: rgba(0, 0, 0, 0.1);
            --replay-rest: \(Theme.Palette.css(Theme.Palette.secondaryHex.light));
            --replay-over: \(Theme.Palette.css(Theme.Palette.textHex.light));
            --replay-faded: \(Theme.Palette.css(Theme.Palette.tertiaryHex.light));
            --replay-focus: \(Theme.Palette.css(Theme.Palette.accentHex.light));
        }
        html.night-mode:root {
            --replay-disc: \(Theme.Palette.css(Theme.Palette.raisedHex.dark));
            --replay-edge: rgba(255, 255, 255, 0.1);
            --replay-rest: \(Theme.Palette.css(Theme.Palette.secondaryHex.dark));
            --replay-over: \(Theme.Palette.css(Theme.Palette.textHex.dark));
            --replay-faded: \(Theme.Palette.css(Theme.Palette.tertiaryHex.dark));
            --replay-focus: \(Theme.Palette.css(Theme.Palette.accentHex.dark));
        }
        .replay-button { --replay-glyph: var(--replay-rest); border-radius: 50%; outline-offset: 1px; }
        .replay-button:hover { --replay-glyph: var(--replay-over); }
        .replay-button:active { opacity: 0.7; }
        .replay-button:focus-visible { outline: 2px solid var(--replay-focus); }
        .replay-button svg circle { fill: var(--replay-disc); stroke: var(--replay-edge); stroke-width: 1.6px; }
        .replay-button svg path {
            fill: var(--replay-glyph); stroke: var(--replay-glyph); stroke-width: 6px; stroke-linejoin: round;
            transform-origin: 32px 32px; transform: scale(0.56);
            transition: fill 0.12s ease-out, stroke 0.12s ease-out;
        }
        /* A sound with a file is a player, as in the editor's fields: play
           or pause, its waveform, its length. It never sets `display`, so a
           note type that hides play buttons still hides it. */
        .replay-button.sound-player {
            align-items: center; gap: \(Int(Theme.Sound.cardGap))px; height: \(Int(Theme.Sound.cardHeight))px;
            padding: 0 \(Int(Theme.Sound.cardPadding))px; box-sizing: border-box;
            border-radius: \(Int(Theme.Sound.cardHeight / 2))px;
            background: var(--replay-disc); box-shadow: inset 0 0 0 1px var(--replay-edge);
            color: var(--replay-rest); cursor: default; direction: ltr; opacity: 1;
            font: 500 \(Theme.Sound.cardTimeSize)px ui-rounded, -apple-system, sans-serif;
            font-variant-numeric: tabular-nums; line-height: 1; text-align: left;
            -webkit-user-select: none; user-select: none;
        }
        .replay-button.sound-player svg { width: 14px; height: 14px; flex: none; }
        .replay-button.sound-player svg path { fill: var(--replay-over); stroke: none; transform: none; }
        .sound-player .sound-bars {
            display: flex; align-items: center; gap: \(Int(Theme.Sound.barGap))px;
            height: \(Int(Theme.Sound.cardBarMaxHeight))px;
        }
        .sound-player .sound-bars i {
            width: \(Int(Theme.Sound.barWidth))px; min-height: \(Int(Theme.Sound.barWidth))px;
            border-radius: \(Int(Theme.Sound.barWidth))px; background: var(--replay-rest);
        }
        .sound-player.current .sound-bars i { background: var(--replay-faded); }
        .sound-player.current .sound-bars i.played { background: var(--replay-over); }
        .sound-player .sound-time { min-width: 4ch; }
        </style>
        </head>
        <body class="\(themeBodyClasses(nightMode: nightMode))">
        <script src="/_anki/js/webview.js"></script>
        <script src="/_anki/js/reviewer.js"></script>
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
        // Sound players. Swift names the sounds that have a file and sends
        // their waveforms (_ankiMacSounds), then how far the one playing
        // has got (_ankiMacPlayback). A click plays or pauses; a drag or a
        // sideways swipe along the player moves through the sound.
        (() => {
            let waves = {}, now = null;
            const play = '<path d="M3.5 2.3v11.4a.9.9 0 0 0 1.37.77l9.2-5.7a.9.9 0 0 0 0-1.54l-9.2-5.7A.9.9 0 0 0 3.5 2.3z"/>';
            const pause = '<path d="M3 2.6a1 1 0 0 1 1-1h1.6a1 1 0 0 1 1 1v10.8a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1zM9.4 2.6a1 1 0 0 1 1-1H12a1 1 0 0 1 1 1v10.8a1 1 0 0 1-1 1h-1.6a1 1 0 0 1-1-1z"/>';
            const clock = (seconds) => Math.floor(seconds / 60) + ":" + String(seconds % 60).padStart(2, "0");
            const isCurrent = (ref) => !!now && now.refs.includes(ref);

            function paint(a) {
                const ref = a.dataset.ref, wave = waves[ref], on = isCurrent(ref);
                const glyph = on && now.playing ? pause : play;
                if (a._glyph !== glyph) { a._glyph = glyph; a.querySelector("svg").innerHTML = glyph; }
                a.classList.toggle("current", on);
                const bars = a.querySelectorAll(".sound-bars i");
                bars.forEach((bar, index) => bar.classList.toggle("played", on && index + 0.5 <= now.progress * bars.length));
                // Its length at rest, how far in while it plays.
                const seconds = on ? Math.floor(now.elapsed) : wave.duration === null ? null : Math.round(wave.duration);
                a.querySelector(".sound-time").textContent = seconds === null ? "" : clock(seconds);
            }

            function build(a) {
                const ref = a.dataset.ref, wave = waves[ref];
                a.classList.add("sound-player");
                a.removeAttribute("onclick");
                a.innerHTML = '<svg class="playImage" viewBox="0 0 16 16"></svg><span class="sound-bars">'
                    + wave.levels.map((level) => `<i style="height: ${Math.round(level * 100)}%"></i>`).join("")
                    + '</span><span class="sound-time"></span>';
                const seek = (progress) => {
                    progress = Math.max(0, Math.min(1, progress));
                    if (isCurrent(ref)) {
                        now.progress = progress;
                        if (wave.duration !== null) now.elapsed = progress * wave.duration;
                        paint(a);
                    }
                    pycmd(`seek:${ref}:${progress.toFixed(4)}`);
                };
                const toggle = () => pycmd(isCurrent(ref) ? "audiopause" : "play:" + ref);
                let drag = null;
                a.addEventListener("pointerdown", (e) => {
                    if (e.button !== 0) return;
                    a.setPointerCapture(e.pointerId);
                    drag = { x: e.clientX, moved: false };
                });
                a.addEventListener("pointermove", (e) => {
                    if (!drag) return;
                    if (Math.abs(e.clientX - drag.x) > \(Int(Theme.Sound.dragSlop))) drag.moved = true;
                    if (!drag.moved) return;
                    const bars = a.querySelector(".sound-bars").getBoundingClientRect();
                    seek((e.clientX - bars.left) / bars.width);
                });
                a.addEventListener("pointerup", () => {
                    if (drag && !drag.moved) toggle();
                    drag = null;
                });
                a.addEventListener("pointercancel", () => { drag = null; });
                // The pointer's clicks were answered above; this leaves the keyboard's.
                a.addEventListener("click", (e) => {
                    e.preventDefault();
                    if (e.detail === 0) toggle();
                });
                a.addEventListener("wheel", (e) => {
                    if (Math.abs(e.deltaX) <= Math.abs(e.deltaY)) return;
                    e.preventDefault();
                    const width = a.querySelector(".sound-bars").getBoundingClientRect().width;
                    seek((isCurrent(ref) ? now.progress : 0) - e.deltaX / width);
                }, { passive: false });
            }

            const players = () => [...document.querySelectorAll(".replay-button[data-ref]")].filter((a) => waves[a.dataset.ref]);
            window._ankiMacSounds = (sounds) => {
                waves = sounds;
                for (const a of players()) {
                    if (!a.classList.contains("sound-player")) build(a);
                    paint(a);
                }
            };
            window._ankiMacPlayback = (state) => {
                now = state;
                players().filter((a) => a.classList.contains("sound-player")).forEach(paint);
            };
        })();
        let hadSelection = false;
        document.addEventListener("selectionchange", () => {
            const has = !getSelection().isCollapsed;
            if (has !== hadSelection) { hadSelection = has; pycmd("_selection:" + (has ? 1 : 0)); }
        });
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
            CardLinks.open(url, from: webView.window)
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
final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?

    init(_ target: any WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
