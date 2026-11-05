import CoreGraphics

/// Draws box, block and braille characters to the exact cell, rather than using
/// the font's versions. With extra line spacing a font's box glyphs stop short of
/// the cell edges, leaving gaps in every TUI border.
enum BoxDrawing {
    private enum Weight {
        static let none = 0
        static let heavy = 2
        static let double = 3
    }

    /// Up, right, down, left weights for U+2500 to U+254B, four digits each.
    /// A zero entry means the character is handled separately (dashes).
    private static let lines: [String] = [
        "0101", "0202", "1010", "2020", "0000", "0000", "0000", "0000", "0000", "0000", "0000", "0000",
        "0110", "0210", "0120", "0220", "0011", "0012", "0021", "0022", "1100", "1200", "2100", "2200",
        "1001", "1002", "2001", "2002", "1110", "1210", "2110", "1120", "2120", "2210", "1220", "2220",
        "1011", "1012", "2011", "1021", "2021", "2012", "1022", "2022", "0111", "0112", "0211", "0212",
        "0121", "0122", "0221", "0222", "1101", "1102", "1201", "1202", "2101", "2102", "2201", "2202",
        "1111", "1112", "1211", "1212", "2111", "1121", "2121", "2112", "2211", "1122", "1221", "2212",
        "1222", "2122", "2221", "2222",
    ]

    /// The same for U+2550 to U+256C.
    private static let doubleLines: [String] = [
        "0303", "3030", "0310", "0130", "0330", "0013", "0031", "0033", "1300", "3100", "3300",
        "1003", "3001", "3003", "1310", "3130", "3330", "1013", "3031", "3033", "0313", "0131",
        "0333", "1303", "3101", "3303", "1313", "3131", "3333",
    ]

    /// The same for U+2574 to U+257F.
    private static let halfLines: [String] = [
        "0001", "1000", "0100", "0010", "0002", "2000", "0200", "0020", "0201", "1020", "0102", "2010",
    ]

    static func handles(_ codepoint: UInt32) -> Bool {
        switch codepoint {
        case 0x2500...0x2570, 0x2574...0x259F, 0x2800...0x28FF: return true
        default: return false
        }
    }

    static func draw(_ codepoint: UInt32, in context: CGContext, width: Int, height: Int) {
        let w = CGFloat(width)
        let h = CGFloat(height)
        let thin = max(1, (h * 0.065).rounded())
        let thick = thin * 2

        switch codepoint {
        case 0x2504...0x250B, 0x254C...0x254F:
            dashes(codepoint, context, w, h, thin, thick)
        case 0x2500...0x254B:
            segments(lines[Int(codepoint - 0x2500)], context, w, h, thin, thick)
        case 0x2550...0x256C:
            segments(doubleLines[Int(codepoint - 0x2550)], context, w, h, thin, thick)
        case 0x256D...0x2570:
            arc(codepoint, context, w, h, thin)
        case 0x2574...0x257F:
            segments(halfLines[Int(codepoint - 0x2574)], context, w, h, thin, thick)
        case 0x2580...0x259F:
            block(codepoint, context, w, h)
        case 0x2800...0x28FF:
            braille(codepoint, context, w, h)
        default:
            break
        }
    }

    private static func segments(_ code: String, _ context: CGContext, _ w: CGFloat, _ h: CGFloat,
                                 _ thin: CGFloat, _ thick: CGFloat) {
        let weights = code.utf8.map { Int($0) - 48 }
        let up = weights[0], right = weights[1], down = weights[2], left = weights[3]

        func size(_ weight: Int) -> CGFloat { weight == Weight.heavy ? thick : thin }
        let cx = ((w - thin) / 2).rounded(.down)
        let cy = ((h - thin) / 2).rounded(.down)

        func vertical(from: CGFloat, to: CGFloat, weight: Int) {
            guard weight != Weight.none else { return }
            if weight == Weight.double {
                context.fill(CGRect(x: cx - thin, y: from, width: thin, height: to - from))
                context.fill(CGRect(x: cx + thin, y: from, width: thin, height: to - from))
            } else {
                let t = size(weight)
                context.fill(CGRect(x: cx - ((t - thin) / 2).rounded(.down), y: from, width: t, height: to - from))
            }
        }

        func horizontal(from: CGFloat, to: CGFloat, weight: Int) {
            guard weight != Weight.none else { return }
            if weight == Weight.double {
                context.fill(CGRect(x: from, y: cy - thin, width: to - from, height: thin))
                context.fill(CGRect(x: from, y: cy + thin, width: to - from, height: thin))
            } else {
                let t = size(weight)
                context.fill(CGRect(x: from, y: cy - ((t - thin) / 2).rounded(.down), width: to - from, height: t))
            }
        }

        // Each arm runs past the centre by the junction's own width, so corners close.
        let reach = thick + thin
        vertical(from: 0, to: min(h, cy + reach), weight: up)
        vertical(from: max(0, cy - thin), to: h, weight: down)
        horizontal(from: 0, to: min(w, cx + reach), weight: left)
        horizontal(from: max(0, cx - thin), to: w, weight: right)
    }

