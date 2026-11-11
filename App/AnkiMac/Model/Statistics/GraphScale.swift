import SwiftUI

/// The parts of d3 that upstream's graphs use to shape their data: tick
/// placement, domain rounding, binning and the colour ramps. Ported from
/// d3-array 3.2 and d3-scale 4, so the same collection gives the same bars.
nonisolated enum GraphScale {
    private static let e10 = 50.0.squareRoot(), e5 = 10.0.squareRoot(), e2 = 2.0.squareRoot()

    private static func tickSpec(_ start: Double, _ stop: Double, _ count: Double) -> (Double, Double, Double) {
        let step = (stop - start) / max(0, count)
        let power = floor(log10(step))
        let error = step / pow(10, power)
        let factor: Double = error >= e10 ? 10 : error >= e5 ? 5 : error >= e2 ? 2 : 1
        var i1: Double, i2: Double, inc: Double
        if power < 0 {
            inc = pow(10, -power) / factor
            i1 = jsRound(start * inc)
            i2 = jsRound(stop * inc)
            if i1 / inc < start { i1 += 1 }
            if i2 / inc > stop { i2 -= 1 }
            inc = -inc
        } else {
            inc = pow(10, power) * factor
            i1 = jsRound(start / inc)
            i2 = jsRound(stop / inc)
            if i1 * inc < start { i1 += 1 }
            if i2 * inc > stop { i2 -= 1 }
        }
        if i2 < i1, 0.5 <= count, count < 2 { return tickSpec(start, stop, count * 2) }
        return (i1, i2, inc)
    }

    /// JavaScript's Math.round: halves go towards +infinity.
    private static func jsRound(_ x: Double) -> Double { floor(x + 0.5) }

    /// d3.ticks: about `count` round values from start to stop.
    static func ticks(_ start: Double, _ stop: Double, count: Double) -> [Double] {
        guard count > 0 else { return [] }
        if start == stop { return [start] }
        let reverse = stop < start
        let (i1, i2, inc) = reverse ? tickSpec(stop, start, count) : tickSpec(start, stop, count)
        guard i2 >= i1 else { return [] }
        let n = Int(i2 - i1) + 1
        return (0..<n).map { i in
            let k = reverse ? i2 - Double(i) : i1 + Double(i)
            return inc < 0 ? k / -inc : k * inc
        }
    }

    static func tickIncrement(_ start: Double, _ stop: Double, count: Double) -> Double {
        tickSpec(start, stop, count).2
    }

    /// d3's linear scale `.nice()`: widens the domain to round values.
    static func nice(_ domain: (Double, Double), count: Double = 10) -> (Double, Double) {
        var (start, stop) = domain
        let reversed = stop < start
        if reversed { swap(&start, &stop) }
        var previous: Double?
        for _ in 0..<10 {
            let step = tickIncrement(start, stop, count: count)
            if step == previous { break }
            if step > 0 {
                start = floor(start / step) * step
                stop = ceil(stop / step) * step
            } else if step < 0 {
                start = ceil(start * step) / step
                stop = floor(stop * step) / step
            } else {
                return domain
            }
            previous = step
        }
        return reversed ? (stop, start) : (start, stop)
    }

    /// d3.bin with a fixed domain and thresholds: bin i holds the points in
    /// [threshold i-1, threshold i), the last one also its upper bound.
    /// Points outside the domain are dropped.
    static func bin<Point>(
        _ points: some Sequence<Point>, value: (Point) -> Double, domain: (Double, Double), thresholds: [Double]
    ) -> [Bin<Point>] {
        let (x0, x1) = domain
        var inner = thresholds[...]
        while let first = inner.first, first <= x0 { inner.removeFirst() }
        while let last = inner.last, last > x1 { inner.removeLast() }
        let edges = Array(inner)
        var bins = (0...edges.count).map { i in
            Bin<Point>(x0: i > 0 ? edges[i - 1] : x0, x1: i < edges.count ? edges[i] : x1)
        }
        for point in points {
            let x = value(point)
            guard x0 <= x, x <= x1 else { continue }
            var lo = 0, hi = edges.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if x < edges[mid] { hi = mid } else { lo = mid + 1 }
            }
            bins[lo].points.append(point)
        }
        return bins
    }

    struct Bin<Point> {
        var x0: Double
        var x1: Double
        var points: [Point] = []
    }

    /// d3.quantileSorted over values given as sorted (value, count) runs.
    static func quantile(sortedRuns runs: [(value: Double, count: Int)], _ p: Double) -> Double? {
        let n = runs.reduce(0) { $0 + $1.count }
        guard n > 0 else { return nil }
        func value(at index: Int) -> Double {
            var remaining = index
            for run in runs {
                if remaining < run.count { return run.value }
                remaining -= run.count
            }
            return runs.last!.value
        }
        if p <= 0 || n < 2 { return value(at: 0) }
        if p >= 1 { return value(at: n - 1) }
        let i = Double(n - 1) * p
        let i0 = Int(floor(i))
        let v0 = value(at: i0), v1 = value(at: i0 + 1)
        return v0 + (v1 - v0) * (i - Double(i0))
    }

    /// Maps [d0, d1] linearly onto [r0, r1], like a d3 linear scale.
    static func linear(_ value: Double, domain: (Double, Double), range: (Double, Double)) -> Double {
        let (d0, d1) = domain, (r0, r1) = range
        guard d1 != d0 else { return (r0 + r1) / 2 }
        return r0 + (value - d0) / (d1 - d0) * (r1 - r0)
    }
}

