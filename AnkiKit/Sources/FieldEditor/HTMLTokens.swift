import Foundation

/// One piece of a field's HTML, with the bytes it came from.
enum HTMLToken: Equatable {
    case text(String)
    case open(name: String, raw: String, selfClosing: Bool)
    case close(name: String, raw: String)
    /// Comments, doctypes and processing instructions, kept as they were.
    case comment(String)
}

/// A tolerant tokenizer: never fails, never normalises. Anything that isn't
/// a well-formed tag (a lone `<`, `a < b`) stays text, so concatenating the
/// raw pieces gives back the input byte for byte.
func tokenizeHTML(_ html: String) -> [HTMLToken] {
    let bytes = Array(html.utf8)
    var tokens: [HTMLToken] = []
    var index = 0
    var textStart = 0

    func string(_ start: Int, _ end: Int) -> String { String(decoding: bytes[start..<end], as: UTF8.self) }
    func flushText(_ end: Int) {
        if end > textStart { tokens.append(.text(string(textStart, end))) }
    }
    func isLetter(_ byte: UInt8) -> Bool { (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) }
    func isSpace(_ byte: UInt8) -> Bool { byte == 32 || byte == 9 || byte == 10 || byte == 13 }

    while index < bytes.count {
        guard bytes[index] == UInt8(ascii: "<") else {
            index += 1
            continue
        }
        let next = index + 1 < bytes.count ? bytes[index + 1] : 0
        if next == UInt8(ascii: "!") || next == UInt8(ascii: "?") {
            let isComment = index + 3 < bytes.count && bytes[index + 2] == 45 && bytes[index + 3] == 45
            var end: Int
            if isComment {
                end = index + 4
                while end + 2 < bytes.count, !(bytes[end] == 45 && bytes[end + 1] == 45 && bytes[end + 2] == 62) {
                    end += 1
                }
                end = min(bytes.count, end + 3)
            } else {
                end = index + 2
                while end < bytes.count, bytes[end] != UInt8(ascii: ">") { end += 1 }
                end = min(bytes.count, end + 1)
            }
            flushText(index)
            tokens.append(.comment(string(index, end)))
            index = end
            textStart = end
            continue
        }
        let closing = next == UInt8(ascii: "/")
        let nameStart = closing ? index + 2 : index + 1
        guard nameStart < bytes.count, isLetter(bytes[nameStart]) else {
            index += 1
            continue
        }
        var end = nameStart
        while end < bytes.count, !isSpace(bytes[end]), bytes[end] != UInt8(ascii: "/"), bytes[end] != UInt8(ascii: ">") {
            end += 1
        }
        let name = string(nameStart, end).lowercased()
        // Find the closing ">", skipping quoted attribute values.
        var quote: UInt8 = 0
        var lastNonSpace: UInt8 = 0
        while end < bytes.count {
            let byte = bytes[end]
            if quote != 0 {
                if byte == quote { quote = 0 }
            } else if (byte == 34 || byte == 39) && lastNonSpace == UInt8(ascii: "=") {
                quote = byte
            } else if byte == UInt8(ascii: ">") {
                break
            }
            if !isSpace(byte) { lastNonSpace = byte }
            end += 1
        }
        guard end < bytes.count else {
            index += 1
            continue
        }
        let raw = string(index, end + 1)
        flushText(index)
        if closing {
            tokens.append(.close(name: name, raw: raw))
        } else {
            tokens.append(.open(name: name, raw: raw, selfClosing: bytes[end - 1] == UInt8(ascii: "/")))
        }
        index = end + 1
        textStart = index
    }
    flushText(bytes.count)
    return tokens
}

