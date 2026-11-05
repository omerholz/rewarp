import AppKit
import CGhosttyVT
import RewarpCore

/// Block actions, the context menu, and the chrome that floats over the list.
extension TerminalView {
    /// The blocks an action applies to: the selection in list order, or else the
    /// most recent block.
    var targetBlocks: [Block] {
        let blocks = allBlocks
        if !selectedBlocks.isEmpty { return blocks.filter { selectedBlocks.contains($0.id) } }
        return blocks.last.map { [$0] } ?? []
    }

    private var allBlocks: [Block] {
        session.withState { $0.blocks }
    }

    func scrollList(by delta: Int) {
        scroll.scroll(by: delta, content: layout.contentHeight, viewport: listHeight)
        session.requestFrame()
    }

    func scrollList(to offset: Int) {
        scroll.scroll(to: offset, content: layout.contentHeight, viewport: listHeight)
        session.requestFrame()
    }

    private func selectAndReveal(_ id: Int) {
        select(block: id)
        reveal(block: id)
    }

    private func writeToPasteboard(_ text: String) {
        guard !text.isEmpty else { return }
        Clipboard.write(text)
    }

    private func joined(_ transform: (PaneSession.State, Block) -> String) -> String {
        let targets = targetBlocks
        return session.withState { state in
            targets.map { transform(state, $0) }.joined(separator: "\n")
        }
    }

    @objc func copy(_ sender: Any?) {
        if let text = selectedText {
            writeToPasteboard(text)
        } else if !selectedBlocks.isEmpty {
            copyBlockOutput(sender)
        }
    }

    @objc func paste(_ sender: Any?) {
        guard let text = Clipboard.read() else { return }
        if keysGoToProgram {
            session.paste(text)
        } else {
            onFocusInput?()
            onInsertIntoInput?(text)
        }
    }

    @objc override func selectAll(_ sender: Any?) {
        selectedBlocks = Set(layout.entries.map(\.id))
        if activeBlock == nil { activeBlock = layout.entries.last?.id }
        session.requestFrame()
    }

    @objc func copyBlockCommand(_ sender: Any?) { writeToPasteboard(joined { $1.command }) }
    @objc func copyBlockOutput(_ sender: Any?) { writeToPasteboard(joined { $0.outputText(of: $1) }) }
    @objc func copyBlockBoth(_ sender: Any?) {
        writeToPasteboard(joined { "\($1.command)\n\($0.outputText(of: $1))" })
    }
    @objc func copyBlockDirectory(_ sender: Any?) { writeToPasteboard(joined { $1.workingDirectory }) }
    @objc func copyBlockBranch(_ sender: Any?) { writeToPasteboard(joined { $1.gitBranch ?? "" }) }

    @objc func insertSelectionIntoInput(_ sender: Any?) {
        guard let text = selectedText else { return }
        onFocusInput?()
        onInsertIntoInput?(text)
    }

    @objc func toggleBookmark(_ sender: Any?) {
        let targets = targetBlocks
        let value = !targets.allSatisfy(\.isBookmarked)
        for block in targets { block.isBookmarked = value }
        session.requestFrame()
    }

    @objc func reinputBlocks(_ sender: Any?) {
        onReinput?(joined { $1.command })
    }

    @objc func reinputBlocksAsRoot(_ sender: Any?) {
        onReinput?(joined { "sudo \($1.command)" })
    }

    @objc func clearBlocks(_ sender: Any?) {
        selectedBlocks.removeAll()
        activeBlock = nil
        // These would otherwise keep a cleared block's terminal alive.
        session.withState { _ in
            if let terminal = gestureTerminal { ghostty_selection_gesture_reset(gesture, terminal.handle) }
        }
        gestureTerminal = nil
        textSelectionBlock = nil
        session.removeAllBlocks()
        scroll.scrollToBottom(content: 0, viewport: listHeight)
    }

    @objc func splitLeftOrRight(_ sender: Any?) { onSplit?(.horizontal) }
    @objc func splitUpOrDown(_ sender: Any?) { onSplit?(.vertical) }
    @objc func toggleMaximize(_ sender: Any?) { onToggleZoom?() }
    @objc func closePaneFromMenu(_ sender: Any?) { onClose?() }

    // MARK: Moving the selection

    private func index(of id: Int) -> Int? {
        layout.entries.firstIndex { $0.id == id }
    }

    /// Scrolls just far enough to show the block, top first when it's too tall.
    func reveal(block id: Int) {
        guard let index = index(of: id) else { return }
        let entry = layout.entries[index]
        let viewport = listHeight
        if entry.top < scroll.offset || entry.height > viewport {
            scrollList(to: entry.top)
        } else if entry.bottom > scroll.offset + viewport {
            scrollList(to: entry.bottom - viewport)
        }
        session.requestFrame()
    }

