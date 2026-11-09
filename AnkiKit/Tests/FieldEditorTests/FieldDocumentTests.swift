import AppKit
import Foundation
import SQLite3
import Testing

@testable import FieldEditor

private var style: FieldStyle { FieldStyle(
    font: .systemFont(ofSize: 14), codeFont: .monospacedSystemFont(ofSize: 13, weight: .regular),
    textColor: .textColor, unknownTagBackground: .systemYellow, chipFont: .systemFont(ofSize: 10),
    chipFill: .gray, chipText: .black, imageMaxHeight: 80) }

/// Loads a field, applies an edit to the text the editor would show, and
/// exports it.
private func edit(_ html: String, _ change: (FieldDocument, NSTextStorage) -> Void = { _, _ in }) -> String {
    let document = FieldDocument(html: html, style: style)
    let storage = NSTextStorage(attributedString: document.text)
    change(document, storage)
    return document.html(from: storage)
}

private func range(of word: String, in storage: NSTextStorage) -> NSRange {
    (storage.string as NSString).range(of: word)
}

/// Fields that broke earlier converters: unclosed and misnested tags,
/// entities, comments, tables, custom tags, MathJax and cloze syntax.
let awkwardFields: [String] = [
    "<span style=\"font-weight: bold; color: rgb(255, 0, 0);\">red <span style=\"font-style:italic\">nested</span></span> tail",
    "<table><tr><td>a</td><td><b>b</b></td></tr></table>",
    "{{c1::<b>Paris</b>::capital}} is in {{c2::France}}",
    "\\(a < b \\) and \\[x^2 > y\\]",
    "\\(a &lt; b\\) and \\[x^2 &gt; y\\]",
    "&nbsp;&nbsp;indented &amp; &lt;tag&gt; &eacute; &#233; &#xE9; &unknownentity; &amp",
    "line1<br>line2<br/>line3<br />",
    "<div>one</div><div>two</div><div><br></div>",
    "before<!-- a comment -->after",
    "<foo-bar data-x=\"1\">custom</foo-bar> <x:y>ns</x:y>",
    "",
    "<img src=\"paste-123.png\"> [sound:audio.mp3]",
    "<a href=\"https://ankiweb.net\">link</a>",
    "[latex]\\begin{matrix} a & b \\end{matrix}[/latex]",
    "<ul><li>one</li><li>two</li></ul>",
    "<b>unclosed bold <i>and italic",
    "text</span> more</div>",
    "<span class='x' data-a=unquoted title=\"a>b\">q</span>",
    "<font color=\"#ff0000\">red</font> <sup>2</sup> <sub>i</sub> <u>u</u> <s>s</s>",
    "  leading\n\ttabs   multiple   spaces\n",
    "<pre>code\n  indented</pre>",
    "<div style=\"text-align: center;\"><span style=\"font-size: 20px;\">Big</span></div>",
    "<b><i>overlap</b></i>",
    "émoji 😀 \r\n done",
    "<svg><path d=\"M0 0\"/></svg>",
    "a<b></b>c<i></i>",
    "<style>.x{color:red}</style><span class=\"x\">styled</span>",
    "<img src=\"a&amp;b.png\" alt=\"\">",
    "x < y and y > z",
    "<b>bold</b><b>adjacent</b>",
    "<span style=\"color: rgb(0, 0, 255);\">blue</span>&nbsp;",
]

/// Every field of the bench collections: the regression check the
/// prototype passed at 100%.
private func corpus() -> [String] {
    let fixtures = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../bench/fixtures")
        .standardized
    func fields(_ name: String, notes: Int) -> [String] {
        let path = fixtures.appending(path: "\(name)/collection.anki2").path
        var db: OpaquePointer?
        guard sqlite3_open_v2("file:\(path)?immutable=1", &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK
        else { return [] }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, "select flds from notes order by id limit \(notes)", -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        var out: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            out += String(cString: sqlite3_column_text(statement, 0))
                .split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
        }
        return out
    }
    return fields("user", notes: 100_000) + fields("large", notes: 2500)
}

@Test func corpusRoundTripsByteForByte() {
    let fields = corpus() + awkwardFields
    #expect(fields.count >= 6_000, "the bench fixtures are missing")
    var changed: [String] = []
    for field in fields where edit(field) != field {
        changed.append(field)
    }
    #expect(changed.isEmpty, "\(changed.count) of \(fields.count) fields changed, first: \(changed.first ?? "")")
}

@Test(arguments: awkwardFields)
func awkwardFieldRoundTrips(_ field: String) {
    #expect(edit(field) == field)
}

@Test func typingChangesOnlyWhatWasTyped() {
    let html = "<div>caf&eacute; &amp; <b>cr&egrave;me</b></div>"
    let result = edit(html) { _, storage in
        let at = range(of: "&", in: storage).location
        storage.replaceCharacters(in: NSRange(location: at, length: 0), with: "X<")
    }
    #expect(result == "<div>caf&eacute; X&lt;&amp; <b>cr&egrave;me</b></div>")
}

@Test func boldingAddsOnlyTheTag() {
    let result = edit("<div>Paris is in France</div>") { document, storage in
        document.toggle(.bold, in: storage, range: range(of: "France", in: storage))
    }
    #expect(result == "<div>Paris is in <b>France</b></div>")
}

