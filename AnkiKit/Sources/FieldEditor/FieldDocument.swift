import AppKit

extension NSAttributedString.Key {
    /// The ids of the elements enclosing a character, outermost first.
    public static let fieldStack = NSAttributedString.Key("AnkiFieldStack")
    /// The text token a character came from, for replaying its source bytes.
    public static let fieldSource = NSAttributedString.Key("AnkiFieldSource")
    /// The raw HTML of something shown as one character: a `<br>`, an image,
    /// a comment, a table opened as a chip.
    public static let fieldAtom = NSAttributedString.Key("AnkiFieldAtom")
    /// Characters the editor added for display (block breaks, list bullets),
    /// which export leaves out.
    public static let fieldSynthetic = NSAttributedString.Key("AnkiFieldSynthetic")
    /// A MathJax atom's TeX, as a `FieldMath`.
    public static let fieldMath = NSAttributedString.Key("AnkiFieldMath")
}

/// MathJax in a field: `\(…\)` inline or `\[…\]` as a block, shown
/// rendered and kept as written.
public struct FieldMath: Hashable, Sendable {
    public let tex: String
    public let display: Bool

    public init(tex: String, display: Bool) {
        self.tex = tex
        self.display = display
    }

    /// The field HTML for this TeX, escaping only what would confuse HTML,
    /// as desktop's `escapeSomeEntities`.
    public var html: String {
        let escaped = tex.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return display ? "\\[\(escaped)\\]" : "\\(\(escaped)\\)"
    }
}

/// How a field looks in the editor. The app fills it from its theme.
public struct FieldStyle {
    public var font: NSFont
    public var codeFont: NSFont
    public var textColor: NSColor
    /// Behind text in tags the editor doesn't know, so they stand out.
    public var unknownTagBackground: NSColor
    public var chipFont: NSFont
    public var chipFill: NSColor
    public var chipText: NSColor
    public var imageMaxHeight: CGFloat
    /// Rendered MathJax and how far below the baseline it reaches, or nil
    /// while it isn't ready; MathJax shows as its TeX until then.
    public var mathImage: ((FieldMath) -> (image: NSImage, descent: CGFloat)?)?

    public init(
        font: NSFont, codeFont: NSFont, textColor: NSColor, unknownTagBackground: NSColor, chipFont: NSFont,
        chipFill: NSColor, chipText: NSColor, imageMaxHeight: CGFloat,
        mathImage: ((FieldMath) -> (image: NSImage, descent: CGFloat)?)? = nil
    ) {
        self.mathImage = mathImage
        self.font = font
        self.codeFont = codeFont
        self.textColor = textColor
        self.unknownTagBackground = unknownTagBackground
        self.chipFont = chipFont
        self.chipFill = chipFill
        self.chipText = chipText
        self.imageMaxHeight = imageMaxHeight
    }
}

/// Formatting the toolbar toggles.
/// The two colours desktop's toolbar sets.
public enum ColorKind: Sendable {
    case text, highlight

    var property: String { self == .text ? "color" : "background-color" }
}

public enum InlineFormat: CaseIterable, Sendable {
    case bold, italic, underline, strikethrough, superscript, `subscript`

    /// The tag added to apply it.
    var tag: String {
        switch self {
        case .bold: "b"
        case .italic: "i"
        case .underline: "u"
        case .strikethrough: "s"
        case .superscript: "sup"
        case .subscript: "sub"
        }
    }

    /// Tags that apply it, which removing it takes away.
    var tags: Set<String> {
        switch self {
        case .bold: ["b", "strong"]
        case .italic: ["i", "em"]
        case .underline: ["u", "ins"]
        case .strikethrough: ["s", "strike", "del"]
        case .superscript: ["sup"]
        case .subscript: ["sub"]
        }
    }

    /// CSS declarations that apply it.
    func isApplied(by property: String, _ value: String) -> Bool {
        let value = value.lowercased()
        switch self {
        case .bold: return property == "font-weight" && (value == "bold" || value == "bolder" || (Int(value) ?? 0) >= 600)
        case .italic: return property == "font-style" && (value == "italic" || value == "oblique")
        case .underline: return property.hasPrefix("text-decoration") && value.contains("underline")
        case .strikethrough: return property.hasPrefix("text-decoration") && value.contains("line-through")
        case .superscript: return property == "vertical-align" && value == "super"
        case .subscript: return property == "vertical-align" && value == "sub"
        }
    }
}

