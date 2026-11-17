import SwiftUI
import UniformTypeIdentifiers

/// Where a deck dragged in the main sidebar would land. Decks sort by name,
/// so a drop only picks the parent; the line shows the level, not a place.
enum DeckDropTarget: Equatable {
    /// Inside the deck under the pointer.
    case into(Int64)
    /// Beside the rows around a line at `y`, `depth` levels in, under
    /// `parent` (0 for the top level).
    case beside(y: CGFloat, depth: Int, parent: Int64)

    var parent: Int64 {
        switch self {
        case .into(let id): id
        case .beside(_, _, let parent): parent
        }
    }
}

/// A deck being dragged in the main sidebar, the rows' frames, and where it
/// would land. One drop target covers the whole list, rather than one per
/// row, so the gaps between rows take drops too.
@Observable final class DeckDropState {
    nonisolated static let space = "DeckDrop"

    /// Said by the row's `onDrag`; it stays after the drag ends.
    var dragged: Int64?
    var target: DeckDropTarget?
    /// In the list's coordinates, measured by each row.
    @ObservationIgnored var frames: [Int64: CGRect] = [:]
    @ObservationIgnored fileprivate var spring: Task<Void, Never>?
    /// The folded decks this drag opened, which fold again unless it drops in them.
    @ObservationIgnored fileprivate var sprung: [Int64] = []
}

/// A dragged deck travels as text, so no custom type needs declaring.
enum DeckDrag {
    nonisolated private static let prefix = "anki-mac-deck:"

    static func provider(_ deckID: Int64) -> NSItemProvider {
        NSItemProvider(object: (prefix + String(deckID)) as NSString)
    }

    nonisolated static func deckID(_ text: String?) -> Int64? {
        guard let text, text.hasPrefix(prefix) else { return nil }
        return Int64(text.dropFirst(prefix.count))
    }
}

/// A deck row on screen, top to bottom, as the drop sees it.
struct DeckDropRow {
    /// Its parents' ids, then its own.
    let path: [Int64]
    let filtered: Bool
    /// Has subdecks it isn't showing.
    let folded: Bool
    let frame: CGRect

    var id: Int64 { path[path.count - 1] }
    var depth: Int { path.count - 1 }
}

extension DeckDropTarget {
    /// The middle of a row drops inside it; its edges, the gaps between rows
    /// and the space under the list drop beside, at the level the pointer is
    /// over: the further left, the closer to the top level. Nothing lands
    /// inside itself or in a filtered deck.
    static func at(_ point: CGPoint, rows: [DeckDropRow], dragged: Int64) -> DeckDropTarget? {
        guard let last = rows.indices.last else { return .beside(y: 0, depth: 0, parent: 0) }
        let byID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func canHold(_ parent: Int64) -> Bool {
            guard let row = byID[parent] else { return parent == 0 }
            return !row.filtered && !row.path.contains(dragged)
        }

        let hit = rows.firstIndex { $0.frame.minY <= point.y && point.y < $0.frame.maxY }
        if let hit {
            let frame = rows[hit].frame
            let edge = frame.height * Theme.Layout.dropEdgeShare
            if point.y >= frame.minY + edge, point.y < frame.maxY - edge {
                return canHold(rows[hit].id) ? .into(rows[hit].id) : nil
            }
        }

        // The rows either side of the line.
        let above = hit.map { point.y < rows[$0].frame.midY ? $0 - 1 : $0 }
            ?? (rows.lastIndex { $0.frame.midY <= point.y } ?? -1)
        let below = above + 1 <= last ? above + 1 : nil
        let y: CGFloat = switch (above >= 0, below) {
        case (true, let below?): (rows[above].frame.maxY + rows[below].frame.minY) / 2
        case (true, nil): rows[above].frame.maxY + 1
        case (false, _): rows[0].frame.minY - 1
        }
        guard above >= 0 else { return .beside(y: y, depth: 0, parent: 0) }

        // A row's subdecks follow it, so the line can't leave the level of
        // the row under it; under the last row it goes up to the top level,
        // and well under the list it's there whatever the pointer's level.
        let lowest = below.map { rows[$0].depth } ?? 0
        let highest = max(lowest, rows[above].depth)
        let underList = below == nil && point.y > rows[last].frame.maxY + Theme.Layout.rowHeight / 2
        let pointed = Int(((point.x - lineX(depth: 0)) / Theme.Layout.dropLevelStep).rounded(.down))
        var depth = underList ? lowest : min(max(pointed, lowest), highest)
        while depth >= lowest {
            let parent = depth == 0 ? 0 : rows[above].path[depth - 1]
            if canHold(parent) { return .beside(y: y, depth: depth, parent: parent) }
            depth -= 1
        }
        return nil
    }

