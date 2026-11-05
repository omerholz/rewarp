import CGhosttyVT
import Testing
@testable import RewarpCore

private func ghosttyWrite(_ terminal: VTTerminal, _ bytes: UnsafeBufferPointer<UInt8>) {
    ghostty_terminal_vt_write(terminal.handle, bytes.baseAddress, bytes.count)
}

private func layout(_ rows: [Int], header: Int = 30) -> BlockLayout {
    var layout = BlockLayout(cellHeight: 10, footerHeight: 4)
    layout.rebuild(rows.enumerated().map { .init(id: $0.offset, headerHeight: header, outputRows: $0.element) })
    return layout
}

@Suite("Block layout")
struct BlockLayoutTests {
    @Test("Blocks stack without gaps")
    func stacking() {
        let list = layout([2, 0, 5])
        #expect(list.entries.map(\.top) == [0, 54, 88])
        #expect(list.entries.map(\.height) == [54, 34, 84])
        #expect(list.contentHeight == 172)
    }

    @Test("Output starts below the header")
    func outputTop() {
        #expect(layout([2, 2]).entries[1].outputTop == 84)
    }

    @Test("Only the blocks in the window are visible")
    func visible() {
        let list = layout([2, 2, 2, 2])  // each 54 tall
        #expect(list.visibleRange(top: 0, height: 54) == 0..<1)
        #expect(list.visibleRange(top: 53, height: 2) == 0..<2)
        #expect(list.visibleRange(top: 54, height: 54) == 1..<2)
        #expect(list.visibleRange(top: 100, height: 1000) == 1..<4)
        #expect(list.visibleRange(top: 5000, height: 10) == 4..<4)
    }

    @Test("An empty list has nothing visible")
    func empty() {
        var list = BlockLayout(cellHeight: 10, footerHeight: 4)
        list.rebuild([])
        #expect(list.visibleRange(top: 0, height: 100) == 0..<0)
        #expect(list.contentHeight == 0)
    }

    @Test("Growing the last block changes nothing above it")
    func updateLast() {
        var list = layout([2, 2])
        let first = list.entries[0]
        list.updateLast(outputRows: 10)
        #expect(list.entries[0] == first)
        #expect(list.entries[1].height == 134)
        #expect(list.contentHeight == 188)
    }

    @Test("Finding the visible blocks stays fast with a very long list")
    func scale() {
        let list = layout(Array(repeating: 3, count: 100_000))
        let middle = list.contentHeight / 2
        #expect(list.visibleRange(top: middle, height: 600).count < 12)
    }
}

@Suite("Block scrolling")
struct BlockScrollTests {
    @Test("New output keeps the list at the bottom")
    func followsTail() {
        var scroll = BlockScroll()
        scroll.settle(content: 1000, viewport: 400)
        #expect(scroll.offset == 600)
        scroll.settle(content: 1500, viewport: 400)
        #expect(scroll.offset == 1100)
    }

    @Test("Scrolling up stops following, so reading isn't interrupted")
    func stopsFollowing() {
        var scroll = BlockScroll()
        scroll.settle(content: 1000, viewport: 400)
        scroll.scroll(by: -100, content: 1000, viewport: 400)
        #expect(!scroll.followsTail)
        scroll.settle(content: 5000, viewport: 400)
        #expect(scroll.offset == 500)
    }

    @Test("Scrolling back to the bottom resumes following")
    func resumesFollowing() {
        var scroll = BlockScroll()
        scroll.settle(content: 1000, viewport: 400)
        scroll.scroll(by: -100, content: 1000, viewport: 400)
        scroll.scroll(by: 100, content: 1000, viewport: 400)
        #expect(scroll.followsTail)
    }

    @Test("Scrolling stops at both ends")
    func clamps() {
        var scroll = BlockScroll()
        scroll.settle(content: 1000, viewport: 400)
        scroll.scroll(by: -5000, content: 1000, viewport: 400)
        #expect(scroll.offset == 0)
        scroll.scroll(by: 5000, content: 1000, viewport: 400)
        #expect(scroll.offset == 600)
    }

    @Test("Content shorter than the viewport doesn't scroll")
    func shortContent() {
        var scroll = BlockScroll()
        scroll.settle(content: 100, viewport: 400)
        #expect(scroll.offset == 0)
        scroll.scroll(by: 50, content: 100, viewport: 400)
        #expect(scroll.offset == 0)
    }

    @Test("Shrinking content pulls an old offset back into range")
    func shrinking() {
        var scroll = BlockScroll()
        scroll.settle(content: 1000, viewport: 400)
        scroll.scroll(by: -50, content: 1000, viewport: 400)
        scroll.settle(content: 500, viewport: 400)
        #expect(scroll.offset == 100)
    }
}

@Suite("Terminal content height")
struct ContentRowsTests {
    @Test("Short output is as tall as its text, not as tall as the terminal")
    func short() {
        let terminal = VTTerminal(cols: 20, rows: 10)
        Array("one\r\ntwo\r\n".utf8).withUnsafeBufferPointer { ghosttyWrite(terminal, $0) }
        #expect(terminal.contentRows() == 2)
    }

    @Test("Scrollback counts")
    func scrollback() {
        let terminal = VTTerminal(cols: 20, rows: 4)
        let text = (1...10).map { "row \($0)\r\n" }.joined()
        Array(text.utf8).withUnsafeBufferPointer { ghosttyWrite(terminal, $0) }
        #expect(terminal.contentRows() == 10)
    }

    @Test("No output means no rows")
    func empty() {
        #expect(VTTerminal(cols: 20, rows: 10).contentRows() == 0)
    }

    @Test("Text drawn below the cursor still counts")
    func belowCursor() {
        let terminal = VTTerminal(cols: 20, rows: 10)
        Array("\u{1b}[8;1Hlow\u{1b}[1;1H".utf8).withUnsafeBufferPointer { ghosttyWrite(terminal, $0) }
        #expect(terminal.contentRows() == 8)
    }
}