/// One field's HTML in an editable form that gives the HTML back unchanged
/// where it wasn't edited.
///
/// Every element of the field gets an id, and every character carries the
/// ids of the elements around it. Text keeps a link to the token it came
/// from, and things the text view can't hold as text (line breaks, images,
/// comments, tables) become single characters that carry their raw HTML.
/// Export replays the original tags and the original bytes of unedited
/// text, and escapes only what was typed.
public final class FieldDocument {
    public let html: String
    public private(set) var text: NSAttributedString = NSAttributedString()

    private struct Element {
        let name: String
        let open: String
        var close: String
    }

    private var elements: [Element] = []
    private var texts: [Int: DecodedText] = [:]
    private var nextSource = 0
    private let style: FieldStyle
    private let mediaFolder: URL?
    private var displayCache: [[Int]: [NSAttributedString.Key: Any]] = [:]
    private var formatCache: [[Int]: Set<InlineFormat>] = [:]
    /// An element with one formatting property removed from its style.
    private var withoutFormat: [Int: [InlineFormat: Int?]] = [:]
    private var withoutColor: [Int: [ColorKind: Int?]] = [:]
    private var pendingMerge: (range: NSRange, from: Int, to: Int?)?

    static let voidTags: Set<String> = [
        "br", "img", "hr", "wbr", "input", "meta", "link", "source", "area", "col", "embed", "param", "track", "base",
    ]
    /// Shown as one chip, edited as HTML.
    static let opaqueTags: Set<String> = [
        "table", "svg", "math", "script", "style", "object", "iframe", "video", "audio", "select", "textarea",
        "canvas", "template",
    ]
    static let blockTags: Set<String> = [
        "div", "p", "li", "ul", "ol", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "pre", "tr",
    ]
    static let inlineTags: Set<String> = [
        "b", "i", "u", "s", "strong", "em", "sup", "sub", "span", "font", "a", "strike", "del", "ins", "code",
        "small", "big", "mark", "td", "th", "tbody", "thead", "html", "body", "head", "center", "label", "kbd",
        "abbr", "ruby", "rt", "rp",
    ]
    /// What "Remove Formatting" takes away.
    static let formattingTags: Set<String> = [
        "b", "i", "u", "s", "strong", "em", "sup", "sub", "span", "font", "strike", "del", "ins", "small", "big",
        "mark",
    ]
    private static let syntheticUnits: Set<UInt16> = [10, 0x200B, 0x2022, 0x2002]

    public init(html: String, style: FieldStyle, mediaFolder: URL? = nil) {
        self.html = html
        self.style = style
        self.mediaFolder = mediaFolder
        text = build(tokenizeHTML(html), base: [], trackSources: true)
    }

    // MARK: Import

    /// Pasted HTML, as text to insert at a position whose elements are
    /// `base`. It exports as written, but escaped, since it's new.
    public func fragment(html: String, base: [Int]) -> NSAttributedString {
        build(tokenizeHTML(html), base: base, trackSources: false)
    }

