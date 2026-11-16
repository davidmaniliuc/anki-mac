import AppKit
import FieldEditor
import Observation
import SwiftUI

/// The text and highlight colours the format bar applies. Desktop keeps the
/// last ones per profile, so they live in the app's defaults, not the
/// collection.
@Observable
final class EditorColors {
    static let shared = EditorColors()

    var text: Color { didSet { save(text, "lastTextColor") } }
    var highlight: Color { didSet { save(highlight, "lastHighlightColor") } }

    private init() {
        // Desktop's default for both is #0000ff.
        text = Self.load("lastTextColor") ?? Color(.sRGB, red: 0, green: 0, blue: 1)
        highlight = Self.load("lastHighlightColor") ?? Color(.sRGB, red: 0, green: 0, blue: 1)
    }

    func color(_ kind: ColorKind) -> Color {
        kind == .text ? text : highlight
    }

    private static func load(_ key: String) -> Color? {
        guard let hex = UserDefaults.standard.string(forKey: key), hex.count == 7, hex.hasPrefix("#"),
            let value = Int(hex.dropFirst(), radix: 16)
        else { return nil }
        return Color(
            .sRGB, red: Double(value >> 16) / 255, green: Double(value >> 8 & 0xff) / 255, blue: Double(value & 0xff) / 255)
    }

    private func save(_ color: Color, _ key: String) {
        let (red, green, blue) = Self.components(color)
        UserDefaults.standard.set(String(format: "#%02x%02x%02x", red, green, blue), forKey: key)
    }

    /// 0–255 sRGB components, as desktop writes them into `rgb(…)`.
    static func components(_ color: Color) -> (Int, Int, Int) {
        let rgb = NSColor(color).usingColorSpace(.sRGB) ?? .black
        func byte(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return (byte(rgb.redComponent), byte(rgb.greenComponent), byte(rgb.blueComponent))
    }
}

/// Carries a colour kind through `NSApp.sendAction`.
final class ColorCommand: NSObject {
    let kind: ColorKind
    init(_ kind: ColorKind) { self.kind = kind }
}

/// The target of the system colour panel while it picks a colour for the
/// editor: the format bar's text or highlight colour, or the mask editor's
/// fill. A pick becomes that colour and is applied.
final class EditorColorPanel: NSObject {
    static let shared = EditorColorPanel()
    private var picked: (NSColor) -> Void = { _ in }

    func show(_ kind: ColorKind, apply: @escaping () -> Void) {
        show(NSColor(EditorColors.shared.color(kind))) { color in
            if kind == .text { EditorColors.shared.text = Color(nsColor: color) } else {
                EditorColors.shared.highlight = Color(nsColor: color)
            }
            apply()
        }
    }

    func show(_ color: NSColor, picked: @escaping (NSColor) -> Void) {
        self.picked = picked
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isContinuous = false
        panel.color = color
        panel.setTarget(self)
        panel.setAction(#selector(picked(_:)))
        panel.orderFront(nil)
    }

    @objc private func picked(_ panel: NSColorPanel) {
        picked(panel.color)
    }
}
