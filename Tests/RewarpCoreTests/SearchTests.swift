import Testing
@testable import RewarpCore

private func find(_ text: String, regex: Bool = false, caseSensitive: Bool = false,
                  in sources: [(blockID: Int, rows: [String])]) -> BlockFinder {
    var finder = BlockFinder()
    finder.search(TextQuery(text: text, isRegex: regex, isCaseSensitive: caseSensitive), in: sources)
    return finder
}

@Suite("Find across blocks")
struct BlockFinderTests {
    @Test("Matches run from the newest output upward")
    func order() {
        let finder = find("x", in: [(1, ["x", "a x"]), (2, ["x"])])
        #expect(finder.hits.map(\.blockID) == [2, 1, 1])
        #expect(finder.hits.map(\.row) == [0, 1, 0])
    }

    @Test("The label counts matches, and reads 0/0 when there are none")
    func label() {
        #expect(find("a", in: [(1, ["a a"])]).label == "1/2")
        #expect(find("zzz", in: [(1, ["a"])]).label == "0/0")
    }

    @Test("Case is ignored unless asked for")
    func caseSensitivity() {
        #expect(find("error", in: [(1, ["ERROR"])]).hits.count == 1)
        #expect(find("error", caseSensitive: true, in: [(1, ["ERROR"])]).hits.isEmpty)
    }

    @Test("Literal search treats regex characters as text")
    func literal() {
        #expect(find("a.c", in: [(1, ["abc", "a.c"])]).hits.map(\.row) == [1])
    }

    @Test("Regular expressions work when asked for")
    func regex() {
        #expect(find("^a.c$", regex: true, in: [(1, ["abc", "xabc"])]).hits.map(\.row) == [0])
    }

    @Test("A broken regular expression finds nothing rather than failing")
    func brokenRegex() {
        #expect(find("(", regex: true, in: [(1, ["("])]).hits.isEmpty)
    }

    @Test("Wide characters are counted in cells")
    func wideCharacters() {
        let hit = find("x", in: [(1, ["日本x"])]).hits[0]
        #expect(hit.startColumn == 4)
        #expect(hit.endColumn == 5)
    }

    @Test("Wide text itself can be found")
    func findsWideText() {
        let hit = find("本", in: [(1, ["日本語"])]).hits[0]
        #expect(hit.startColumn == 2)
        #expect(hit.endColumn == 4)
    }

    @Test("Width follows the terminal's table, including where it surprises")
    func terminalWidths() {
        // U+2630 is ambiguous enough that a hand-written table gets it wrong.
        let hit = find("x", in: [(1, ["\u{2630}x"])]).hits[0]
        #expect(hit.startColumn == CellWidth.of("\u{2630}"))
        #expect(CellWidth.of("\u{200B}") == 0)
    }

    @Test("Matches can be read back for just the rows on screen")
    func visibleHits() {
        let rows = (0..<1000).map { $0 % 2 == 0 ? "x" : "y" }
        let finder = find("x", in: [(1, rows), (2, ["x"])])
        #expect(finder.hits(inBlock: 1, rows: 10..<14).map(\.row) == [12, 10])
        #expect(finder.hits(inBlock: 1, rows: 0..<1).map(\.row) == [0])
        #expect(finder.hits(inBlock: 1, rows: 2000..<2010).isEmpty)
        #expect(finder.hits(inBlock: 3, rows: 0..<10).isEmpty)
    }

    @Test("Moving through matches wraps both ways")
    func navigation() {
        var finder = find("x", in: [(1, ["x x x"])])
        finder.next()
        #expect(finder.label == "2/3")
        finder.previous()
        finder.previous()
        #expect(finder.label == "3/3")
        finder.next()
        #expect(finder.label == "1/3")
    }

    @Test("New output doesn't move the current match")
    func stableAcrossUpdates() {
        var finder = find("x", in: [(1, ["x", "x"])])
        finder.next()
        let current = finder.current
        finder.search(TextQuery(text: "x"), in: [(1, ["x", "x"]), (2, ["x"])])
        #expect(finder.current == current)
    }
}

@Suite("Block filter")
struct BlockFilterTests {
    private let rows = ["alpha", "beta", "gamma", "beta two", "delta"]

    @Test("Only matching rows stay")
    func basic() {
        #expect(BlockFilterOptions(query: TextQuery(text: "beta")).keptRows(in: rows) == [1, 3])
    }

    @Test("Context keeps neighbouring rows, without repeats")
    func context() {
        let options = BlockFilterOptions(query: TextQuery(text: "beta"), contextLines: 1)
        #expect(options.keptRows(in: rows) == [0, 1, 2, 3, 4])
    }

    @Test("Invert keeps what doesn't match")
    func invert() {
        let options = BlockFilterOptions(query: TextQuery(text: "beta"), isInverted: true)
        #expect(options.keptRows(in: rows) == [0, 2, 4])
    }

    @Test("Regular expressions support anchors")
    func anchors() {
        let options = BlockFilterOptions(query: TextQuery(text: "^beta$", isRegex: true))
        #expect(options.keptRows(in: rows) == [1])
    }

    @Test("An unusable query keeps every row")
    func unusable() {
        #expect(BlockFilterOptions(query: TextQuery(text: "")).keptRows(in: rows).count == 5)
        #expect(BlockFilterOptions(query: TextQuery(text: "(", isRegex: true)).keptRows(in: rows).count == 5)
    }

    @Test("Filtering doesn't touch the block, and keeps colours")
    func keepsOutput() throws {
        let session = PaneSession(cols: 40, rows: 10, cellWidth: 10, cellHeight: 20, theme: .dusk, workingDirectory: "/tmp")
        session.reportToken = "token"
        let text = "\u{1b}]7701;start=token;x\u{07}one\r\n\u{1b}[31mtwo\u{1b}[0m\r\nthree\r\n\u{1b}]7701;done=token;0\u{07}"
        Array(text.utf8).withUnsafeBytes { session.ingest($0) }
        let block = try #require(session.blocks.first)

        session.setFilter(BlockFilterOptions(query: TextQuery(text: "two")), on: block)
        #expect(block.displayTerminal.plainText() == "two")
        #expect(block.terminal.plainText().contains("three"))
        #expect(block.displayTerminal.styledRows().first?.contains("\u{1b}[") == true)

        session.setFilter(nil, on: block)
        #expect(block.displayTerminal === block.terminal)
    }
}
