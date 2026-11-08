import SwiftUI
import WebKit

/// Puts the long-lived reviewer web view into the SwiftUI hierarchy.
struct CardWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}
}