@Test func unboldingPartOfAnOriginalTagSplitsIt() {
    let result = edit("<B>bold text</B> after") { document, storage in
        document.toggle(.bold, in: storage, range: range(of: "text", in: storage))
    }
    #expect(result == "<B>bold </B>text after")
}

@Test func unboldingAStyledSpanKeepsItsOtherStyles() {
    let result = edit("<span style=\"font-weight: bold; color: red\">x</span>") { document, storage in
        document.toggle(.bold, in: storage, range: NSRange(location: 0, length: 1))
    }
    #expect(result == "<span style=\"color: red;\">x</span>")
}

@Test func unboldingABoldOnlySpanDropsIt() {
    let result = edit("a<span style=\"font-weight:700\">b</span>") { document, storage in
        document.toggle(.bold, in: storage, range: range(of: "b", in: storage))
    }
    #expect(result == "ab")
}

@Test func superscriptReplacesSubscript() {
    let result = edit("H<sub>2</sub>O") { document, storage in
        document.toggle(.superscript, in: storage, range: range(of: "2", in: storage))
    }
    #expect(result == "H<sup>2</sup>O")
}

@Test func colouringWrapsInASpanAsDesktopDoes() {
    let result = edit("<div>Paris is in France</div>") { document, storage in
        document.setColor(.text, red: 255, green: 0, blue: 0, in: storage, range: range(of: "France", in: storage))
    }
    #expect(result == "<div>Paris is in <span style=\"color: rgb(255, 0, 0);\">France</span></div>")
}

@Test func recolouringReplacesTheColour() {
    let result = edit("a<font color=\"#00f\">b</font><span style=\"background-color: red; font-weight: bold\">c</span>") {
        document, storage in
        let all = NSRange(location: 0, length: storage.length)
        document.setColor(.text, red: 0, green: 128, blue: 0, in: storage, range: all)
        document.setColor(.text, red: 1, green: 2, blue: 3, in: storage, range: all)
        document.setColor(.highlight, red: 255, green: 255, blue: 0, in: storage, range: range(of: "c", in: storage))
    }
    #expect(result == "<span style=\"color: rgb(1, 2, 3);\">ab</span><span style=\"font-weight: bold;\">"
        + "<span style=\"color: rgb(1, 2, 3);\"><span style=\"background-color: rgb(255, 255, 0);\">c</span></span></span>")
}

@Test func isAppliedSeesTagsAndStyles() {
    let document = FieldDocument(html: "<i>a</i><span style=\"font-style: italic\">b</span>c", style: style)
    #expect(document.isApplied(.italic, in: document.text, range: NSRange(location: 0, length: 2)))
    #expect(!document.isApplied(.italic, in: document.text, range: NSRange(location: 0, length: 3)))
}

@Test func removeFormattingKeepsLinksAndBlocks() {
    let result = edit("<div><a href=\"x\"><b>link</b></a> <font color=\"red\">red</font></div>") { document, storage in
        document.removeFormatting(in: storage, range: NSRange(location: 0, length: storage.length))
    }
    #expect(result == "<div><a href=\"x\">link</a> red</div>")
}

@Test func deletingTheBreakBetweenBlocksJoinsThem() {
    let result = edit("<div>one</div><div>two</div>") { document, storage in
        let newline = range(of: "\n", in: storage)
        document.prepareDeletion(of: newline, in: storage)
        storage.deleteCharacters(in: newline)
        document.finishEdit(storage)
    }
    #expect(result == "<div>onetwo</div>")
}

@Test func pastedHTMLIsInsertedEscaped() {
    let result = edit("<div>ab</div>") { document, storage in
        let at = range(of: "b", in: storage).location
        let stack = storage.attribute(.fieldStack, at: at, effectiveRange: nil) as? [Int] ?? []
        storage.insert(document.fragment(html: "<b>x &amp; y</b>", base: stack), at: at)
    }
    #expect(result == "<div>a<b>x &amp; y</b>b</div>")
}

@Test func typingAfterALineBreakIsText() {
    let document = FieldDocument(html: "a<br>", style: style)
    let attributes = document.text.attributes(at: 1, effectiveRange: nil)
    let typing = FieldDocument.cleanTypingAttributes(attributes)
    let storage = NSTextStorage(attributedString: document.text)
    storage.append(NSAttributedString(string: "b", attributes: typing))
    #expect(document.html(from: storage) == "a<br>b")
}

@Test func clozeNumbersFollowTheHighest() {
    #expect(FieldDocument.nextClozeNumber(in: ["{{c1::a}} {{c3::b}}", "{{c2::c}}"]) == 4)
    #expect(FieldDocument.nextClozeNumber(in: ["none"]) == 1)
}

@Test func pasteKeepsSimpleFormattingAndDropsTheRest() {
    let html = "<p class=\"x\">Hi <b>there</b> <span style=\"color: red; font-size: 30px\">red</span>"
        + "<script>alert(1)</script><o:p>office</o:p><img src=\"a.png\" width=\"9\"></p>"
    #expect(PasteFilter.filter(html, keepFormatting: true)
        == "<div>Hi <b>there</b> <span style=\"color: red;\">red</span>office<img src=\"a.png\"></div>")
    #expect(PasteFilter.filter(html, keepFormatting: false) == "<div>Hi there redoffice<img src=\"a.png\"></div>")
}