    private func build(_ tokens: [HTMLToken], base: [Int], trackSources: Bool) -> NSAttributedString {
        let out = NSMutableAttributedString()
        var stack = base
        var openedAt: [Int] = []

        func appendSynthetic(_ string: String, _ stack: [Int]) {
            var attributes = self.attributes(stack)
            attributes[.fieldSynthetic] = true
            out.append(NSAttributedString(string: string, attributes: attributes))
        }
        func appendAtom(
            _ raw: String, lineBreak: Bool = false, label: String, image: NSImage? = nil, math: FieldMath? = nil
        ) {
            var attributes = self.attributes(stack)
            attributes[.fieldAtom] = raw
            if lineBreak {
                out.append(NSAttributedString(string: "\n", attributes: attributes))
                return
            }
            let attachment = NSTextAttachment()
            if let math {
                attributes[.fieldMath] = math
                showMath(math, in: attachment)
            } else if let image {
                attachment.image = image
                let height = min(style.imageMaxHeight, image.size.height)
                attachment.bounds = NSRect(
                    x: 0, y: -4, width: image.size.width * height / max(1, image.size.height), height: height)
            } else {
                let chip = chipImage(label)
                attachment.image = chip
                attachment.bounds = NSRect(x: 0, y: -3, width: chip.size.width, height: chip.size.height)
            }
            attributes[.attachment] = attachment
            out.append(NSAttributedString(string: "\u{FFFC}", attributes: attributes))
        }
        /// An empty element still needs a character to hang its tags on.
        func keepNonEmpty(_ level: Int) {
            if out.length == openedAt[level] { appendSynthetic("\u{200B}", Array(stack[0...(base.count + level)])) }
        }

        var index = 0
        while index < tokens.count {
            switch tokens[index] {
            case .text(let whole):
                for (raw, math) in Self.splitMath(whole) {
                    if let math {
                        appendAtom(raw, label: math.tex, math: math)
                        continue
                    }
                    let decoded = decodeHTMLText(raw)
                    var attributes = self.attributes(stack)
                    if trackSources {
                        texts[nextSource] = decoded
                        attributes[.fieldSource] = nextSource
                        nextSource += 1
                    }
                    out.append(NSAttributedString(
                        string: String(utf16CodeUnits: decoded.units, count: decoded.units.count), attributes: attributes))
                }
            case .comment(let raw):
                appendAtom(raw, label: "<!--…-->")
            case .open(let name, let raw, let selfClosing):
                if name == "br" {
                    appendAtom(raw, lineBreak: true, label: "")
                } else if name == "img" {
                    let source = parseAttributes(raw).first { $0.name == "src" }?.value ?? ""
                    let path = decodeHTMLText(source)
                    let file = String(utf16CodeUnits: path.units, count: path.units.count)
                    let image = mediaFolder.flatMap { NSImage(contentsOf: $0.appending(path: file)) }
                    appendAtom(raw, label: "img \(file)", image: image)
                } else if Self.voidTags.contains(name) || selfClosing {
                    appendAtom(raw, label: "<\(name)/>")
                } else if Self.opaqueTags.contains(name) {
                    // The whole element, up to its matching close, as one chip.
                    var raws = raw
                    var depth = 1
                    var end = index + 1
                    while end < tokens.count, depth > 0 {
                        switch tokens[end] {
                        case .text(let text), .comment(let text): raws += text
                        case .open(let inner, let innerRaw, let innerSelfClosing):
                            raws += innerRaw
                            if inner == name && !innerSelfClosing { depth += 1 }
                        case .close(let inner, let innerRaw):
                            raws += innerRaw
                            if inner == name { depth -= 1 }
                        }
                        end += 1
                    }
                    appendAtom(raws, label: "\(name) · edit as HTML")
                    index = end
                    continue
                } else {
                    elements.append(Element(name: name, open: raw, close: ""))
                    let id = elements.count - 1
                    if Self.blockTags.contains(name), out.length > 0,
                        out.mutableString.character(at: out.length - 1) != 10
                    {
                        appendSynthetic("\n", stack + [id])
                    }
                    stack.append(id)
                    openedAt.append(out.length)
                    if name == "li" { appendSynthetic("\u{2022}\u{2002}", stack) }
                }
            case .close(let name, let raw):
                if let level = stack.indices.dropFirst(base.count).last(where: { elements[stack[$0]].name == name }) {
                    // Closing an outer element closes the ones left open inside it.
                    for depth in stride(from: stack.count - 1, through: level, by: -1) {
                        keepNonEmpty(depth - base.count)
                        if depth == level { elements[stack[depth]].close = raw }
                        stack.removeLast()
                        openedAt.removeLast()
                    }
                } else {
                    appendAtom(raw, label: "</\(name)>")
                }
            }
            index += 1
        }
        for depth in stride(from: stack.count - 1, through: base.count, by: -1) {
            keepNonEmpty(depth - base.count)
            stack.removeLast()
            openedAt.removeLast()
        }
        return out
    }