    /// Where a row's ring starts at `depth`: after the row's padding and the
    /// disclosure's slot.
    static func lineX(depth: Int) -> CGFloat {
        Theme.Spacing.small * 2 + Theme.Layout.disclosureWidth + CGFloat(depth) * Theme.Layout.indent
    }
}

/// Takes the drag from the rows' `onDrag`, which says which deck it is.
struct DeckDropDelegate: DropDelegate {
    let state: DeckDropState
    let rows: () -> [DeckDropRow]
    /// Opens or folds a deck: one the drag has rested on, or one it left.
    let setOpen: (Int64, Bool) -> Void
    /// Moves the deck under the parent, 0 for the top level.
    let move: (Int64, Int64) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        state.dragged != nil && info.hasItemsConforming(to: [.text])
    }

    func dropEntered(info: DropInfo) {
        update(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: state.target == nil ? .forbidden : .move)
    }

    func dropExited(info: DropInfo) {
        show(nil)
        foldSprung(keeping: [])
    }

    /// The deck comes from the drag's data, checked against `dragged`, which
    /// stays set after the drop: SwiftUI may start a second drag of the same
    /// row with the provider it already has, without asking `onDrag` again.
    /// Decks the drag opened on its way fold again, except those the deck went into.
    func performDrop(info: DropInfo) -> Bool {
        guard let dragged = state.dragged, let target = state.target,
              let provider = info.itemProviders(for: [.text]).first
        else { return false }
        show(nil)
        foldSprung(keeping: rows().first { $0.id == target.parent }?.path ?? [])
        // The text comes back on the provider's queue; it's read on the main actor.
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            let text = object as? String
            Task { @MainActor in
                if DeckDrag.deckID(text) == dragged { move(dragged, target.parent) }
            }
        }
        return true
    }

    private func foldSprung(keeping path: [Int64]) {
        for id in state.sprung where !path.contains(id) { setOpen(id, false) }
        state.sprung = []
    }

    private func update(_ info: DropInfo) {
        guard let dragged = state.dragged else { return show(nil) }
        show(DeckDropTarget.at(info.location, rows: rows(), dragged: dragged))
    }

    /// A folded deck the drag rests inside opens after a moment, as a folder does in Finder.
    private func show(_ target: DeckDropTarget?) {
        guard target != state.target else { return }
        withAnimation(.easeOut(duration: 0.12)) { state.target = target }
        state.spring?.cancel()
        state.spring = nil
        guard case .into(let id) = target, rows().first(where: { $0.id == id })?.folded == true else { return }
        let (state, setOpen) = (state, setOpen)
        state.spring = Task {
            try? await Task.sleep(for: Theme.Layout.dropSpringDelay)
            guard !Task.isCancelled else { return }
            setOpen(id, true)
            state.sprung.append(id)
        }
    }
}

/// The line a deck would drop beside: a ring where the deck's ring would sit,
/// then a rule to the row's end, in the accent.
struct DeckDropLine: View {
    let depth: Int

    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .strokeBorder(Theme.Palette.accent, lineWidth: Theme.Layout.dropLineWidth)
                .frame(width: Theme.Layout.dropLineDot, height: Theme.Layout.dropLineDot)
            Rectangle()
                .fill(Theme.Palette.accent)
                .frame(height: Theme.Layout.dropLineWidth)
        }
        .padding(.leading, DeckDropTarget.lineX(depth: depth))
        .padding(.trailing, Theme.Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(false)
    }
}

extension DeckNode {
    /// The deck's parent in the tree, 0 for a top-level deck.
    static func parentID(of deckID: Int64, in decks: [DeckNode], under parent: Int64 = 0) -> Int64? {
        for deck in decks {
            if deck.id == deckID { return parent }
            if let found = parentID(of: deckID, in: deck.children ?? [], under: deck.id) { return found }
        }
        return nil
    }
}
