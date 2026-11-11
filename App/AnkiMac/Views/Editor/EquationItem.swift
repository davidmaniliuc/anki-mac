import SwiftUI

/// What desktop's Equations menu inserts: MathJax, or the older LaTeX tags.
enum EquationItem: CaseIterable {
    case mathInline, mathBlock, mathChemistry, latex, latexEquation, latexMathEnv

    var title: String {
        switch self {
        case .mathInline: Tr.editingMathjaxInline
        case .mathBlock: Tr.editingMathjaxBlock
        case .mathChemistry: Tr.editingMathjaxChemistry
        case .latex: Tr.editingLatex
        case .latexEquation: Tr.editingLatexEquation
        case .latexMathEnv: Tr.editingLatexMathEnv
        }
    }

    var action: Selector {
        switch self {
        case .mathInline: #selector(FieldTextView.insertMathInline(_:))
        case .mathBlock: #selector(FieldTextView.insertMathBlock(_:))
        case .mathChemistry: #selector(FieldTextView.insertMathChemistry(_:))
        case .latex: #selector(FieldTextView.insertLatex(_:))
        case .latexEquation: #selector(FieldTextView.insertLatexEquation(_:))
        case .latexMathEnv: #selector(FieldTextView.insertLatexMathEnv(_:))
        }
    }

    /// Desktop's two-key shortcut: Control with the first key, then the second.
    var chord: (prefix: Character, key: Character) {
        switch self {
        case .mathInline: ("m", "m")
        case .mathBlock: ("m", "e")
        case .mathChemistry: ("m", "c")
        case .latex: ("t", "t")
        case .latexEquation: ("t", "e")
        case .latexMathEnv: ("t", "m")
        }
    }

    static let chordPrefixes: Set<Character> = Set(allCases.map(\.chord.prefix))
}

/// The items of the Equations menu, in the format bar and the Format menu.
struct EquationButtons: View {
    let send: (Selector) -> Void

    var body: some View {
        ForEach(EquationItem.allCases, id: \.self) { item in
            if item == .latex { Divider() }
            Button(item.title) { send(item.action) }
        }
    }
}