    // MARK: MathJax

    /// Raw text cut into plain runs and MathJax, each MathJax run with its
    /// TeX. Delimiters split across tags stay text.
    static func splitMath(_ raw: String) -> [(raw: String, math: FieldMath?)] {
        guard raw.contains("\\(") || raw.contains("\\[") else { return [(raw, nil)] }
        var parts: [(String, FieldMath?)] = []
        var rest = raw[...]
        while let open = [rest.firstRange(of: "\\("), rest.firstRange(of: "\\[")].compactMap({ $0 })
            .min(by: { $0.lowerBound < $1.lowerBound })
        {
            let display = rest[open] == "\\["
            guard let close = rest[open.upperBound...].firstRange(of: display ? "\\]" : "\\)") else { break }
            if open.lowerBound > rest.startIndex { parts.append((String(rest[..<open.lowerBound]), nil)) }
            let inner = decodeHTMLText(String(rest[open.upperBound..<close.lowerBound]))
            parts.append((
                String(rest[open.lowerBound..<close.upperBound]),
                FieldMath(tex: String(utf16CodeUnits: inner.units, count: inner.units.count), display: display)))
            rest = rest[close.upperBound...]
        }
        if !rest.isEmpty { parts.append((String(rest), nil)) }
        return parts
    }

    private func showMath(_ math: FieldMath, in attachment: NSTextAttachment) {
        if let (image, descent) = style.mathImage?(math) {
            attachment.image = image
            attachment.bounds = NSRect(x: 0, y: -descent, width: image.size.width, height: image.size.height)
        } else {
            let chip = chipImage(math.tex.isEmpty ? "MathJax" : math.tex)
            attachment.image = chip
            attachment.bounds = NSRect(x: 0, y: -3, width: chip.size.width, height: chip.size.height)
        }
    }

    /// Swaps in rendered MathJax that has become ready since the text was built.
    public func refreshMath(in storage: NSTextStorage) {
        var changed: [(NSRange, FieldMath)] = []
        storage.enumerateAttribute(.fieldMath, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if let math = value as? FieldMath { changed.append((range, math)) }
        }
        guard !changed.isEmpty else { return }
        storage.beginEditing()
        for (range, math) in changed {
            let attachment = NSTextAttachment()
            showMath(math, in: attachment)
            storage.addAttribute(.attachment, value: attachment, range: range)
        }
        storage.endEditing()
    }

    // MARK: Export