/// d3-scale-chromatic's ramps: a B-spline through a ColorBrewer scheme.
nonisolated struct ColorRamp: Sendable {
    private let channels: [[Double]]

    init(_ hex: String) {
        let colors = stride(from: 0, to: hex.count, by: 6).map { offset -> [Double] in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            let value = Int(hex[start..<hex.index(start, offsetBy: 6)], radix: 16)!
            return [Double(value >> 16 & 0xff), Double(value >> 8 & 0xff), Double(value & 0xff)]
        }
        channels = (0..<3).map { c in colors.map { $0[c] } }
    }

    func callAsFunction(_ t: Double) -> Color {
        let rgb = channels.map { Self.basis($0, t) }
        return Color(.sRGB, red: rgb[0] / 255, green: rgb[1] / 255, blue: rgb[2] / 255)
    }

    private static func basis(_ values: [Double], _ t: Double) -> Double {
        let n = values.count - 1
        var t = t
        let i: Int
        if t <= 0 {
            t = 0
            i = 0
        } else if t >= 1 {
            t = 1
            i = n - 1
        } else {
            i = Int(floor(t * Double(n)))
        }
        let v1 = values[i], v2 = values[i + 1]
        let v0 = i > 0 ? values[i - 1] : 2 * v1 - v2
        let v3 = i < n - 1 ? values[i + 2] : 2 * v2 - v1
        let t1 = (t - Double(i) / Double(n)) * Double(n)
        let t2 = t1 * t1, t3 = t2 * t1
        return ((1 - 3 * t1 + 3 * t2 - t3) * v0 + (4 - 6 * t2 + 3 * t3) * v1
            + (1 + 3 * t1 + 3 * t2 - 3 * t3) * v2 + t3 * v3) / 6
    }

    static let blues = ColorRamp("f7fbffdeebf7c6dbef9ecae16baed64292c62171b508519c08306b")
    static let greens = ColorRamp("f7fcf5e5f5e0c7e9c0a1d99b74c47641ab5d238b45006d2c00441b")
    static let reds = ColorRamp("fff5f0fee0d2fcbba1fc9272fb6a4aef3b2ccb181da50f1567000d")
    static let oranges = ColorRamp("fff5ebfee6cefdd0a2fdae6bfd8d3cf16913d94801a636037f2704")
    static let purples = ColorRamp("fcfbfdefedf5dadaebbcbddc9e9ac8807dba6a51a354278f3f007d")
    static let redYellowGreen = ColorRamp("a50026d73027f46d43fdae61fee08bffffbfd9ef8ba6d96a66bd631a9850006837")
}

extension Color {
    /// A `#rrggbb` colour, for the fixed swatches desktop's graphs use.
    nonisolated init(hex: UInt32) {
        self.init(
            .sRGB, red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255,
            blue: Double(hex & 0xff) / 255)
    }
}
