import CGhosttyVT
import Foundation

/// How wide a character is on the grid, by the terminal's own table.
public enum CellWidth {
    public static func of(_ scalar: Unicode.Scalar) -> Int {
        Int(ghostty_unicode_codepoint_width(scalar.value))
    }
}

public struct TextQuery: Equatable, Sendable {
    public var text: String
    public var isRegex: Bool
    public var isCaseSensitive: Bool

    public init(text: String, isRegex: Bool = false, isCaseSensitive: Bool = false) {
        self.text = text
        self.isRegex = isRegex
        self.isCaseSensitive = isCaseSensitive
    }

    /// Nil when the query is empty or isn't a valid regular expression.
    func compiled() -> NSRegularExpression? {
        guard !text.isEmpty else { return nil }
        var options: NSRegularExpression.Options = [.anchorsMatchLines]
        if !isCaseSensitive { options.insert(.caseInsensitive) }
        let pattern = isRegex ? text : NSRegularExpression.escapedPattern(for: text)
        return try? NSRegularExpression(pattern: pattern, options: options)
    }
}

/// One match, in the coordinates of a block's output grid.
public struct FindHit: Equatable, Sendable {
    public var blockID: Int
    public var row: Int
    public var startColumn: Int
    /// One past the last cell.
    public var endColumn: Int
}

/// Finds text across blocks. Matches are listed from the newest row upward, which
/// is the order Warp walks through them.
public struct BlockFinder {
    public private(set) var hits: [FindHit] = []
    public private(set) var currentIndex: Int?
    private var hitsByBlock: [Int: [FindHit]] = [:]

    public init() {}

    public var current: FindHit? { currentIndex.map { hits[$0] } }

    /// One block's matches on the given rows. Drawing calls this every frame, so
    /// the cost has to follow what's on screen and not the number of matches.
    public func hits(inBlock id: Int, rows: Range<Int>) -> ArraySlice<FindHit> {
        guard let hits = hitsByBlock[id] else { return [] }
        // Rows descend within a block, so find where each end of the range falls.
        func firstIndex(belowRow row: Int) -> Int {
            var low = 0
            var high = hits.count
            while low < high {
                let middle = (low + high) / 2
                if hits[middle].row < row {
                    high = middle
                } else {
                    low = middle + 1
                }
            }
            return low
        }
        return hits[firstIndex(belowRow: rows.upperBound)..<firstIndex(belowRow: rows.lowerBound)]
    }

    /// "3/12", or "0/0" when nothing matches.
    public var label: String {
        guard let currentIndex else { return "0/0" }
        return "\(currentIndex + 1)/\(hits.count)"
    }

    /// `sources` runs oldest to newest, as the block list does.
    public mutating func search(_ query: TextQuery, in sources: [(blockID: Int, rows: [String])]) {
        let previous = current
        hits.removeAll(keepingCapacity: true)
        hitsByBlock.removeAll(keepingCapacity: true)
        currentIndex = nil
        guard let expression = query.compiled() else { return }

        for source in sources.reversed() {
            for row in source.rows.indices.reversed() {
                let line = source.rows[row]
                let range = NSRange(location: 0, length: line.utf16.count)
                let matches = expression.matches(in: line, range: range)
                for match in matches.reversed() where match.range.length > 0 {
                    let columns = Self.cells(of: match.range, in: line)
                    hits.append(FindHit(blockID: source.blockID, row: row,
                                        startColumn: columns.lowerBound, endColumn: columns.upperBound))
                }
            }
        }
        guard !hits.isEmpty else { return }
        hitsByBlock = Dictionary(grouping: hits, by: \.blockID)
        // New output arriving must not move the match the user is on.
        currentIndex = previous.flatMap { hits.firstIndex(of: $0) } ?? 0
    }

    public mutating func clear() {
        hits.removeAll()
        hitsByBlock.removeAll()
        currentIndex = nil
    }

    /// Moves toward older output.
    public mutating func next() {
        guard let index = currentIndex else { return }
        currentIndex = (index + 1) % hits.count
    }

    /// Moves toward newer output.
    public mutating func previous() {
        guard let index = currentIndex else { return }
        currentIndex = (index + hits.count - 1) % hits.count
    }

    /// Maps a UTF-16 range in a row's text to the cells it covers.
    static func cells(of range: NSRange, in line: String) -> Range<Int> {
        var utf16 = 0
        var column = 0
        var start = 0
        var end = 0
        for scalar in line.unicodeScalars {
            if utf16 == range.location { start = column }
            let width = CellWidth.of(scalar)
            utf16 += scalar.utf16.count
            column += width
            if utf16 == NSMaxRange(range) {
                end = column
                break
            }
        }
        return start..<max(end, start + 1)
    }
}

public struct BlockFilterOptions: Equatable, Sendable {
    public var query: TextQuery
    public var contextLines: Int
    public var isInverted: Bool

    public init(query: TextQuery, contextLines: Int = 0, isInverted: Bool = false) {
        self.query = query
        self.contextLines = contextLines
        self.isInverted = isInverted
    }

    /// The rows to keep, in order. An unusable query keeps everything, so a half
    /// typed regular expression doesn't blank the block.
    public func keptRows(in rows: [String]) -> [Int] {
        guard let expression = query.compiled() else { return Array(rows.indices) }
        let matched = rows.indices.filter { index in
            let line = rows[index]
            let found = expression.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)) != nil
            return found != isInverted
        }
        guard contextLines > 0 else { return matched }
        var kept = Set<Int>()
        for index in matched {
            for neighbour in (index - contextLines)...(index + contextLines) where rows.indices.contains(neighbour) {
                kept.insert(neighbour)
            }
        }
        return kept.sorted()
    }
}