    /// The field's HTML for the text as edited.
    public func html(from text: NSAttributedString) -> String {
        let string = text.string as NSString
        let length = text.length
        let whole = NSRange(location: 0, length: length)

        // Each source token's current text, gathered across its runs.
        var current: [Int: [UInt16]] = [:]
        text.enumerateAttribute(.fieldSource, in: whole) { value, range, _ in
            guard let source = value as? Int else { return }
            var buffer = [UInt16](repeating: 0, count: range.length)
            string.getCharacters(&buffer, range: range)
            current[source, default: []] += buffer
        }
        // How much of each token's start and end is unchanged: those
        // characters replay their source bytes, entities and all.
        var kept: [Int: (prefix: Int, suffix: Int)] = [:]
        for (source, now) in current {
            let original = texts[source]!.units
            if now == original {
                kept[source] = (now.count, 0)
                continue
            }
            var prefix = 0
            while prefix < now.count, prefix < original.count, now[prefix] == original[prefix] { prefix += 1 }
            var suffix = 0
            while suffix < now.count - prefix, suffix < original.count - prefix,
                now[now.count - 1 - suffix] == original[original.count - 1 - suffix]
            {
                suffix += 1
            }
            kept[source] = (prefix, suffix)
        }

        var cursor: [Int: Int] = [:]
        var out = ""
        out.reserveCapacity(length * 2)
        var open: [Int] = []
        func moveTo(_ stack: [Int]) {
            var shared = 0
            while shared < open.count, shared < stack.count, open[shared] == stack[shared] { shared += 1 }
            for id in open[shared...].reversed() { out += closeTag(id) }
            for id in stack[shared...] { out += elements[id].open }
            open = stack
        }
        func appendEscaped(_ units: [UInt16]) {
            if !units.isEmpty { out += escapeHTML(String(utf16CodeUnits: units, count: units.count)) }
        }

        var index = 0
        while index < length {
            var range = NSRange()
            let attributes = text.attributes(at: index, effectiveRange: &range)
            moveTo((attributes[.fieldStack] as? [Int]) ?? [])
            var buffer = [UInt16](repeating: 0, count: range.length)
            string.getCharacters(&buffer, range: range)
            if attributes[.fieldSynthetic] != nil {
                // Only what was typed into a placeholder survives.
                appendEscaped(buffer.filter { !Self.syntheticUnits.contains($0) })
            } else if let raw = attributes[.fieldAtom] as? String {
                var typed: [UInt16] = []
                for unit in buffer {
                    if unit == 10 || unit == 0xFFFC {
                        appendEscaped(typed)
                        typed = []
                        out += raw
                    } else {
                        typed.append(unit)
                    }
                }
                appendEscaped(typed)
            } else if let source = attributes[.fieldSource] as? Int, let original = texts[source] {
                let now = current[source]!
                let (prefix, suffix) = kept[source]!
                var position = cursor[source] ?? 0
                var typed: [UInt16] = []
                for _ in 0..<range.length {
                    let replayed: String? =
                        position < prefix ? original.sources[position]
                        : position >= now.count - suffix ? original.sources[original.units.count - (now.count - position)]
                        : nil
                    if let replayed {
                        appendEscaped(typed)
                        typed = []
                        out += replayed
                    } else {
                        typed.append(now[position])
                    }
                    position += 1
                }
                appendEscaped(typed)
                cursor[source] = position
            } else {
                appendEscaped(buffer)
            }
            index = NSMaxRange(range)
        }
        moveTo([])
        return out
    }

    /// An element's closing tag as written; empty for one the field never
    /// closed, so the field comes back as it was.
    private func closeTag(_ id: Int) -> String {
        elements[id].close
    }

    // MARK: Display

    /// What a character inside these elements looks like, plus the stack.
    public func attributes(_ stack: [Int]) -> [NSAttributedString.Key: Any] {
        if let cached = displayCache[stack] { return cached }
        var traits: NSFontDescriptor.SymbolicTraits = []
        var size = style.font.pointSize
        var attributes: [NSAttributedString.Key: Any] = [:]
        var code = false
        for id in stack {
            let element = elements[id]
            let tagAttributes = Dictionary(parseAttributes(element.open), uniquingKeysWith: { first, _ in first })
            let css = Dictionary(
                parseCSS(tagAttributes["style"] ?? "").map { ($0.property, $0.value.lowercased()) },
                uniquingKeysWith: { first, _ in first })
            switch element.name {
            case "b", "strong", "h1", "h2", "h3", "th": traits.insert(.bold)
            case "i", "em": traits.insert(.italic)
            case "u", "ins": attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            case "s", "strike", "del": attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            case "sup":
                attributes[.baselineOffset] = size * 0.35
                size *= 0.75
            case "sub":
                attributes[.baselineOffset] = -size * 0.2
                size *= 0.75
            case "a": if let href = tagAttributes["href"] { attributes[.link] = href }
            case "code", "pre", "kbd": code = true
            default:
                if !Self.inlineTags.contains(element.name), !Self.blockTags.contains(element.name) {
                    attributes[.backgroundColor] = style.unknownTagBackground
                }
            }
            if let color = (tagAttributes["color"] ?? css["color"]).flatMap(parseColor) {
                attributes[.foregroundColor] = color
            }
            if let color = css["background-color"].flatMap(parseColor) { attributes[.backgroundColor] = color }
            for format in [InlineFormat.bold, .italic] where css.contains(where: { format.isApplied(by: $0.key, $0.value) }) {
                traits.insert(format == .bold ? .bold : .italic)
            }
            if css.contains(where: { InlineFormat.underline.isApplied(by: $0.key, $0.value) }) {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            if css.contains(where: { InlineFormat.strikethrough.isApplied(by: $0.key, $0.value) }) {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if let pixels = css["font-size"].flatMap({ Double($0.replacingOccurrences(of: "px", with: "")) }) {
                size = CGFloat(pixels) * 0.75
            }
        }
        let base = code ? style.codeFont : style.font
        let descriptor = base.fontDescriptor.withSymbolicTraits(traits)
        attributes[.font] = NSFont(descriptor: descriptor, size: size) ?? base
        if attributes[.foregroundColor] == nil { attributes[.foregroundColor] = style.textColor }
        attributes[.fieldStack] = stack
        displayCache[stack] = attributes
        return attributes
    }

    private func chipImage(_ label: String) -> NSImage {
        let font = style.chipFont
        let fill = style.chipFill
        let color = style.chipText
        let width = (label as NSString).size(withAttributes: [.font: font]).width + 10
        let height = ceil(font.ascender - font.descender) + 4
        return NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            fill.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4).fill()
            (label as NSString).draw(at: NSPoint(x: 5, y: 2 - font.descender), withAttributes: [.font: font, .foregroundColor: color])
            return true
        }
    }

