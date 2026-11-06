import AppKit
import CGhosttyVT
import RewarpCore

enum BlockControl: Equatable {
    case menu
    case bookmark
}

extension TerminalView {
    /// A mouse press being tracked, to tell a click from a drag.
    struct Press {
        var block: Block?
        var startsOutputSelection: Bool
        var didDrag = false
        var location: CGPoint
    }

    enum HitRegion {
        case header
        case output(column: Int, row: Int)
        case footer
    }

    private func pixelPoint(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x * scale, y: point.y * scale)
    }

    private var left: Int { Int(Self.paddingX * scale) }
    private var top: Int { Int(Self.paddingY * scale) }

    /// The block under a point, and which part of it. The point is in pixels.
    func hit(_ point: CGPoint) -> (item: PlacedBlock, region: HitRegion)? {
        guard Int(point.y) < listHeight else { return nil }
        let y = Int(point.y) - listOrigin
        guard let item = placed.first(where: { y >= $0.entry.top && y < $0.entry.bottom }) else { return nil }
        let entry = item.entry
        if y < entry.outputTop { return (item, .header) }
        let outputBottom = entry.outputTop + entry.outputRows * glyphs.cellHeight
        if y >= outputBottom { return (item, .footer) }
        return (item, .output(column: column(at: point), row: (y - entry.outputTop) / glyphs.cellHeight))
    }

    /// Screen coordinates cover scrollback too, so a block's row number works
    /// wherever that block's viewport happens to be.
    private func gridRef(_ tag: GhosttyPointTag, terminal: VTTerminal, column: Int, row: Int) -> GhosttyGridRef? {
        var ref = GhosttyGridRef()
        ref.size = MemoryLayout<GhosttyGridRef>.size
        var point = GhosttyPoint()
        point.tag = tag
        point.value.coordinate = GhosttyPointCoordinate(x: UInt16(column), y: UInt32(row))
        return ghostty_terminal_grid_ref(terminal.handle, point, &ref) == GHOSTTY_SUCCESS ? ref : nil
    }

    private func column(at point: CGPoint) -> Int {
        min(max(0, (Int(point.x) - left) / glyphs.cellWidth), gridColumns - 1)
    }

    // MARK: Text selection

    private func applyGesture(_ type: GhosttySelectionGestureEventType, event: NSEvent,
                              terminal: VTTerminal, ref: GhosttyGridRef?) {
        let point = pixelPoint(event)
        var gestureEvent: GhosttySelectionGestureEvent?
        guard ghostty_selection_gesture_event_new(nil, &gestureEvent, type) == GHOSTTY_SUCCESS,
              let gestureEvent else { return }
        defer { ghostty_selection_gesture_event_free(gestureEvent) }

        if var ref {
            _ = ghostty_selection_gesture_event_set(gestureEvent, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_REF, &ref)
        }
        if type != GHOSTTY_SELECTION_GESTURE_EVENT_TYPE_RELEASE {
            var position = GhosttySurfacePosition(x: Double(point.x) - Double(left), y: Double(point.y))
            _ = ghostty_selection_gesture_event_set(gestureEvent, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_POSITION, &position)
        }
        if type == GHOSTTY_SELECTION_GESTURE_EVENT_TYPE_PRESS {
            var time = UInt64(event.timestamp * 1_000_000_000)
            var interval = UInt64(NSEvent.doubleClickInterval * 1_000_000_000)
            _ = ghostty_selection_gesture_event_set(gestureEvent, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_TIME_NS, &time)
            _ = ghostty_selection_gesture_event_set(gestureEvent, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_REPEAT_INTERVAL_NS, &interval)
        }
        if type == GHOSTTY_SELECTION_GESTURE_EVENT_TYPE_DRAG {
            var geometry = GhosttySelectionGestureGeometry(
                columns: UInt32(gridColumns), cell_width: UInt32(glyphs.cellWidth), padding_left: 0,
                screen_height: UInt32(listHeight))
            _ = ghostty_selection_gesture_event_set(gestureEvent, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_GEOMETRY, &geometry)
            var rectangle = event.modifierFlags.contains(.command) && event.modifierFlags.contains(.option)
            _ = ghostty_selection_gesture_event_set(gestureEvent, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_RECTANGLE, &rectangle)
        }

        var selection = GhosttySelection()
        selection.size = MemoryLayout<GhosttySelection>.size
        let result = ghostty_selection_gesture_event(gesture, terminal.handle, gestureEvent, &selection)
        if result == GHOSTTY_SUCCESS {
            _ = ghostty_terminal_set(terminal.handle, GHOSTTY_TERMINAL_OPT_SELECTION, &selection)
        } else if type == GHOSTTY_SELECTION_GESTURE_EVENT_TYPE_PRESS {
            terminal.clearSelection()
        }
    }

    /// Takes a terminal from inside `withState`, which is what guards the gesture.
    private func beginGesture(on terminal: VTTerminal) {
        if let previous = gestureTerminal, previous !== terminal {
            ghostty_selection_gesture_reset(gesture, previous.handle)
        }
        gestureTerminal = terminal
    }

    private func clearTextSelection() {
        session.withState { _ in gestureTerminal?.clearSelection() }
        if let block = textSelectionBlock { surfaces[block.id]?.needsCapture = true }
        textSelectionBlock = nil
        session.requestFrame()
    }

    /// The text selected in a block or full-screen program, if any.
    var selectedText: String? {
        let text = session.withState { _ in gestureTerminal?.selectedText() }
        return text?.isEmpty == false ? text : nil
    }

    // MARK: Block selection

    func select(block id: Int, extending: Bool = false, toggling: Bool = false) {
        if toggling {
            if selectedBlocks.remove(id) == nil {
                selectedBlocks.insert(id)
                activeBlock = id
            } else if activeBlock == id {
                activeBlock = selectedBlocks.first
            }
        } else if extending, let active = activeBlock,
                  let from = layout.entries.firstIndex(where: { $0.id == active }),
                  let to = layout.entries.firstIndex(where: { $0.id == id }) {
            selectedBlocks = Set(layout.entries[min(from, to)...max(from, to)].map(\.id))
        } else {
            selectedBlocks = [id]
            activeBlock = id
        }
        session.requestFrame()
    }

    func clearBlockSelection() {
        guard !selectedBlocks.isEmpty else { return }
        selectedBlocks.removeAll()
        activeBlock = nil
        session.requestFrame()
    }

    // MARK: Events

    private func reportsMouse(_ state: PaneSession.State) -> Bool {
        state.inputTerminal.value(GHOSTTY_TERMINAL_DATA_MOUSE_TRACKING, default: false)
    }

    /// Where a point falls on a program's grid. A program on the primary screen
    /// draws inside its block, so that's what it measures from.
    private func programY(_ point: CGPoint, _ state: PaneSession.State) -> Int {
        let terminal = state.inputTerminal
        guard state.hasIntegration, !terminal.isAlternateScreen,
              let item = placed.last(where: \.isRunning) else { return Int(point.y) - top }
        let gridTop = item.entry.outputTop + terminal.scrollbackRows * glyphs.cellHeight
        return Int(point.y) - (listOrigin + gridTop)
    }

    private func report(_ event: NSEvent, action: GhosttyMouseAction, button: GhosttyMouseButton?) -> Bool {
        session.withState { state in
            guard state.routesInputToProgram else { return false }
            // Shift always reaches the terminal's own selection, as in Warp.
            guard reportsMouse(state), !event.modifierFlags.contains(.shift) else { return false }
            var size = GhosttyMouseEncoderSize()
            size.size = MemoryLayout<GhosttyMouseEncoderSize>.size
            size.screen_width = UInt32(gridColumns * glyphs.cellWidth)
            size.screen_height = UInt32(gridRows * glyphs.cellHeight)
            size.cell_width = UInt32(glyphs.cellWidth)
            size.cell_height = UInt32(glyphs.cellHeight)
            mouseEncoder.sync(from: state.inputTerminal.handle, size: size, anyButtonPressed: !pressedButtons.isEmpty)
            let point = pixelPoint(event)
            let bytes = mouseEncoder.encode(action: action, button: button, mods: ghosttyMods(event.modifierFlags),
                                            x: Float(Int(point.x) - left), y: Float(programY(point, state)))
            session.sendToProcess(bytes)
            return true
        }
    }

    private func fullScreenCell(_ point: CGPoint) -> (column: Int, row: Int) {
        (column(at: point), min(max(0, (Int(point.y) - top) / glyphs.cellHeight), gridRows - 1))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        pressedButtons.insert(0)
        if report(event, action: GHOSTTY_MOUSE_ACTION_PRESS, button: GHOSTTY_MOUSE_BUTTON_LEFT) { return }

        let point = pixelPoint(event)
        if handleChromeClick(at: point) { return }

        switch display {
        case .plain, .fullScreen:
            session.withState { state in
                let terminal = state.inputTerminal
                beginGesture(on: terminal)
                let cell = fullScreenCell(point)
                let ref = gridRef(GHOSTTY_POINT_TAG_VIEWPORT, terminal: terminal, column: cell.column, row: cell.row)
                applyGesture(GHOSTTY_SELECTION_GESTURE_EVENT_TYPE_PRESS, event: event, terminal: terminal, ref: ref)
            }
            press = Press(block: nil, startsOutputSelection: true, location: point)
            session.requestFrame()

        case .list:
            let found = hit(point)
            var startsSelection = false
            let modified = event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.command)
            let rectangular = event.modifierFlags.contains(.command) && event.modifierFlags.contains(.option)

            clearTextSelection()
            if let found, case .output(let column, let row) = found.region, !modified || rectangular {
                session.withState { state in
                    let terminal = state.displayTerminal(of: found.item.block)
                    beginGesture(on: terminal)
                    let ref = gridRef(GHOSTTY_POINT_TAG_SCREEN, terminal: terminal, column: column, row: row)
                    applyGesture(GHOSTTY_SELECTION_GESTURE_EVENT_TYPE_PRESS, event: event, terminal: terminal, ref: ref)
                }
                textSelectionBlock = found.item.block
                surfaces[found.item.block.id]?.needsCapture = true
                startsSelection = true
            }
            press = Press(block: found?.item.block, startsOutputSelection: startsSelection, location: point)
            session.requestFrame()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if report(event, action: GHOSTTY_MOUSE_ACTION_MOTION, button: GHOSTTY_MOUSE_BUTTON_LEFT) { return }
        guard var current = press, current.startsOutputSelection else { return }
        let point = pixelPoint(event)
        if hypot(point.x - current.location.x, point.y - current.location.y) > 2 { current.didDrag = true }
        press = current

        session.withState { _ in
            guard let terminal = gestureTerminal else { return }
            if let block = current.block {
                guard let found = placed.first(where: { $0.block === block }) else { return }
                // Selection stays inside the block it started in. Past either end,
                // the row clamps to the block's first or last row.
                let y = Int(point.y) - listOrigin - found.entry.outputTop
                let row = min(max(0, y / glyphs.cellHeight), max(0, found.entry.outputRows - 1))
                let ref = gridRef(GHOSTTY_POINT_TAG_SCREEN, terminal: terminal, column: column(at: point), row: row)
                applyGesture(GHOSTTY_SELECTION_GESTURE_EVENT_TYPE_DRAG, event: event, terminal: terminal, ref: ref)
                surfaces[block.id]?.needsCapture = true
            } else {
                let cell = fullScreenCell(point)
                let ref = gridRef(GHOSTTY_POINT_TAG_VIEWPORT, terminal: terminal, column: cell.column, row: cell.row)
                applyGesture(GHOSTTY_SELECTION_GESTURE_EVENT_TYPE_DRAG, event: event, terminal: terminal, ref: ref)
            }
        }
        session.requestFrame()
    }

    override func mouseUp(with event: NSEvent) {
        pressedButtons.remove(0)
        if report(event, action: GHOSTTY_MOUSE_ACTION_RELEASE, button: GHOSTTY_MOUSE_BUTTON_LEFT) { return }
        defer { press = nil }
        guard let finished = press else { return }

        session.withState { _ in
            if let terminal = gestureTerminal {
                applyGesture(GHOSTTY_SELECTION_GESTURE_EVENT_TYPE_RELEASE, event: event, terminal: terminal, ref: nil)
            }
        }

        if finished.didDrag || (event.clickCount >= 2 && finished.startsOutputSelection) {
            copySelectionIfEnabled()
            return
        }

        // A click with no drag acts on the block rather than on text.
        clearTextSelection()
        guard let block = finished.block else {
            clearBlockSelection()
            return
        }
        if session.withState({ $0.isRunning(block) }) {
            onFocusInput?()
            return
        }
        select(block: block.id,
               extending: event.modifierFlags.contains(.shift),
               toggling: event.modifierFlags.contains(.command))
    }

    /// Copy on select is on by default in Warp.
    private func copySelectionIfEnabled() {
        guard let text = selectedText else { return }
        Clipboard.write(text)
    }

    override func mouseMoved(with event: NSEvent) {
        if report(event, action: GHOSTTY_MOUSE_ACTION_MOTION, button: nil) { return }
        let point = pixelPoint(event)
        let found = hit(point)?.item.block.id
        let control = found == nil ? nil : control(at: point)
        if found != hoveredBlock || control != hoveredControl {
            hoveredBlock = found
            hoveredControl = control
            session.requestFrame()
        }
        isPointerInside = true
    }

    override func mouseExited(with event: NSEvent) {
        isPointerInside = false
        if hoveredBlock != nil {
            hoveredBlock = nil
            hoveredControl = nil
            session.requestFrame()
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if case .list = display, !programWantsScrolling {
            let pixels = event.hasPreciseScrollingDeltas
                ? event.scrollingDeltaY * scale
                : event.scrollingDeltaY * 3 * CGFloat(glyphs.cellHeight)
            scrollList(by: -Int(pixels.rounded()))
            return
        }

        let rowsPerPoint = event.hasPreciseScrollingDeltas ? scale / CGFloat(glyphs.cellHeight) : 3
        scrollRemainder += event.scrollingDeltaY * rowsPerPoint
        let rows = Int(scrollRemainder.rounded(.towardZero))
        guard rows != 0 else { return }
        scrollRemainder -= CGFloat(rows)

        let (captured, sendsArrows, applicationCursor) = session.withState { state in
            let terminal = state.inputTerminal
            let captured = reportsMouse(state)
            let alternate = terminal.isAlternateScreen
            if !captured && !alternate { terminal.scroll(byRows: -rows) }
            return (captured, alternate && terminal.isModeSet(1007), terminal.isModeSet(1))
        }

        if captured {
            let button = rows > 0 ? GHOSTTY_MOUSE_BUTTON_FOUR : GHOSTTY_MOUSE_BUTTON_FIVE
            for _ in 0..<abs(rows) { _ = report(event, action: GHOSTTY_MOUSE_ACTION_PRESS, button: button) }
        } else if sendsArrows {
            // Pagers and editors without mouse support still scroll with the wheel.
            let arrow = "\u{1b}\(applicationCursor ? "O" : "[")\(rows > 0 ? "A" : "B")"
            session.sendToProcess(Array(String(repeating: arrow, count: abs(rows)).utf8))
        }
        session.requestFrame()
    }

    private var programWantsScrolling: Bool {
        session.withState { $0.routesInputToProgram && reportsMouse($0) }
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if report(event, action: GHOSTTY_MOUSE_ACTION_PRESS, button: GHOSTTY_MOUSE_BUTTON_RIGHT) { return }
        showContextMenu(for: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        _ = report(event, action: GHOSTTY_MOUSE_ACTION_RELEASE, button: GHOSTTY_MOUSE_BUTTON_RIGHT)
    }

    /// Middle click pastes.
    override func otherMouseDown(with event: NSEvent) {
        if report(event, action: GHOSTTY_MOUSE_ACTION_PRESS, button: GHOSTTY_MOUSE_BUTTON_MIDDLE) { return }
        if event.buttonNumber == 2 { paste(nil) }
    }

    override func otherMouseUp(with event: NSEvent) {
        _ = report(event, action: GHOSTTY_MOUSE_ACTION_RELEASE, button: GHOSTTY_MOUSE_BUTTON_MIDDLE)
    }
}