    func selectAdjacentBlock(up: Bool) {
        guard !layout.entries.isEmpty else { return }
        window?.makeFirstResponder(self)
        guard let active = activeBlock, let current = index(of: active) else {
            if let last = layout.entries.last { selectAndReveal(last.id) }
            return
        }
        let next = current + (up ? -1 : 1)
        if next >= layout.entries.count {
            // Past the newest block, focus goes back to the input.
            clearBlockSelection()
            scrollList(to: layout.contentHeight)
            onFocusInput?()
            return
        }
        guard next >= 0 else { return }
        selectAndReveal(layout.entries[next].id)
    }

    func extendBlockSelection(up: Bool) {
        guard activeBlock != nil else {
            selectAdjacentBlock(up: up)
            return
        }
        let selected = selectedBlocks.compactMap(index(of:))
        guard let low = selected.min(), let high = selected.max() else { return }
        // Grow on the side the key points to, keeping the active block in place.
        let target = up ? low - 1 : high + 1
        guard layout.entries.indices.contains(target) else { return }
        selectedBlocks.insert(layout.entries[target].id)
        reveal(block: layout.entries[target].id)
        session.requestFrame()
    }

    func scrollToEdge(ofSelectedBlock top: Bool) {
        guard let id = activeBlock ?? layout.entries.last?.id, let index = index(of: id) else { return }
        let entry = layout.entries[index]
        let target = top ? entry.top : entry.bottom - listHeight
        scrollList(to: target)
    }

    func jumpToBookmark(up: Bool) {
        let blocks = allBlocks
        let anchor = activeBlock.flatMap(index(of:)) ?? blocks.count
        let indices = up ? Array((0..<anchor).reversed()) : Array((anchor + 1)..<max(anchor + 1, blocks.count))
        guard let found = indices.first(where: { blocks[$0].isBookmarked }) else { return }
        window?.makeFirstResponder(self)
        selectAndReveal(blocks[found].id)
    }

    /// A block's row count or contents changed from outside the terminal.
    func blockDisplayChanged(_ block: Block) {
        presentations[block.id] = nil
        surfaces[block.id]?.needsCapture = true
        layout = BlockLayout(cellHeight: layout.cellHeight, footerHeight: layout.footerHeight)
        session.requestFrame()
    }

    // MARK: Find

    /// Searches every block, or the selected one when find started there.
    func runFind(_ query: TextQuery?) {
        findQuery = query
        guard let query else {
            finder.clear()
            session.requestFrame()
            return
        }
        let blocks = allBlocks.filter { findScope == nil || $0.id == findScope }
        let sources = session.withState { state in
            blocks.map { (blockID: $0.id, rows: state.displayTerminal(of: $0).rowTexts()) }
        }
        finder.search(query, in: sources)
        revealCurrentMatch()
    }

    func moveFind(next: Bool) {
        if next { finder.next() } else { finder.previous() }
        revealCurrentMatch()
    }

    private func revealCurrentMatch() {
        session.requestFrame()
        guard let hit = finder.current, let index = index(of: hit.blockID) else { return }
        let entry = layout.entries[index]
        let y = entry.outputTop + hit.row * glyphs.cellHeight
        // A match that's already showing stays put, so the view doesn't jump.
        if y >= scroll.offset, y + glyphs.cellHeight <= scroll.offset + listHeight { return }
        scrollList(to: y - listHeight / 3)
    }

    func emitFindHighlights(for item: PlacedBlock, left: Int, into frame: Frame) {
        let top = listOrigin + item.entry.outputTop
        let current = finder.current
        let cellWidth = glyphs.cellWidth
        let cellHeight = glyphs.cellHeight
        let visibleRows = item.firstRow..<(item.firstRow + gridRows + 2)
        for hit in finder.hits(inBlock: item.block.id, rows: visibleRows) {
            let color = hit == current ? packed(RGB(0xFF, 0x9F, 0x1C), alpha: 200) : packed(RGB(0xE8, 0xC4, 0x68), alpha: 110)
            frame.background.append(rect(left + hit.startColumn * cellWidth, top + hit.row * cellHeight,
                                         (hit.endColumn - hit.startColumn) * cellWidth, cellHeight, color))
        }
    }

    // MARK: Hover toolbelt

    private var buttonSize: Int { Int(24 * scale) }

    private func toolbeltOrigin(for item: PlacedBlock, width: Int) -> (x: Int, y: Int) {
        let y = max(listOrigin + item.entry.top + Int(5 * scale), Int(5 * scale))
        return (width - buttonSize * 2 - Int(10 * scale), y)
    }

