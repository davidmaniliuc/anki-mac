import AppKit
import FieldEditor
import WebKit

/// Renders MathJax for the editor, as desktop's editor does: MathJax's SVG
/// output in a hidden web view, drawn as an image in the field's text colour.
/// Rendering is asynchronous, so a field first shows the TeX and swaps in
/// the image when `didRender` fires.
@MainActor
final class MathRenderer: NSObject {
    static let shared = MathRenderer()
    static let didRender = Notification.Name("MathRendererDidRender")

    private struct Key: Hashable {
        let math: FieldMath
        let fontSize: CGFloat
        let color: String
    }

    private var webView: WKWebView?
    private var ready = false
    private var cache: [Key: (image: NSImage, descent: CGFloat)] = [:]
    private var queued: [Key] = []
    private var pending: Set<Key> = []

    /// The rendered image, or nil after starting to render it.
    func image(_ math: FieldMath, fontSize: CGFloat) -> (image: NSImage, descent: CGFloat)? {
        let key = Key(math: math, fontSize: fontSize, color: Self.hex(.textColor))
        if let cached = cache[key] { return cached }
        if pending.insert(key).inserted {
            queued.append(key)
            start()
            if ready { renderQueued() }
        }
        return nil
    }

    private func start() {
        guard webView == nil, let script = Bundle.main.url(forResource: "tex-svg-full", withExtension: "js"),
            let source = try? String(contentsOf: script, encoding: .utf8)
        else { return }
        let configuration = WKWebViewConfiguration()
        // The full build has every TeX package loaded; these add desktop's
        // to the default set. No font cache, so every SVG stands alone.
        let setup = """
            window.MathJax = { tex: { packages: { "[+]": ["noerrors", "mathtools", "mhchem"] } },
              svg: { fontCache: "none" }, startup: { typeset: false } };
            """
        configuration.userContentController.addUserScript(
            WKUserScript(source: setup, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController.addUserScript(
            WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.loadHTMLString("<!doctype html><html><body></body></html>", baseURL: nil)
        self.webView = webView
    }

    private func renderQueued() {
        guard let webView else { return }
        let keys = queued
        queued = []
        for key in keys {
            // Cloze answers show inside the maths, as desktop's `revealClozeAnswers`.
            let tex = key.math.tex.replacingOccurrences(
                of: #"\{\{c\d+::(.*?)(?:::.*?)?\}\}"#, with: "$1", options: .regularExpression)
            let script = """
                await MathJax.startup.promise;
                const svg = MathJax.tex2svg(tex, { display }).querySelector("svg");
                if (svg.innerHTML.includes("data-mjx-error")) return null;
                return [svg.outerHTML, svg.style.verticalAlign || "0ex"];
                """
            webView.callAsyncJavaScript(
                script, arguments: ["tex": tex, "display": key.math.display], in: nil, in: .page
            ) { [weak self] result in
                guard let self else { return }
                self.pending.remove(key)
                guard case .success(let value) = result, let pair = value as? [String], pair.count == 2,
                    let rendered = Self.image(svg: pair[0], verticalAlign: pair[1], key: key)
                else { return }
                self.cache[key] = rendered
                NotificationCenter.default.post(name: Self.didRender, object: self)
            }
        }
    }

    /// MathJax sizes its SVG in ex; AppKit's SVG support wants plain units,
    /// so ex becomes points at half the font size, as MathJax assumes.
    private static func image(svg: String, verticalAlign: String, key: Key) -> (image: NSImage, descent: CGFloat)? {
        let ex = key.fontSize / 2
        func points(_ value: String) -> CGFloat? {
            Double(value.replacingOccurrences(of: "ex", with: "")).map { CGFloat($0) * ex }
        }
        var svg = svg.replacingOccurrences(of: "currentColor", with: key.color)
        for attribute in ["width", "height"] {
            guard let range = svg.range(of: #"\#(attribute)="[-0-9.]+ex""#, options: .regularExpression) else { continue }
            let value = svg[range].dropFirst(attribute.count + 2).dropLast()
            if let size = points(String(value)) { svg.replaceSubrange(range, with: "\(attribute)=\"\(size)\"") }
        }
        guard let image = NSImage(data: Data(svg.utf8)), image.size.width > 0 else { return nil }
        return (image, -(points(verticalAlign) ?? 0))
    }

    private static func hex(_ color: NSColor) -> String {
        var hex = "#000000"
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            if let rgb = color.usingColorSpace(.sRGB) {
                hex = String(
                    format: "#%02x%02x%02x", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255),
                    Int(rgb.blueComponent * 255))
            }
        }
        return hex
    }
}

extension MathRenderer: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated {
            ready = true
            renderQueued()
        }
    }
}
