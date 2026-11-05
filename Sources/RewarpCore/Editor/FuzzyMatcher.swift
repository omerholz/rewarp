/// Scores a query against a candidate as an in-order subsequence, the way editors
/// do for file and symbol search. Matches at the start, after separators and in
/// consecutive runs count for more.
public enum FuzzyMatcher {
    public struct Match: Equatable, Sendable {
        public var score: Int
        /// Character offsets in the candidate, for highlighting.
        public var positions: [Int]
    }

    public static func match(_ query: String, in candidate: String) -> Match? {
        guard !query.isEmpty else { return Match(score: 0, positions: []) }
        guard mayMatch(query, in: candidate) else { return nil }
        let needle = Array(query.lowercased())
        let original = Array(candidate)
        let haystack = Array(candidate.lowercased())
        // Lowercasing can change length for a few scripts. Those simply don't
        // get position highlighting rather than wrong highlighting.
        let positionsAreReliable = haystack.count == original.count

        var positions: [Int] = []
        var score = 0
        var index = 0
        var previous = -2

        for character in needle {
            var found = -1
            while index < haystack.count {
                if haystack[index] == character {
                    found = index
                    break
                }
                index += 1
            }
            guard found >= 0 else { return nil }

            score += 1
            if found == 0 {
                score += 8
            } else if isSeparator(haystack[found - 1]) {
                score += 6
            }
            if found == previous + 1 { score += 5 }
            if positionsAreReliable, original[found] == query[query.index(query.startIndex, offsetBy: positions.count)] {
                score += 1
            }
            positions.append(found)
            previous = found
            index = found + 1
        }

        // A closer fit beats a longer candidate with the same matches.
        score -= min(haystack.count - needle.count, 20) / 4
        if String(haystack).hasPrefix(String(needle)) { score += 20 }
        return Match(score: score, positions: positionsAreReliable ? positions : [])
    }

    /// Rules out most candidates without allocating, which matters when every
    /// keystroke checks the whole history. Only ASCII queries are ruled out here,
    /// because case folding beyond that isn't byte by byte.
    private static func mayMatch(_ query: String, in candidate: String) -> Bool {
        var wanted = query.utf8.makeIterator()
        guard var next = wanted.next(), query.utf8.allSatisfy({ $0 < 0x80 }) else { return true }
        for byte in candidate.utf8 where lowercased(byte) == lowercased(next) {
            guard let following = wanted.next() else { return true }
            next = following
        }
        return false
    }

    private static func lowercased(_ byte: UInt8) -> UInt8 {
        (0x41...0x5A).contains(byte) ? byte + 0x20 : byte
    }

    private static func isSeparator(_ character: Character) -> Bool {
        character == "-" || character == "_" || character == "/" || character == "." || character == " "
    }
}