    func control(at point: CGPoint) -> BlockControl? {
        guard let id = hoveredBlock ?? hit(point)?.item.block.id,
              let item = placed.first(where: { $0.block.id == id }) else { return nil }
        let width = Int(bounds.width * scale)
        let origin = toolbeltOrigin(for: item, width: width)
        let x = Int(point.x)
        let y = Int(point.y)
        guard y >= origin.y, y < origin.y + buttonSize else { return nil }
        if x >= origin.x, x < origin.x + buttonSize { return .bookmark }
        if x >= origin.x + buttonSize, x < origin.x + buttonSize * 2 { return .menu }
        return nil
    }

    func emitToolbelt(into frame: Frame, width: Int) {
        let chromeGlyphs = fonts.chrome
        let background = packed(theme.background.mixed(with: theme.foreground, 0.1))
        let hover = packed(theme.background.mixed(with: theme.foreground, 0.2))
        let icon = packed(theme.foreground.mixed(with: theme.background, 0.25))
        let accent = packed(theme.accent)

        func drawIcon(_ codepoint: UInt32, x: Int, y: Int, color: UInt32) {
            let glyph = chromeGlyphs.glyph(codepoint: codepoint, style: 0)
            guard !glyph.isEmpty else { return }
            let left = x + (buttonSize - Int(glyph.width)) / 2
            let top = y + (buttonSize - Int(glyph.height)) / 2
            frame.overlayChromeText.append(Instance(
                x: Int16(left), y: Int16(top), width: glyph.width, height: glyph.height,
                u: glyph.u, v: glyph.v, color: color))
        }

        for item in placed {
            let isHovered = item.block.id == hoveredBlock
            guard isHovered || item.block.isBookmarked else { continue }
            let origin = toolbeltOrigin(for: item, width: width)
            if isHovered {
                frame.overlay.append(rect(origin.x, origin.y, buttonSize * 2, buttonSize, background))
                if hoveredControl == .bookmark {
                    frame.overlay.append(rect(origin.x, origin.y, buttonSize, buttonSize, hover))
                } else if hoveredControl == .menu {
                    frame.overlay.append(rect(origin.x + buttonSize, origin.y, buttonSize, buttonSize, hover))
                }
                drawIcon(0xF142, x: origin.x + buttonSize, y: origin.y, color: icon)
            }
            drawIcon(item.block.isBookmarked ? 0xF02E : 0xF097, x: origin.x, y: origin.y,
                     color: item.block.isBookmarked ? accent : icon)
        }
    }

    // MARK: Sticky header

    private var stickyHeight: Int {
        Int(6 * scale) * 2 + fonts.chrome.cellHeight + glyphs.cellHeight
    }

    /// The block whose header has scrolled away while its output is still showing.
    private var stickyBlock: PlacedBlock? {
        guard stickyHeaderEnabled else { return nil }
        guard let item = placed.first(where: { listOrigin + $0.entry.bottom > stickyHeight }) else { return nil }
        guard listOrigin + item.entry.top < 0, item.entry.outputRows > 0 else { return nil }
        // A long-running command filling the screen shouldn't lose a row to this
        // until the user actually scrolls up.
        if item.isRunning && scroll.followsTail { return nil }
        return item
    }

    func emitStickyHeader(into frame: Frame, width: Int) {
        guard let item = stickyBlock else { return }
        let height = stickyHeight
        frame.overlay.append(rect(0, 0, width, height, packed(theme.background.mixed(with: theme.foreground, 0.06))))
        frame.overlay.append(rect(0, height - 1, width, 1, packed(theme.background.mixed(with: theme.foreground, 0.16))))
        let left = Int(Self.paddingX * scale)
        var y = Int(6 * scale)
        fonts.chrome.emit(item.presentation.context, x: left, top: y,
                          color: packed(theme.foreground.mixed(with: theme.background, 0.42)),
                          limit: width - left, into: &frame.overlayChromeText)
        y += fonts.chrome.cellHeight
        if let line = item.presentation.commandLines.first {
            glyphs.emit(line, x: left, top: y, color: packed(theme.foreground), style: GlyphCache.Style.bold,
                        limit: width - left, into: &frame.overlayText)
        }
    }

    // MARK: Scrollbar

    private var scrollbarWidth: Int { Int(6 * scale) }

    private var scrollbarArea: (x: Int, height: Int) {
        (Int(bounds.width * scale) - scrollbarWidth - Int(2 * scale), listHeight)
    }

    func emitScrollbar(into frame: Frame, width: Int) {
        let content = layout.contentHeight
        let viewport = listHeight
        guard isPointerInside, content > viewport, viewport > 0 else { return }
        let area = scrollbarArea
        let thumbHeight = max(Int(24 * scale), viewport * viewport / content)
        let travel = viewport - thumbHeight
        let limit = BlockScroll.maximum(content: content, viewport: viewport)
        let thumbTop = limit > 0 ? scroll.offset * travel / limit : 0
        frame.overlay.append(rect(area.x, thumbTop, scrollbarWidth, thumbHeight,
                                  packed(theme.foreground, alpha: 70)))
        // Bookmarks mark their rough position in the history.
        let accent = packed(theme.accent)
        for top in bookmarkTops {
            let y = top * viewport / content
            frame.overlay.append(rect(area.x - Int(2 * scale), y, scrollbarWidth + Int(4 * scale), Int(3 * scale), accent))
        }
    }

