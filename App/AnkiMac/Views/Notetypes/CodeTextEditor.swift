import AppKit
import SwiftUI

/// A plain monospaced text view for HTML and CSS: no smart quotes, dashes or
/// spelling corrections, which would corrupt a template.
struct CodeTextEditor: NSViewRepresentable {
    @Binding var text: String
    /// Set on the text view itself: SwiftUI's label stops at the wrapper.
    let label: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        // The block's wash shows through, as the editor's HTML source.
        scroll.drawsBackground = false
        let view = scroll.documentView as! NSTextView
        view.isRichText = false
        view.drawsBackground = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        view.textContainerInset = Theme.Editor.fieldInset
        view.delegate = context.coordinator
        view.string = text
        view.setAccessibilityLabel(label)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        view.setAccessibilityLabel(label)
        guard view.string != text else { return }
        let range = view.selectedRange()
        view.string = text
        // A selection beyond the new text would raise; fall back to the start.
        let length = (text as NSString).length
        view.setSelectedRange(range.upperBound <= length ? range : NSRange(location: length, length: 0))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: CodeTextEditor
        init(_ parent: CodeTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }
    }
}
