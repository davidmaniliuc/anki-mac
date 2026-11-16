import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Desktop's mask editor: Select Image until there is one, then the tools
/// over the image. Its bar is the format bar's, the Mask and Note tabs first.
struct ImageOcclusionView: View {
    let noteEditor: NoteEditorModel
    @Bindable var editor: ImageOcclusionEditor
    var barHeight: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            MaskBar(noteEditor: noteEditor, editor: editor)
                .padding(.horizontal, Theme.Spacing.medium)
                .padding(.vertical, barHeight == nil ? Theme.Spacing.small : 0)
                .frame(minHeight: barHeight)
            Theme.Palette.hairline.frame(height: 1)
            if let reason = editor.unreadable {
                ContentUnavailableView {
                    Label(Tr.notetypesErrorGettingImagecloze, systemImage: "exclamationmark.triangle")
                } description: {
                    Text(reason)
                }
            } else if editor.image == nil {
                MaskImagePicker(editor: editor)
            } else {
                MaskCanvas(
                    editor: editor, occlusions: editor.occlusions, selection: editor.selection, tool: editor.tool,
                    translucent: editor.translucent, imageSize: editor.imageSize)
            }
        }
        .alert(
            editor.message ?? "", isPresented: Binding { editor.message != nil } set: { if !$0 { editor.message = nil } }
        ) {
            Button("OK") {}
        }
    }
}

/// Desktop's Mask and Note tabs, leading the bar of whichever is shown.
struct OcclusionTabs: View {
    let noteEditor: NoteEditorModel
    let editor: ImageOcclusionEditor

    var body: some View {
        QuietSegments(
            selection: Binding { editor.tab } set: {
                noteEditor.commitPendingEdits()
                editor.tab = $0
            }, choices: [.masks, .note]
        ) {
            switch $0 {
            case .masks: Tr.notetypesOcclusionMask
            case .note: Tr.notetypesOcclusionNote
            }
        }
        .accessibilityLabel(Tr.notetypesImageOcclusionName)
    }
}

/// Before there is an image: a photo glyph over Select Image and Paste,
/// and the whole tab takes a dropped image, washed while one is over it.
private struct MaskImagePicker: View {
    let editor: ImageOcclusionEditor
    @State private var targeted = false

    var body: some View {
        VStack(spacing: Theme.Spacing.medium) {
            Image(systemName: "photo")
                .font(Theme.ImageOcclusion.pickerSymbol)
                .foregroundStyle(Theme.Palette.tertiary)
                .accessibilityHidden(true)
            HStack(spacing: Theme.Spacing.small) {
                Button(Tr.notetypesIoSelectImage, action: chooseImage)
                Button(Tr.notetypesIoPasteImageFromClipboard) { editor.pasteImage() }
            }
            .buttonStyle(ChipButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Theme.Layout.rowRadius)
                .fill(targeted ? Theme.Palette.hover : .clear)
                .padding(Theme.Spacing.medium)
        )
        .contentShape(Rectangle())
        .dropDestination(for: DroppedImage.self) { images, _ in
            guard let image = images.first else { return false }
            editor.useImage(image.data, name: image.name)
            return true
        } isTargeted: { targeted = $0 }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        editor.useImage(at: url)
    }
}

/// The tabs, then desktop's tools as the format bar's quiet glyphs in
/// groups split by hairlines: the drawing tools, the fill with its colour
/// under it, undo, the view, the selection, and last the mode as a quiet
/// menu. Only the tabs and the mode show until there is an image.
private struct MaskBar: View {
    let noteEditor: NoteEditorModel
    @Bindable var editor: ImageOcclusionEditor

