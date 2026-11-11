import Foundation

/// One mask on an image occlusion note, with its position and size as
/// fractions of the image's width and height, as upstream stores them
/// (ts/routes/image-occlusion/shapes).
struct OcclusionShape: Hashable {
    enum Geometry: Hashable {
        case rect(width: Double, height: Double)
        /// `rx` is a fraction of the width, `ry` of the height; the ellipse
        /// fills the box from (left, top) of twice those.
        case ellipse(rx: Double, ry: Double)
        /// The points' bounding box is drawn with its corner at (left, top).
        case polygon(points: [OcclusionPoint])
        /// `fontSize` is a fraction of the image's height.
        case text(String, scale: Double, fontSize: Double?)
    }

    var geometry: Geometry
    var left: Double
    var top: Double
    /// Degrees clockwise about (left, top), as the reviewer draws it.
    var angle: Double = 0
    /// A colour other than the default: the mask colour, or black for text.
    var fill: String?

    static let maskColor = "#ffeba2"
    static let textColor = "#000000"

    var isText: Bool {
        if case .text = geometry { true } else { false }
    }

    var kind: String {
        switch geometry {
        case .rect: "rect"
        case .ellipse: "ellipse"
        case .polygon: "polygon"
        case .text: "text"
        }
    }
}

struct OcclusionPoint: Hashable {
    var x: Double
    var y: Double
}

/// The shapes one cloze number hides: a single shape, or a group, which
/// hides and reveals together.
struct Occlusion: Identifiable, Hashable {
    var id = UUID()
    var shapes: [OcclusionShape]
    /// The cloze number, kept once given; nil for a mask not yet saved.
    /// Text labels are 0: they show on every card.
    var ordinal: Int?

    var isText: Bool { shapes.count == 1 && shapes[0].isText }
}

extension Occlusion {
    /// Several masks as one group, as desktop's Group: it keeps the lowest
    /// number among them, or is numbered afresh when one has none yet. A
    /// label's 0 doesn't count, since a group is a mask with a card of its own.
    init(grouping members: [Occlusion]) {
        let ordinals = members.map(\.ordinal).filter { $0 != 0 }
        self.init(
            shapes: members.flatMap(\.shapes), ordinal: ordinals.contains(nil) ? nil : ordinals.compactMap(\.self).min())
    }
}

// MARK: Cloze text

/// The occlusion field's text, ported from upstream's shapes/to-cloze.ts
/// and from-cloze.ts so a note written by either reads back the same.
enum OcclusionCloze {
    /// Numbers unsaved masks as desktop does (filling gaps first, text as
    /// 0) and writes each shape as
    /// `{{c1::image-occlusion:rect:left=.2:top=.3:width=.1:height=.1:oi=1}}<br>`.
    /// Returns the masks with their numbers, to keep for the next save.
    static func text(_ occlusions: [Occlusion], occludeInactive: Bool) -> (text: String, numbered: [Occlusion]) {
        let ordinals = occlusions.map(\.ordinal)
        let maxOrdinal = ordinals.compactMap(\.self).max().map { max($0, 0) } ?? 0
        var missing = maxOrdinal >= 1 ? (1...maxOrdinal).filter { !ordinals.contains($0) } : []
        var next = maxOrdinal + 1
        var numbered = occlusions
        var text = ""
        for index in numbered.indices {
            if numbered[index].ordinal == nil {
                if numbered[index].isText {
                    numbered[index].ordinal = 0
                } else if !missing.isEmpty {
                    numbered[index].ordinal = missing.removeFirst()
                } else {
                    numbered[index].ordinal = next
                    next += 1
                }
            }
            let ordinal = numbered[index].ordinal!
            for shape in numbered[index].shapes {
                text += cloze(shape, ordinal: ordinal, occludeInactive: occludeInactive)
            }
        }
        return (text, numbered)
    }

    /// How many cards the masks make: every mask but text labels.
    static func cardCount(_ occlusions: [Occlusion]) -> Int {
        occlusions.count { !$0.isText }
    }

    private static func cloze(_ shape: OcclusionShape, ordinal: Int, occludeInactive: Bool) -> String {
        var properties = [("left", display(shape.left)), ("top", display(shape.top))]
        let angle = storedAngle(shape.angle)
        if angle != 0 { properties.append(("angle", String(angle))) }
        var defaultFill = OcclusionShape.maskColor
        switch shape.geometry {
        case .rect(let width, let height):
            properties += [("width", display(width)), ("height", display(height))]
        case .ellipse(let rx, let ry):
            properties += [("rx", display(rx)), ("ry", display(ry))]
        case .polygon(let points):
            properties.append(("points", points.map { "\(display($0.x)),\(display($0.y))" }.joined(separator: " ")))
        case .text(let text, let scale, let fontSize):
            properties += [("text", text), ("scale", display(scale))]
            if let fontSize, fontSize != 0 { properties.append(("fs", display(fontSize))) }
            defaultFill = OcclusionShape.textColor
        }
        if let fill = shape.fill, fill != defaultFill { properties.append(("fill", fill)) }
        if occludeInactive { properties.append(("oi", "1")) }
        let body = properties.map { name, value in
            ":\(name)=" + value.replacing("\\", with: "\\\\").replacing(":", with: "\\:")
        }.joined()
        return "{{c\(ordinal)::image-occlusion:\(shape.kind)\(body)}}<br>"
    }