    // MARK: Formatting

    /// The formatting in force at a stack, from tags or their styles.
    public func formats(_ stack: [Int]) -> Set<InlineFormat> {
        if let cached = formatCache[stack] { return cached }
        var found: Set<InlineFormat> = []
        for id in stack {
            let element = elements[id]
            for format in InlineFormat.allCases {
                if format.tags.contains(element.name) || styleDeclarations(id).contains(where: {
                    format.isApplied(by: $0.property, $0.value)
                }) {
                    found.insert(format)
                }
            }
        }
        formatCache[stack] = found
        return found
    }

    /// Whether every character in the range has the format.
    public func isApplied(_ format: InlineFormat, in text: NSAttributedString, range: NSRange) -> Bool {
        guard range.length > 0 else { return false }
        var applied = true
        text.enumerateAttribute(.fieldStack, in: range) { value, _, stop in
            if !formats((value as? [Int]) ?? []).contains(format) {
                applied = false
                stop.pointee = true
            }
        }
        return applied
    }

    /// Adds the format to the range, or takes it away if the whole range has
    /// it. Taking it from part of an original tag splits the tag; taking it
    /// from a styled tag rewrites only that part's style.
    public func toggle(_ format: InlineFormat, in storage: NSTextStorage, range: NSRange) {
        guard range.length > 0 else { return }
        let remove = isApplied(format, in: storage, range: range)
        storage.beginEditing()
        if remove {
            restack(storage, range) { self.stack($0, removing: format) }
        } else {
            let opposite: InlineFormat? = format == .superscript ? .subscript : format == .subscript ? .superscript : nil
            let id = addElement(format.tag)
            restack(storage, range) { stack in
                var stack = opposite.map { self.stack(stack, removing: $0) } ?? stack
                stack.append(id)
                return stack
            }
        }
        storage.endEditing()
    }

    /// The typing attributes after toggling a format with nothing selected.
    public func typingAttributes(
        _ attributes: [NSAttributedString.Key: Any], toggling format: InlineFormat
    ) -> [NSAttributedString.Key: Any] {
        let current = (attributes[.fieldStack] as? [Int]) ?? []
        let stack = formats(current).contains(format) ? self.stack(current, removing: format) : current + [addElement(format.tag)]
        var result = self.attributes(stack)
        result[.fieldSource] = attributes[.fieldSource]
        return result
    }

    /// Desktop's Remove Formatting: inline formatting tags go, links and
    /// blocks stay.
    public func removeFormatting(in storage: NSTextStorage, range: NSRange) {
        guard range.length > 0 else { return }
        storage.beginEditing()
        restack(storage, range) { $0.filter { !Self.formattingTags.contains(self.elements[$0].name) } }
        storage.endEditing()
    }