    private static func dashes(_ codepoint: UInt32, _ context: CGContext, _ w: CGFloat, _ h: CGFloat,
                               _ thin: CGFloat, _ thick: CGFloat) {
        let count: Int
        let vertical: Bool
        let heavy: Bool
        switch codepoint {
        case 0x2504: (count, vertical, heavy) = (3, false, false)
        case 0x2505: (count, vertical, heavy) = (3, false, true)
        case 0x2506: (count, vertical, heavy) = (3, true, false)
        case 0x2507: (count, vertical, heavy) = (3, true, true)
        case 0x2508: (count, vertical, heavy) = (4, false, false)
        case 0x2509: (count, vertical, heavy) = (4, false, true)
        case 0x250A: (count, vertical, heavy) = (4, true, false)
        case 0x250B: (count, vertical, heavy) = (4, true, true)
        case 0x254C: (count, vertical, heavy) = (2, false, false)
        case 0x254D: (count, vertical, heavy) = (2, false, true)
        case 0x254E: (count, vertical, heavy) = (2, true, false)
        default: (count, vertical, heavy) = (2, true, true)
        }
        let t = heavy ? thick : thin
        let length = vertical ? h : w
        let step = length / CGFloat(count)
        let dash = (step * 0.7).rounded()
        for index in 0..<count {
            let start = (CGFloat(index) * step).rounded()
            if vertical {
                context.fill(CGRect(x: ((w - t) / 2).rounded(.down), y: start, width: t, height: dash))
            } else {
                context.fill(CGRect(x: start, y: ((h - t) / 2).rounded(.down), width: dash, height: t))
            }
        }
    }

    private static func arc(_ codepoint: UInt32, _ context: CGContext, _ w: CGFloat, _ h: CGFloat, _ thin: CGFloat) {
        let cx = ((w - thin) / 2).rounded(.down) + thin / 2
        let cy = ((h - thin) / 2).rounded(.down) + thin / 2
        let radius = min(cx, cy, w - cx, h - cy)
        let start: CGPoint
        let end: CGPoint
        switch codepoint {
        case 0x256D: (start, end) = (CGPoint(x: w, y: cy), CGPoint(x: cx, y: h))
        case 0x256E: (start, end) = (CGPoint(x: 0, y: cy), CGPoint(x: cx, y: h))
        case 0x256F: (start, end) = (CGPoint(x: 0, y: cy), CGPoint(x: cx, y: 0))
        default: (start, end) = (CGPoint(x: w, y: cy), CGPoint(x: cx, y: 0))
        }
        context.setLineWidth(thin)
        context.setLineCap(.butt)
        context.beginPath()
        context.move(to: start)
        context.addArc(tangent1End: CGPoint(x: cx, y: cy), tangent2End: end, radius: radius)
        context.addLine(to: end)
        context.strokePath()
    }

    private static func block(_ codepoint: UInt32, _ context: CGContext, _ w: CGFloat, _ h: CGFloat) {
        func fill(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
            let left = (x * w).rounded()
            let top = (y * h).rounded()
            context.fill(CGRect(x: left, y: top, width: ((x + width) * w).rounded() - left,
                                height: ((y + height) * h).rounded() - top))
        }
        func quadrants(_ upperLeft: Bool, _ upperRight: Bool, _ lowerLeft: Bool, _ lowerRight: Bool) {
            if upperLeft { fill(x: 0, y: 0, width: 0.5, height: 0.5) }
            if upperRight { fill(x: 0.5, y: 0, width: 0.5, height: 0.5) }
            if lowerLeft { fill(x: 0, y: 0.5, width: 0.5, height: 0.5) }
            if lowerRight { fill(x: 0.5, y: 0.5, width: 0.5, height: 0.5) }
        }
        func shade(_ alpha: CGFloat) {
            context.setFillColor(gray: 1, alpha: alpha)
            fill(x: 0, y: 0, width: 1, height: 1)
            context.setFillColor(gray: 1, alpha: 1)
        }

        switch codepoint {
        case 0x2580: fill(x: 0, y: 0, width: 1, height: 0.5)
        case 0x2581...0x2588:
            let eighths = CGFloat(codepoint - 0x2580)
            fill(x: 0, y: 1 - eighths / 8, width: 1, height: eighths / 8)
        case 0x2589...0x258F:
            fill(x: 0, y: 0, width: CGFloat(0x2590 - codepoint) / 8, height: 1)
        case 0x2590: fill(x: 0.5, y: 0, width: 0.5, height: 1)
        case 0x2591: shade(0.25)
        case 0x2592: shade(0.5)
        case 0x2593: shade(0.75)
        case 0x2594: fill(x: 0, y: 0, width: 1, height: 0.125)
        case 0x2595: fill(x: 0.875, y: 0, width: 0.125, height: 1)
        case 0x2596: quadrants(false, false, true, false)
        case 0x2597: quadrants(false, false, false, true)
        case 0x2598: quadrants(true, false, false, false)
        case 0x2599: quadrants(true, false, true, true)
        case 0x259A: quadrants(true, false, false, true)
        case 0x259B: quadrants(true, true, true, false)
        case 0x259C: quadrants(true, true, false, true)
        case 0x259D: quadrants(false, true, false, false)
        case 0x259E: quadrants(false, true, true, false)
        default: quadrants(false, true, true, true)
        }
    }

    private static func braille(_ codepoint: UInt32, _ context: CGContext, _ w: CGFloat, _ h: CGFloat) {
        let bits = codepoint - 0x2800
        // Unicode numbers the dots down the left column, then the right, then
        // the extra bottom pair.
        let dots: [(column: CGFloat, row: CGFloat)] = [
            (0, 0), (0, 1), (0, 2), (1, 0), (1, 1), (1, 2), (0, 3), (1, 3),
        ]
        let radius = max(1, (min(w / 2, h / 4) * 0.28).rounded())
        for (index, dot) in dots.enumerated() where bits & (1 << UInt32(index)) != 0 {
            let x = (dot.column + 0.5) * w / 2
            let y = (dot.row + 0.5) * h / 4
            context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
        }
    }
}