private let namedEntities: [String: String] = [
    "nbsp": "\u{00A0}", "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
    "eacute": "é", "egrave": "è", "agrave": "à", "ccedil": "ç", "ecirc": "ê", "ocirc": "ô",
    "laquo": "«", "raquo": "»", "hellip": "…", "mdash": "—", "ndash": "–", "times": "×", "deg": "°",
    "rarr": "→", "larr": "←", "copy": "©", "euro": "€", "rsquo": "\u{2019}", "lsquo": "\u{2018}",
]

/// Text decoded for display, as UTF-16 units, each paired with the source
/// bytes it came from: an entity's first unit carries the whole entity, the
/// rest of a multi-unit character carries nothing.
struct DecodedText {
    var units: [UInt16] = []
    var sources: [String] = []
}

func decodeHTMLText(_ raw: String) -> DecodedText {
    var decoded = DecodedText()
    let scalars = Array(raw.unicodeScalars)
    var index = 0
    func push(_ shown: String, source: String) {
        for (offset, unit) in shown.utf16.enumerated() {
            decoded.units.append(unit)
            decoded.sources.append(offset == 0 ? source : "")
        }
    }
    while index < scalars.count {
        let scalar = scalars[index]
        if scalar == "&" {
            var end = index + 1
            while end < scalars.count, end - index < 12, scalars[end] != ";", scalars[end] != "&", scalars[end] != " " {
                end += 1
            }
            if end < scalars.count, scalars[end] == ";" {
                let body = String(String.UnicodeScalarView(scalars[(index + 1)..<end]))
                let source = String(String.UnicodeScalarView(scalars[index...end]))
                var value = namedEntities[body]
                if value == nil, body.hasPrefix("#") {
                    let number = body.dropFirst()
                    let code = number.hasPrefix("x") || number.hasPrefix("X")
                        ? UInt32(number.dropFirst(), radix: 16) : UInt32(number)
                    if let code, let character = Unicode.Scalar(code) { value = String(character) }
                }
                if let value {
                    push(value, source: source)
                    index = end + 1
                    continue
                }
            }
        }
        let source = String(scalar)
        // HTML collapses line breaks and tabs to spaces when it renders.
        push(scalar == "\n" || scalar == "\r" || scalar == "\t" ? " " : source, source: source)
        index += 1
    }
    return decoded
}

/// Text the user typed, as HTML: markup characters escaped, line breaks as
/// `<br>`, and the editor's invisible placeholders dropped.
func escapeHTML(_ text: String) -> String {
    var html = ""
    for scalar in text.unicodeScalars {
        switch scalar {
        case "&": html += "&amp;"
        case "<": html += "&lt;"
        case ">": html += "&gt;"
        case "\u{00A0}": html += "&nbsp;"
        case "\n", "\u{2028}": html += "<br>"
        case "\u{200B}", "\u{FFFC}": break
        default: html.unicodeScalars.append(scalar)
        }
    }
    return html
}

private let attributePattern = try! NSRegularExpression(
    pattern: #"([^\s"'>/=]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?"#)

/// The attributes of an opening tag, in order, names lowercased.
func parseAttributes(_ tag: String) -> [(name: String, value: String)] {
    let ns = tag as NSString
    guard ns.length > 2 else { return [] }
    let inner = ns.substring(with: NSRange(location: 1, length: ns.length - 2)) as NSString
    let matches = attributePattern.matches(in: inner as String, range: NSRange(location: 0, length: inner.length))
    // The first match is the tag name.
    return matches.dropFirst().map { match in
        let name = inner.substring(with: match.range(at: 1)).lowercased()
        let value = (2...4).first { match.range(at: $0).location != NSNotFound }
            .map { inner.substring(with: match.range(at: $0)) } ?? ""
        return (name, value)
    }
}

/// A style attribute's declarations, property names lowercased.
func parseCSS(_ style: String) -> [(property: String, value: String)] {
    style.split(separator: ";").compactMap { declaration in
        let parts = declaration.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        return parts.count == 2 && !parts[0].isEmpty ? (parts[0].lowercased(), parts[1]) : nil
    }
}
