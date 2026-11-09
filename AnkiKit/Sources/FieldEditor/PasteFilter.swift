import Foundation

/// Desktop's filter for HTML pasted from elsewhere (ts/lib/html-filter):
/// unknown tags are unwrapped, scripts and styles removed, `<p>` becomes
/// `<div>`, and only a few attributes survive. The extended filter, used
/// unless the collection strips formatting on paste, also keeps simple
/// formatting.
public enum PasteFilter {
    private enum Rule {
        case attributes(Set<String>)
        case span
        case toDiv
        case remove
    }

    private static let basic: [String: Rule] = [
        "br": .attributes([]), "img": .attributes(["src", "alt"]), "div": .attributes([]), "p": .toDiv,
        "sub": .attributes([]), "sup": .attributes([]), "title": .remove, "script": .remove, "iframe": .remove,
        "object": .remove, "style": .remove,
    ]

    private static let extended: [String: Rule] = basic.merging([
        "a": .attributes(["href"]), "b": .attributes([]), "blockquote": .attributes([]), "code": .attributes([]),
        "dd": .attributes([]), "dl": .attributes([]), "dt": .attributes([]), "em": .attributes([]),
        "font": .attributes(["color"]), "h1": .attributes([]), "h2": .attributes([]), "h3": .attributes([]),
        "i": .attributes([]), "li": .attributes([]), "ol": .attributes([]), "pre": .attributes([]),
        "rp": .attributes([]), "rt": .attributes([]), "ruby": .attributes([]), "span": .span,
        "strong": .attributes([]), "table": .attributes([]), "td": .attributes(["colspan", "rowspan"]),
        "th": .attributes(["colspan", "rowspan"]), "tr": .attributes(["rowspan"]), "u": .attributes([]),
        "ul": .attributes([]),
    ]) { _, new in new }

    /// Styles a pasted span may keep: desktop's light-mode list.
    private static let spanStyles: Set<String> = [
        "color", "background-color", "font-weight", "font-style", "text-decoration-line",
    ]

    /// `imageSource` maps each image's `src`, as desktop saves remote and
    /// inline images into the media folder.
    public static func filter(
        _ html: String, keepFormatting: Bool, imageSource: (String) -> String = { $0 }
    ) -> String {
        let rules = keepFormatting ? extended : basic
        var out = ""
        /// For each open element: the tag that closes it, or nil when it was unwrapped.
        var open: [(name: String, close: String?)] = []
        var removing: (name: String, depth: Int)?

        for token in tokenizeHTML(html) {
            if var skip = removing {
                switch token {
                case .open(let name, _, let selfClosing) where name == skip.name && !selfClosing: skip.depth += 1
                case .close(let name, _) where name == skip.name: skip.depth -= 1
                default: break
                }
                removing = skip.depth == 0 ? nil : skip
                continue
            }
            switch token {
            case .text(let text):
                out += text
            case .comment:
                break
            case .open(let name, let raw, let selfClosing):
                let isVoid = FieldDocument.voidTags.contains(name) || selfClosing
                switch rules[name] {
                case .remove?:
                    if !isVoid { removing = (name, 1) }
                case .toDiv?:
                    out += "<div>"
                    open.append((name, "</div>"))
                case .attributes(let allowed)?:
                    var attributes = parseAttributes(raw).filter { allowed.contains($0.name) }
                    if name == "img", let index = attributes.firstIndex(where: { $0.name == "src" }) {
                        attributes[index].value = imageSource(attributes[index].value)
                    }
                    out += tag(name, attributes)
                    if !isVoid { open.append((name, "</\(name)>")) }
                case .span?:
                    let style = parseCSS(parseAttributes(raw).first { $0.name == "style" }?.value ?? "")
                        .filter { spanStyles.contains($0.property) && !($0.property == "background-color" && $0.value == "transparent") }
                    let attributes = style.isEmpty ? [] : [(name: "style", value: style.map { "\($0.property): \($0.value);" }.joined(separator: " "))]
                    out += tag(name, attributes)
                    open.append((name, "</\(name)>"))
                case nil:
                    if !isVoid { open.append((name, nil)) }
                }
            case .close(let name, _):
                guard let index = open.lastIndex(where: { $0.name == name }) else { continue }
                for element in open[index...].reversed() {
                    if let close = element.close { out += close }
                }
                open.removeSubrange(index...)
            }
        }
        for element in open.reversed() {
            if let close = element.close { out += close }
        }
        return out
    }

    private static func tag(_ name: String, _ attributes: [(name: String, value: String)]) -> String {
        "<\(name)" + attributes.map { " \($0.name)=\"\($0.value.replacingOccurrences(of: "\"", with: "&quot;"))\"" }.joined() + ">"
    }
}
