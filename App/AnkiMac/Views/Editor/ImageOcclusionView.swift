import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Desktop's mask editor: Select Image until there is one, then the tools
/// over the image.
struct ImageOcclusionView: View {
    @Bindable var editor: ImageOcclusionEditor

    var body: some View {
        Group {
            if let reason = editor.unreadable {
                ContentUnavailableView {
                    Label(Tr.notetypesErrorGettingImagecloze, systemImage: "exclamationmark.triangle")
                } description: {
                    Text(reason)
                }
            } else if editor.image == nil {
                picker
            } else {
                VStack(spacing: 0) {
                    toolbar
                        .padding(.horizontal, Theme.Spacing.medium)
                        .padding(.vertical, Theme.Spacing.small)
                    Divider()
                    MaskCanvas(
                        editor: editor, occlusions: editor.occlusions, selection: editor.selection, tool: editor.tool,
                        translucent: editor.translucent, imageSize: editor.imageSize)
                }
            }
        }
        .alert(
            editor.message ?? "", isPresented: Binding { editor.message != nil } set: { if !$0 { editor.message = nil } }
        ) {
            Button("OK") {}
        }
    }

    private var picker: some View {
        VStack(spacing: Theme.ImageOcclusion.pickerSpacing) {
            Button(Tr.notetypesIoSelectImage, systemImage: "photo") { chooseImage() }
                .buttonStyle(.borderedProminent)
            Button(Tr.notetypesIoPasteImageFromClipboard, systemImage: "doc.on.clipboard") { editor.pasteImage() }
        }
        .controlSize(.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        editor.useImage(at: url)
    }

    private var toolbar: some View {
        HStack(spacing: Theme.Spacing.small) {
            Picker(Tr.editingImageOcclusionMode, selection: $editor.tool) {
                ForEach(ImageOcclusionEditor.Tool.allCases, id: \.self) { tool in
                    Label(tool.title, systemImage: tool.symbol)
                        .help("\(tool.title) (\(tool.key.uppercased()))")
                        .tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            ControlGroup {
                button(Tr.undoUndo, "arrow.uturn.backward", "\u{2318}Z", disabled: editor.undoStack.isEmpty) {
                    editor.undo()
                }
                button(Tr.undoRedo, "arrow.uturn.forward", "\u{2318}Y", disabled: editor.redoStack.isEmpty) {
                    editor.redo()
                }
            }
            .fixedSize()
            ControlGroup {
                button(Tr.editingImageOcclusionZoomOut, "minus.magnifyingglass", "[") { editor.canvas?.zoomOut() }
                button(Tr.editingImageOcclusionZoomIn, "plus.magnifyingglass", "]") { editor.canvas?.zoomIn() }
                button(Tr.editingImageOcclusionZoomReset, "arrow.up.left.and.down.right.magnifyingglass", "F") {
                    editor.canvas?.fit()
                }
            }
            .fixedSize()
            Toggle(isOn: $editor.translucent) {
                Label(Tr.editingImageOcclusionToggleTranslucent, systemImage: "circle.lefthalf.filled")
            }
            .toggleStyle(.button)
            .help("\(Tr.editingImageOcclusionToggleTranslucent) (L)")
            ControlGroup {
                button(Tr.editingImageOcclusionDelete, "trash", "\u{232B}", disabled: editor.selection.isEmpty) {
                    editor.deleteSelection()
                }
                button(Tr.editingImageOcclusionDuplicate, "plus.square.on.square", "D", disabled: editor.selection.isEmpty) {
                    editor.duplicateSelection()
                }
                button(Tr.editingImageOcclusionGroup, "square.on.square.squareshape.controlhandles", "G", disabled: !editor.canGroup) {
                    editor.groupSelection()
                }
                button(Tr.editingImageOcclusionUngroup, "square.on.square.dashed", "U", disabled: !editor.canUngroup) {
                    editor.ungroupSelection()
                }
                button(Tr.editingImageOcclusionSelectAll, "checkmark.rectangle.stack", "A") { editor.selectAll() }
            }
            .fixedSize()
            Spacer(minLength: 0)
            Picker(Tr.editingImageOcclusionMode, selection: Binding { editor.occludeInactive } set: { editor.setOccludeInactive($0) }) {
                Text(Tr.notetypesHideAllGuessOne).tag(true)
                Text(Tr.notetypesHideOneGuessOne).tag(false)
            }
            .labelsHidden()
            .fixedSize()
            .help(Tr.editingImageOcclusionMode)
        }
        .labelStyle(.iconOnly)
        .controlSize(.small)
    }

    private func button(
        _ title: String, _ symbol: String, _ shortcut: String, disabled: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(title, systemImage: symbol, action: action)
            .help("\(title) (\(shortcut))")
            .disabled(disabled)
    }
}