    /// Upstream's floatToDisplay: JavaScript's `toFixed(4)` without leading
    /// or trailing zeros, so 0.25 is ".25" and 1 is "1.".
    static func display(_ number: Double) -> String {
        if number.isNaN || number == 0 { return ".0000" }
        var text = toFixed4(number)
        while text.hasPrefix("0") { text.removeFirst() }
        while text.hasSuffix("0") { text.removeLast() }
        return text
    }

    /// `toFixed` rounds an exact tie away from zero; printf rounds it to
    /// even. A double is exactly halfway between two 4-place decimals only
    /// when it is an odd multiple of 1/32 (a 20px mask on a 640px image).
    private static func toFixed4(_ number: Double) -> String {
        let thirtySeconds = abs(number) * 32
        guard thirtySeconds == thirtySeconds.rounded(), thirtySeconds.truncatingRemainder(dividingBy: 2) == 1 else {
            return String(format: "%.4f", number)
        }
        let units = Int((abs(number) * 10000).rounded(.up))
        let fraction = String(units % 10000)
        return (number < 0 ? "-" : "") + "\(units / 10000)." + String(repeating: "0", count: 4 - fraction.count) + fraction
    }

    /// Angles are stored in ten-thousandths of a turn.
    static func storedAngle(_ degrees: Double) -> Int {
        Int((degrees.truncatingRemainder(dividingBy: 360) / 360 * 10000 + 0.5).rounded(.down))
    }

    // MARK: Reading

    /// The masks of one cloze number as the backend parsed them
    /// (GetImageOcclusionNote): each shape's name and properties.
    struct Parsed {
        var ordinal: Int
        var shapes: [(kind: String, properties: [(name: String, value: String)])]
    }

    /// Masks from the parsed field, grouped as they were saved: a cloze
    /// number with several shapes is a group, and each text label stands
    /// alone. Sorted by number, since the backend's order is arbitrary.
    static func occlusions(_ parsed: [Parsed]) -> [Occlusion] {
        parsed.sorted { $0.ordinal < $1.ordinal }.flatMap { occlusion -> [Occlusion] in
            let shapes = occlusion.shapes.compactMap { shape(kind: $0.kind, properties: $0.properties) }
            if occlusion.ordinal == 0 {
                return shapes.map { Occlusion(shapes: [$0], ordinal: 0) }
            }
            return shapes.isEmpty ? [] : [Occlusion(shapes: shapes, ordinal: occlusion.ordinal)]
        }
    }

    /// Upstream's buildShape: unreadable numbers count as 0.
    static func shape(kind: String, properties: [(name: String, value: String)]) -> OcclusionShape? {
        let values = Dictionary(properties.map { ($0.name, $0.value) }, uniquingKeysWith: { _, last in last })
        func number(_ name: String) -> Double { values[name].flatMap(Double.init) ?? 0 }
        let geometry: OcclusionShape.Geometry
        switch kind {
        case "rect":
            geometry = .rect(width: number("width"), height: number("height"))
        case "ellipse":
            geometry = .ellipse(rx: number("rx"), ry: number("ry"))
        case "polygon":
            let points = (values["points"] ?? "").split(separator: " ").map { pair in
                let xy = pair.split(separator: ",", omittingEmptySubsequences: false)
                return OcclusionPoint(
                    x: xy.first.flatMap { Double($0) } ?? 0, y: xy.dropFirst().first.flatMap { Double($0) } ?? 0)
            }
            geometry = .polygon(points: points.isEmpty ? [OcclusionPoint(x: 0, y: 0)] : points)
        case "text":
            geometry = .text(
                values["text"] ?? "", scale: values["scale"].flatMap(Double.init) ?? 1,
                fontSize: values["fs"].flatMap(Double.init))
        default:
            return nil
        }
        let angle = values["angle"].flatMap(Double.init).map { $0.truncatingRemainder(dividingBy: 10000) / 10000 * 360 }
        return OcclusionShape(
            geometry: geometry, left: number("left"), top: number("top"), angle: angle ?? 0, fill: values["fill"])
    }
}
