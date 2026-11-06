import CGhosttyVT

/// Owns one libghostty-vt terminal. Terminals are not thread safe: every call
/// must happen under the owning session's lock.
public final class VTTerminal {
    public let handle: GhosttyTerminal

    public init(cols: Int, rows: Int, cellWidth: Int = 0, cellHeight: Int = 0) {
        var raw: GhosttyTerminal?
        let result = ghostty_terminal_new(nil, &raw, UInt16(clamping: max(cols, 1)), UInt16(clamping: max(rows, 1)))
        guard result == GHOSTTY_SUCCESS, let raw else {
            fatalError("ghostty_terminal_new failed: \(result)")
        }
        handle = raw
        if cellWidth > 0 {
            resize(cols: cols, rows: rows, cellWidth: cellWidth, cellHeight: cellHeight)
        }
    }

    deinit {
        ghostty_terminal_free(handle)
    }

    public func write(_ text: String) {
        var bytes = Array(text.utf8)
        bytes.withUnsafeMutableBufferPointer { ghostty_terminal_vt_write(handle, $0.baseAddress, $0.count) }
    }

    public func apply(theme: Theme) {
        var fg = theme.foreground.ghostty
        var bg = theme.background.ghostty
        var cursor = theme.cursor.ghostty
        _ = ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_COLOR_FOREGROUND, &fg)
        _ = ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_COLOR_BACKGROUND, &bg)
        _ = ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_COLOR_CURSOR, &cursor)

        // Keep the standard 256-colour cube and only replace the 16 ANSI slots.
        var palette = [GhosttyColorRgb](repeating: GhosttyColorRgb(r: 0, g: 0, b: 0), count: 256)
        _ = palette.withUnsafeMutableBufferPointer {
            ghostty_terminal_get(handle, GHOSTTY_TERMINAL_DATA_COLOR_PALETTE_DEFAULT, $0.baseAddress)
        }
        for (i, color) in theme.ansi.enumerated() { palette[i] = color.ghostty }
        _ = palette.withUnsafeBufferPointer {
            ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_COLOR_PALETTE, $0.baseAddress)
        }
    }

    public func resize(cols: Int, rows: Int, cellWidth: Int, cellHeight: Int) {
        _ = ghostty_terminal_resize(
            handle,
            UInt16(clamping: max(cols, 1)),
            UInt16(clamping: max(rows, 1)),
            UInt32(max(cellWidth, 1)),
            UInt32(max(cellHeight, 1)))
    }

    /// Reads a fixed-size value. Returns `fallback` if the terminal has none.
    public func value<T>(_ key: GhosttyTerminalData, default fallback: T) -> T {
        var out = fallback
        let result = withUnsafeMutablePointer(to: &out) { ghostty_terminal_get(handle, key, $0) }
        return result == GHOSTTY_SUCCESS ? out : fallback
    }

    public func string(_ key: GhosttyTerminalData) -> String {
        var out = GhosttyString(ptr: nil, len: 0)
        return ghostty_terminal_get(handle, key, &out) == GHOSTTY_SUCCESS ? out.swiftString : ""
    }

    public var cols: Int { Int(value(GHOSTTY_TERMINAL_DATA_COLS, default: UInt16(0))) }
    public var rows: Int { Int(value(GHOSTTY_TERMINAL_DATA_ROWS, default: UInt16(0))) }
    public var title: String { string(GHOSTTY_TERMINAL_DATA_TITLE) }
    public var pwd: String { string(GHOSTTY_TERMINAL_DATA_PWD) }

    /// Whether a DEC private mode is on.
    public func isModeSet(_ mode: UInt16) -> Bool {
        var config = GhosttyTerminalModeConfig()
        config.mode = ghostty_mode_new(mode, false)
        guard ghostty_terminal_get(handle, GHOSTTY_TERMINAL_DATA_MODE, &config) == GHOSTTY_SUCCESS else {
            return false
        }
        return config.value
    }

    public var isAlternateScreen: Bool {
        value(GHOSTTY_TERMINAL_DATA_ACTIVE_SCREEN, default: GHOSTTY_TERMINAL_SCREEN_PRIMARY) == GHOSTTY_TERMINAL_SCREEN_ALTERNATE
    }

    public func scroll(byRows delta: Int) {
        var behavior = GhosttyTerminalScrollViewport()
        behavior.tag = GHOSTTY_SCROLL_VIEWPORT_DELTA
        behavior.value.delta = delta
        ghostty_terminal_scroll_viewport(handle, behavior)
    }

    /// Limits scrollback by rows alone. The library also has a byte limit, whose
    /// default is far lower and would silently drop most of a long output.
    public func setScrollbackLimit(lines: Int) {
        var limit = lines
        _ = ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_SCROLLBACK_MAX_LINES, &limit)
        _ = ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_SCROLLBACK_MAX_BYTES, nil)
    }

    public func clearSelection() {
        _ = ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_SELECTION, nil)
    }

    /// The selected text, or nil when nothing is selected.
    public func selectedText() -> String? {
        var selection = GhosttySelection()
        selection.size = MemoryLayout<GhosttySelection>.size
        guard ghostty_terminal_get(handle, GHOSTTY_TERMINAL_DATA_SELECTION, &selection) == GHOSTTY_SUCCESS else {
            return nil
        }
        var options = GhosttyTerminalSelectionFormatOptions()
        options.size = MemoryLayout<GhosttyTerminalSelectionFormatOptions>.size
        options.emit = GHOSTTY_FORMATTER_FORMAT_PLAIN
        options.trim = true
        options.unwrap = true
        return withUnsafePointer(to: &selection) { pointer -> String? in
            options.selection = pointer
            var bytes: UnsafeMutablePointer<UInt8>?
            var length = 0
            guard ghostty_terminal_selection_format_alloc(handle, nil, options, &bytes, &length) == GHOSTTY_SUCCESS,
                  let bytes else { return nil }
            defer { ghostty_free(nil, bytes, length) }
            return String(decoding: UnsafeBufferPointer(start: bytes, count: length), as: UTF8.self)
        }
    }

    /// Makes `row`, counted from the top of the scrollback, the first visible row.
    public func setViewport(topRow row: Int) {
        var behavior = GhosttyTerminalScrollViewport()
        behavior.tag = GHOSTTY_SCROLL_VIEWPORT_ROW
        behavior.value.row = row
        ghostty_terminal_scroll_viewport(handle, behavior)
    }

    public var scrollbackRows: Int { value(GHOSTTY_TERMINAL_DATA_SCROLLBACK_ROWS, default: 0) }

    /// Rows that hold anything, counting scrollback. A block has this height, not
    /// the terminal's height, so short output doesn't leave a tall gap.
    public func contentRows() -> Int {
        let width = cols
        var y = rows - 1
        while y >= 0 {
            if rowHasText(y, width: width) { return scrollbackRows + y + 1 }
            y -= 1
        }
        return scrollbackRows
    }

    private func rowHasText(_ y: Int, width: Int) -> Bool {
        var point = GhosttyPoint()
        point.tag = GHOSTTY_POINT_TAG_ACTIVE
        var ref = GhosttyGridRef()
        ref.size = MemoryLayout<GhosttyGridRef>.size
        for x in 0..<width {
            point.value.coordinate = GhosttyPointCoordinate(x: UInt16(x), y: UInt32(y))
            guard ghostty_terminal_grid_ref(handle, point, &ref) == GHOSTTY_SUCCESS else { continue }
            var cell = GhosttyCell()
            guard ghostty_grid_ref_cell(&ref, &cell) == GHOSTTY_SUCCESS else { continue }
            var hasText = false
            _ = ghostty_cell_get(cell, GHOSTTY_CELL_DATA_HAS_TEXT, &hasText)
            if hasText { return true }
        }
        return false
    }

    /// One string per row, in grid order, for searching.
    public func rowTexts() -> [String] {
        plainText().components(separatedBy: "\n")
    }

    /// One string per row, with the escape sequences that reproduce its styling.
    public func styledRows() -> [String] {
        formatted(GHOSTTY_FORMATTER_FORMAT_VT).components(separatedBy: "\n")
            .map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
    }

    /// All the terminal's text, with trailing blanks trimmed.
    public func plainText() -> String {
        formatted(GHOSTTY_FORMATTER_FORMAT_PLAIN)
    }

    private func formatted(_ format: GhosttyFormatterFormat) -> String {
        var options = GhosttyFormatterTerminalOptions()
        options.size = MemoryLayout<GhosttyFormatterTerminalOptions>.size
        options.emit = format
        options.trim = true
        var formatter: GhosttyFormatter?
        guard ghostty_formatter_terminal_new(nil, &formatter, handle, options) == GHOSTTY_SUCCESS,
              let formatter else { return "" }
        defer { ghostty_formatter_free(formatter) }
        var out: UnsafeMutablePointer<UInt8>?
        var len = 0
        guard ghostty_formatter_format_alloc(formatter, nil, &out, &len) == GHOSTTY_SUCCESS, let out else {
            return ""
        }
        defer { ghostty_free(nil, out, len) }
        return String(decoding: UnsafeBufferPointer(start: out, count: len), as: UTF8.self)
    }
}