    var body: some View {
        FlowLayout(spacing: Theme.Spacing.xxSmall) {
            FormatGroup {
                OcclusionTabs(noteEditor: noteEditor, editor: editor)
            }
            if editor.image != nil {
                FormatGroup {
                    ForEach(ImageOcclusionEditor.Tool.allCases.filter { $0 != .fill }, id: \.self) { tool in
                        button(tool.title, tool.symbol, String(tool.key).uppercased(), selected: editor.tool == tool) {
                            editor.tool = tool
                        }
                    }
                    fill
                }
                FormatGroup {
                    button(Tr.undoUndo, "arrow.uturn.backward", "\u{2318}Z", disabled: editor.undoStack.isEmpty) {
                        editor.undo()
                    }
                    button(Tr.undoRedo, "arrow.uturn.forward", "\u{21E7}\u{2318}Z", disabled: editor.redoStack.isEmpty) {
                        editor.redo()
                    }
                }
                FormatGroup {
                    button(Tr.editingImageOcclusionZoomOut, "minus.magnifyingglass", "[") { editor.canvas?.zoomOut() }
                    button(Tr.editingImageOcclusionZoomIn, "plus.magnifyingglass", "]") { editor.canvas?.zoomIn() }
                    button(Tr.editingImageOcclusionZoomReset, "arrow.up.left.and.down.right.magnifyingglass", "F") {
                        editor.canvas?.fit()
                    }
                    button(
                        Tr.editingImageOcclusionToggleTranslucent, "circle.lefthalf.filled", "L", selected: editor.translucent
                    ) {
                        editor.translucent.toggle()
                    }
                }
                FormatGroup {
                    let none = editor.selection.isEmpty
                    button(Tr.editingImageOcclusionDelete, "trash", "\u{232B}", disabled: none) { editor.deleteSelection() }
                    button(Tr.editingImageOcclusionDuplicate, "plus.square.on.square", "D", disabled: none) {
                        editor.duplicateSelection()
                    }
                    button(Tr.editingImageOcclusionGroup, "square.on.square.squareshape.controlhandles", "G", disabled: !editor.canGroup) {
                        editor.groupSelection()
                    }
                    button(Tr.editingImageOcclusionUngroup, "square.on.square.dashed", "U", disabled: !editor.canUngroup) {
                        editor.ungroupSelection()
                    }
                    button(Tr.editingImageOcclusionSelectAll, "checkmark.rectangle.stack", "A") { editor.selectAll() }
                    alignment
                }
            }
            mode
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .labelStyle(.iconOnly)
    }

    /// The fill tool, its colour under the glyph as the text colour's is;
    /// the chevron opens the colour panel, and a pick takes up the tool,
    /// as desktop's colour picker opens from it.
    private var fill: some View {
        let tool = ImageOcclusionEditor.Tool.fill
        let color = MaskCanvasView.color(editor.fillColor) ?? .systemYellow
        return HStack(spacing: 0) {
            Button {
                editor.tool = tool
            } label: {
                glyph(tool.title, tool.symbol)
                    .overlay(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: Theme.Editor.swatchSize.height / 2)
                            .fill(Color(nsColor: color))
                            .frame(width: Theme.Editor.swatchSize.width, height: Theme.Editor.swatchSize.height)
                            .padding(.bottom, Theme.Spacing.xxSmall)
                    }
            }
            .buttonStyle(QuietButtonStyle(selected: editor.tool == tool, inset: 0))
            .help(helpTag(tool.title, String(tool.key).uppercased()))
            Button {
                // The panel outlives the editor; it mustn't keep the image.
                EditorColorPanel.shared.show(color) { [weak editor] picked in
                    guard let editor else { return }
                    let (red, green, blue) = EditorColors.components(Color(nsColor: picked))
                    editor.fillColor = String(format: "#%02x%02x%02x", red, green, blue)
                    editor.tool = tool
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(Theme.Editor.chevronSymbol)
                    .frame(width: Theme.Editor.chevronWidth, height: Theme.Editor.buttonSize.height)
            }
            .buttonStyle(QuietButtonStyle(inset: 0))
            .help("Change Color")
            .accessibilityLabel("Change Color")
        }
    }

    private var alignment: some View {
        Menu {
            ForEach(MaskCanvasView.Alignment.allCases, id: \.self) { alignment in
                // The canvas takes the Shift shortcuts, so typing in a field never aligns.
                Button("\(alignment.title) (\u{21E7}\(alignment.key.uppercased()))", systemImage: alignment.symbol) {
                    editor.canvas?.align(alignment)
                }
            }
        } label: {
            glyph(Tr.editingImageOcclusionAlignment, "align.horizontal.center")
        }
        .menuStyle(.button)
        .buttonStyle(QuietButtonStyle(inset: 0))
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(editor.selection.isEmpty)
        .help(Tr.editingImageOcclusionAlignment)
    }

    /// Hide All, Guess One or Hide One, Guess One, as Add's quiet menus.
    private var mode: some View {
        Menu {
            Picker(Tr.editingImageOcclusionMode, selection: Binding { editor.occludeInactive } set: {
                editor.setOccludeInactive($0)
            }) {
                Text(modeTitle(true)).tag(true)
                Text(modeTitle(false)).tag(false)
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            QuietMenuLabel(value: modeTitle(editor.occludeInactive))
                // As tall as the tabs, its hover wash spilling over, so the
                // bar keeps the Browser's column titles' height.
                .padding(.vertical, -Theme.Spacing.xxSmall)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Tr.editingImageOcclusionMode)
        .accessibilityLabel(Tr.editingImageOcclusionMode)
        .accessibilityValue(modeTitle(editor.occludeInactive))
    }

    private func modeTitle(_ occludeInactive: Bool) -> String {
        occludeInactive ? Tr.notetypesHideAllGuessOne : Tr.notetypesHideOneGuessOne
    }

    private func glyph(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(Theme.Editor.buttonSymbol)
            .frame(width: Theme.Editor.buttonSize.width, height: Theme.Editor.buttonSize.height)
    }

    /// The name over upstream's "Shortcut key: …" line, as Preview's.
    private func helpTag(_ title: String, _ key: String) -> String {
        "\(title)\n\(Tr.actionsShortcutKey(val: key))"
    }

    private func button(
        _ title: String, _ symbol: String, _ key: String, selected: Bool = false, disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) { glyph(title, symbol) }
            .buttonStyle(QuietButtonStyle(selected: selected, inset: 0))
            .help(helpTag(title, key))
            .disabled(disabled)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// An image dropped from Finder, Photos or a web page, read as it arrives
/// since the file it comes in is only lent for the drop.
private struct DroppedImage: Transferable {
    let data: Data
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            DroppedImage(data: try Data(contentsOf: received.file), name: received.file.lastPathComponent)
        }
    }
}