    /// Desktop's text and highlight colour buttons: the range gets
    /// `<span style="color: rgb(…);">`, and any colour it had before goes,
    /// so picking again replaces the colour instead of nesting spans.
    public func setColor(_ kind: ColorKind, red: Int, green: Int, blue: Int, in storage: NSTextStorage, range: NSRange) {
        guard range.length > 0 else { return }
        elements.append(Element(
            name: "span", open: "<span style=\"\(kind.property): rgb(\(red), \(green), \(blue));\">", close: "</span>"))
        let id = elements.count - 1
        storage.beginEditing()
        restack(storage, range) { stack in
            stack.compactMap { self.element($0, without: kind) } + [id]
        }
        storage.endEditing()
    }

    /// A copy of an element without its colour, nil when nothing would be
    /// left of it; the element itself when it has no colour.
    private func element(_ id: Int, without kind: ColorKind) -> Int? {
        if let cached = withoutColor[id]?[kind] { return cached }
        let element = elements[id]
        let attributes = parseAttributes(element.open)
        let declarations = styleDeclarations(id)
        let fontColor = kind == .text && element.name == "font" && attributes.contains { $0.name == "color" }
        guard fontColor || declarations.contains(where: { $0.property == kind.property }) else { return id }
        let kept = declarations.filter { $0.property != kind.property }
        let others = attributes.filter { $0.name != "style" && !(fontColor && $0.name == "color") }
        var result: Int?
        if !(kept.isEmpty && others.isEmpty && (element.name == "span" || element.name == "font")) {
            var open = "<\(element.name)"
            for attribute in others { open += " \(attribute.name)=\"\(attribute.value)\"" }
            if !kept.isEmpty { open += " style=\"" + kept.map { "\($0.property): \($0.value);" }.joined(separator: " ") + "\"" }
            open += ">"
            elements.append(Element(name: element.name, open: open, close: "</\(element.name)>"))
            result = elements.count - 1
        }
        withoutColor[id, default: [:]][kind] = .some(result)
        return result
    }

    private func addElement(_ tag: String) -> Int {
        elements.append(Element(name: tag, open: "<\(tag)>", close: "</\(tag)>"))
        return elements.count - 1
    }

    private func stack(_ stack: [Int], removing format: InlineFormat) -> [Int] {
        stack.compactMap { id in
            if format.tags.contains(elements[id].name) { return nil }
            guard styleDeclarations(id).contains(where: { format.isApplied(by: $0.property, $0.value) }) else { return id }
            return element(id, without: format)
        }
    }

    private func styleDeclarations(_ id: Int) -> [(property: String, value: String)] {
        parseCSS(parseAttributes(elements[id].open).first { $0.name == "style" }?.value ?? "")
    }

    /// A copy of a styled element without the declarations that apply the
    /// format; nil when nothing would be left of a plain span.
    private func element(_ id: Int, without format: InlineFormat) -> Int? {
        if let cached = withoutFormat[id]?[format] { return cached }
        let element = elements[id]
        let kept = styleDeclarations(id).filter { !format.isApplied(by: $0.property, $0.value) }
        let others = parseAttributes(element.open).filter { $0.name != "style" }
        var result: Int?
        if !(kept.isEmpty && others.isEmpty && element.name == "span") {
            var open = "<\(element.name)"
            for attribute in others { open += " \(attribute.name)=\"\(attribute.value)\"" }
            if !kept.isEmpty { open += " style=\"" + kept.map { "\($0.property): \($0.value);" }.joined(separator: " ") + "\"" }
            open += ">"
            elements.append(Element(name: element.name, open: open, close: "</\(element.name)>"))
            result = elements.count - 1
        }
        withoutFormat[id, default: [:]][format] = .some(result)
        return result
    }

    /// Gives each run in the range a new stack, keeping what marks it as
    /// source text, an atom or a placeholder.
    private func restack(_ storage: NSTextStorage, _ range: NSRange, _ change: ([Int]) -> [Int]) {
        var runs: [(NSRange, [NSAttributedString.Key: Any])] = []
        storage.enumerateAttributes(in: range) { attributes, run, _ in runs.append((run, attributes)) }
        for (run, old) in runs {
            var attributes = self.attributes(change((old[.fieldStack] as? [Int]) ?? []))
            for key in [NSAttributedString.Key.fieldSource, .fieldAtom, .fieldSynthetic, .attachment, .fieldMath] {
                if let value = old[key] { attributes[key] = value }
            }
            storage.setAttributes(attributes, range: run)
        }
    }

