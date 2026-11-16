import AppKit
import SwiftUI

/// A name being typed in its row, as a deck is renamed in the sidebar: a
/// new one at the end of a list, or the one being renamed in its place,
/// under the selection wash. What's wrong with the name shows under it as
/// it is typed, as Deck Options' alerts do. Shared by the profiles, the
/// note types and a note type's fields.
struct RowNameField: View {
    enum Ending { case submit, leave, cancel }

    @Binding var name: String
    let problem: String?
    let font: Font
    let height: CGFloat
    var prompt = Tr.deckConfigNamePrompt
    let end: (Ending) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(Tr.actionsName, text: $name, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .font(font)
                .labelsHidden()
                .focused($focused)
                .onSubmit { end(.submit) }
                .onExitCommand { end(.cancel) }
                .onChange(of: focused) { _, focused in
                    if !focused { end(.leave) }
                }
                // Asked of AppKit: on a sheet, setting the focus state as
                // the row appears doesn't bring the focus.
                .background(FieldFocus())
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRow(height: height, wash: Theme.Palette.selection)
            if let problem {
                OptionWarning(text: problem, level: .danger)
                    .padding(.vertical, Theme.Spacing.xSmall)
            }
        }
        .accessibilityValue(problem ?? "")
    }
}

/// Behind a text field, makes it the window's first responder once the
/// row is in the window, and selects its text so typing replaces it.
private struct FieldFocus: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // A turn later, when the field is in the window beside this view.
            DispatchQueue.main.async { [weak self] in
                guard let self, let window, let field = nearestField() else { return }
                if !window.isKeyWindow { window.makeKey() }
                window.makeFirstResponder(field)
            }
        }

        /// The editable field sharing the closest ancestor with this view.
        private func nearestField() -> NSTextField? {
            var ancestor = superview
            while let view = ancestor {
                if let field = Self.field(in: view) { return field }
                ancestor = view.superview
            }
            return nil
        }

        private static func field(in view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.isEditable { return field }
            for child in view.subviews {
                if let field = field(in: child) { return field }
            }
            return nil
        }
    }
}

extension View {
    /// A click selects the row at once and a double click opens or renames it.
    /// Two exclusive tap gestures would hold every click back until the
    /// double click's time ran out.
    func onClick(_ select: @escaping () -> Void, doubleClick: @escaping () -> Void) -> some View {
        gesture(TapGesture(count: 2).onEnded(doubleClick))
            .simultaneousGesture(TapGesture().onEnded(select))
    }

    /// A list row's height, and its wash reaching past the list's edge
    /// while the text keeps to it, as a deck row's does.
    func listRow(height: CGFloat, wash: Color) -> some View {
        padding(.horizontal, Theme.Layout.washOutset)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: Theme.Layout.listRowRadius).fill(wash))
            .padding(.horizontal, -Theme.Layout.washOutset)
    }
}