    // MARK: Clicks on chrome

    /// Returns true when the click landed on chrome rather than on a block.
    func handleChromeClick(at point: CGPoint) -> Bool {
        guard case .list = display else { return false }
        if let item = stickyBlock, Int(point.y) < stickyHeight {
            scrollList(to: item.entry.top)
            return true
        }

        let content = layout.contentHeight
        let area = scrollbarArea
        if content > listHeight, Int(point.x) >= area.x - Int(4 * scale), Int(point.y) < area.height {
            let fraction = Double(point.y) / Double(max(area.height, 1))
            let target = Int(fraction * Double(BlockScroll.maximum(content: content, viewport: listHeight)))
            scrollList(to: target)
            return true
        }

        if let found = hit(point), let control = control(at: point) {
            switch control {
            case .bookmark:
                found.item.block.isBookmarked.toggle()
                session.requestFrame()
            case .menu:
                select(block: found.item.block.id)
                let origin = toolbeltOrigin(for: found.item, width: Int(bounds.width * scale))
                let location = NSPoint(x: CGFloat(origin.x + buttonSize) / scale, y: CGFloat(origin.y + buttonSize) / scale)
                makeBlockMenu().popUp(positioning: nil, at: location, in: self)
            }
            return true
        }
        return false
    }

    /// Each visible block's top and output top, in points relative to the view.
    func debugBlockFrames() -> [[String: Any]] {
        placed.map { item in
            [
                "id": item.block.id,
                "top": CGFloat(listOrigin + item.entry.top) / scale,
                "outputTop": CGFloat(listOrigin + item.entry.outputTop) / scale,
                "bottom": CGFloat(listOrigin + item.entry.bottom) / scale,
            ]
        }
    }

    // MARK: Context menu

    private func makeBlockMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        func item(_ title: String, _ action: Selector, enabled: Bool = true) {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self
            entry.isEnabled = enabled
            menu.addItem(entry)
        }

        if selectedText != nil {
            item("Copy", #selector(copy(_:)))
            item("Insert into Input", #selector(insertSelectionIntoInput(_:)))
            menu.addItem(.separator())
        }
        let hasBlocks = !layout.entries.isEmpty
        item("Copy Command", #selector(copyBlockCommand(_:)), enabled: hasBlocks)
        item("Copy Output", #selector(copyBlockOutput(_:)), enabled: hasBlocks)
        item("Copy Both", #selector(copyBlockBoth(_:)), enabled: hasBlocks)
        item("Copy Working Directory", #selector(copyBlockDirectory(_:)), enabled: hasBlocks)
        item("Copy Git Branch", #selector(copyBlockBranch(_:)), enabled: targetBlocks.contains { $0.gitBranch != nil })
        menu.addItem(.separator())
        item("Toggle Bookmark", #selector(toggleBookmark(_:)), enabled: hasBlocks)
        item("Reinput", #selector(reinputBlocks(_:)), enabled: hasBlocks)
        menu.addItem(.separator())
        item("Paste", #selector(paste(_:)))
        item("Clear", #selector(clearBlocks(_:)))
        menu.addItem(.separator())
        item("Split Pane Right", #selector(splitLeftOrRight(_:)))
        item("Split Pane Down", #selector(splitUpOrDown(_:)))
        item("Toggle Maximize Pane", #selector(toggleMaximize(_:)))
        item("Close Pane", #selector(closePaneFromMenu(_:)))
        return menu
    }

    private func selectBlockUnderPointer(_ point: NSPoint) {
        let pixels = CGPoint(x: point.x * scale, y: point.y * scale)
        if let found = hit(pixels), !selectedBlocks.contains(found.item.block.id) {
            select(block: found.item.block.id)
        }
    }

    /// What a right-click at a point would do, without the blocking menu loop.
    func prepareContextMenuForTesting(at point: NSPoint, in window: NSWindow?) {
        let flippedY = (window?.contentView?.bounds.height ?? 0) - point.y
        selectBlockUnderPointer(convert(NSPoint(x: point.x, y: flippedY), from: window?.contentView))
        lastMenuTitles = makeBlockMenu().items.filter { !$0.isSeparatorItem }.map(\.title)
    }

    func showContextMenu(for event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        selectBlockUnderPointer(point)
        makeBlockMenu().popUp(positioning: nil, at: point, in: self)
    }
}