    // MARK: Editing rules

    /// Typing after an image or a line break must not type more of it, and
    /// typing at a placeholder must not be dropped on export.
    public static func cleanTypingAttributes(
        _ attributes: [NSAttributedString.Key: Any]
    ) -> [NSAttributedString.Key: Any] {
        var attributes = attributes
        attributes[.fieldAtom] = nil
        attributes[.fieldSynthetic] = nil
        attributes[.attachment] = nil
        attributes[.fieldMath] = nil
        return attributes
    }

    /// Call before deleting `range`. Deleting the break in front of a block
    /// (`<div>`) joins it to the block before, as in a browser; otherwise
    /// the tags would come back on the next load. `finishEdit` applies it.
    public func prepareDeletion(of range: NSRange, in text: NSAttributedString) {
        pendingMerge = nil
        guard range.length > 0, NSMaxRange(range) < text.length else { return }
        var effective = NSRange()
        guard text.attribute(.fieldSynthetic, at: NSMaxRange(range) - 1, effectiveRange: nil) != nil,
            (text.string as NSString).character(at: NSMaxRange(range) - 1) == 10
        else { return }
        let after = (text.attribute(.fieldStack, at: NSMaxRange(range), effectiveRange: &effective) as? [Int]) ?? []
        guard let block = after.last(where: { Self.blockTags.contains(elements[$0].name) }) else { return }
        let before = range.location > 0
            ? (text.attribute(.fieldStack, at: range.location - 1, effectiveRange: nil) as? [Int]) ?? [] : []
        let depth = after.firstIndex(of: block)!
        let target = depth < before.count && Self.blockTags.contains(elements[before[depth]].name) ? before[depth] : nil
        // Everything inside the block, from just after the deletion.
        var end = NSMaxRange(range)
        while end < text.length, ((text.attribute(.fieldStack, at: end, effectiveRange: nil) as? [Int]) ?? []).contains(block) {
            end += 1
        }
        pendingMerge = (NSRange(location: range.location, length: end - NSMaxRange(range)), block, target)
    }

    public func finishEdit(_ storage: NSTextStorage) {
        guard let merge = pendingMerge else { return }
        pendingMerge = nil
        guard NSMaxRange(merge.range) <= storage.length else { return }
        storage.beginEditing()
        restack(storage, merge.range) { stack in
            stack.compactMap { $0 == merge.from ? merge.to : $0 }
        }
        storage.endEditing()
    }

    // MARK: Cloze

    /// The number for a new cloze: one more than the highest in the field.
    public static func nextClozeNumber(in fields: [String]) -> Int {
        let pattern = /\{\{c(\d+)::/
        let highest = fields.flatMap { $0.matches(of: pattern).compactMap { Int($0.1) } }.max() ?? 0
        return highest + 1
    }
}

/// A CSS or HTML colour: `#rgb`, `#rrggbb`, `rgb(…)` or a common name.
func parseColor(_ value: String) -> NSColor? {
    let text = value.trimmingCharacters(in: .whitespaces).lowercased()
    if text.hasPrefix("#") {
        var hex = String(text.dropFirst())
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6, let number = UInt32(hex, radix: 16) else { return nil }
        return NSColor(
            srgbRed: CGFloat((number >> 16) & 255) / 255, green: CGFloat((number >> 8) & 255) / 255,
            blue: CGFloat(number & 255) / 255, alpha: 1)
    }
    if text.hasPrefix("rgb") {
        let numbers = text.split(whereSeparator: { !"0123456789.".contains($0) }).compactMap { Double($0) }
        guard numbers.count >= 3 else { return nil }
        return NSColor(srgbRed: numbers[0] / 255, green: numbers[1] / 255, blue: numbers[2] / 255, alpha: 1)
    }
    let named: [String: NSColor] = [
        "red": .systemRed, "blue": .systemBlue, "green": .systemGreen, "orange": .systemOrange, "gray": .gray,
        "grey": .gray, "black": .black, "white": .white,
    ]
    return named[text]
}
