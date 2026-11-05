import CGhosttyVT
import RewarpCore

struct RowKey: Hashable {
    var high: UInt64
    var low: UInt64
}

/// The prepared instances for one row. `y` values are relative to the row's top,
/// so a row that merely moved can be reused by patching them at emit time.
struct RowData {
    var background: [Instance] = []
    var text: [Instance] = []
    var colorText: [Instance] = []
    var decoration: [Instance] = []
    var stamp = 0
}

@inline(__always)
func packed(_ color: GhosttyColorRgb, alpha: UInt8 = 255) -> UInt32 {
    UInt32(color.r) | UInt32(color.g) << 8 | UInt32(color.b) << 16 | UInt32(alpha) << 24
}

@inline(__always)
func packed(_ color: RGB, alpha: UInt8 = 255) -> UInt32 {
    UInt32(color.r) | UInt32(color.g) << 8 | UInt32(color.b) << 16 | UInt32(alpha) << 24
}

/// Turns one terminal's render state into instances. Rows are cached by the
/// library's stable row id and rebuilt when marked dirty. The library marks every
/// row dirty after the viewport scrolls, so the cache mostly helps rows that sit
/// still, such as a TUI redrawing part of the screen.
final class TerminalSurface {
    private let state: GhosttyRenderState
    private let rows: GhosttyRenderStateRowIterator
    private let cells: GhosttyRenderStateRowCells

    private var cache: [RowKey: RowData] = [:]
    private var order: [(key: RowKey, y: Int)] = []
    private var stamp = 0
    private var glyphGeneration = -1
    private var colors = GhosttyRenderStateColors()
    private var cursor = GhosttyRenderStateCursor()
    private var style = GhosttyStyle()
    private var selectionColor: UInt32 = 0
    private var cluster = [UInt32](repeating: 0, count: 32)

    /// The viewport row this surface last captured, used to skip finished blocks
    /// that haven't moved.
    var capturedRow = -1
    var needsCapture = true

    init() {
        var state: GhosttyRenderState?
        var rows: GhosttyRenderStateRowIterator?
        var cells: GhosttyRenderStateRowCells?
        guard ghostty_render_state_new(nil, &state) == GHOSTTY_SUCCESS,
              ghostty_render_state_row_iterator_new(nil, &rows) == GHOSTTY_SUCCESS,
              ghostty_render_state_row_cells_new(nil, &cells) == GHOSTTY_SUCCESS,
              let state, let rows, let cells else {
            fatalError("could not create a render state")
        }
        self.state = state
        self.rows = rows
        self.cells = cells
        // One extra row, because a pixel-scrolled list can show part of one more
        // row than the viewport holds.
        var overscan = GhosttyRenderStateOverscan(above: 0, below: 1)
        _ = ghostty_render_state_set(state, GHOSTTY_RENDER_STATE_OPTION_OVERSCAN, &overscan)

        colors.size = MemoryLayout<GhosttyRenderStateColors>.size
        cursor.size = MemoryLayout<GhosttyRenderStateCursor>.size
        style.size = MemoryLayout<GhosttyStyle>.size
    }

    deinit {
        ghostty_render_state_row_cells_free(cells)
        ghostty_render_state_row_iterator_free(rows)
        ghostty_render_state_free(state)
    }

    /// False once the glyph atlas has been reset, which moves everything in it.
    func isCurrent(with glyphs: GlyphCache) -> Bool {
        glyphGeneration == glyphs.generation
    }

    /// Must run under the session lock. This is the only part of a frame that
    /// holds up the parser, so all the expensive work happens in `prepare`.
    func capture(_ terminal: VTTerminal) {
        _ = ghostty_render_state_begin_update(state, terminal.handle)
    }

    /// Runs outside the lock, after `capture`.
    func prepare(glyphs: GlyphCache, theme: Theme) {
        _ = ghostty_render_state_end_update(state)
        _ = ghostty_render_state_get(state, GHOSTTY_RENDER_STATE_DATA_COLORS, &colors)
        _ = ghostty_render_state_get(state, GHOSTTY_RENDER_STATE_DATA_CURSOR, &cursor)
        selectionColor = packed(theme.selection)

        if glyphs.generation != glyphGeneration {
            glyphGeneration = glyphs.generation
            cache.removeAll(keepingCapacity: true)
        }

        var iterator: GhosttyRenderStateRowIterator? = rows
        _ = ghostty_render_state_get(state, GHOSTTY_RENDER_STATE_DATA_ROW_ITERATOR, &iterator)

        stamp += 1
        order.removeAll(keepingCapacity: true)
        var y: Int32 = 0
        while ghostty_render_state_row_iterator_next(rows) {
            var id = GhosttyRenderStateRowId()
            var dirty = false
            _ = ghostty_render_state_row_get(rows, GHOSTTY_RENDER_STATE_ROW_DATA_ID, &id)
            _ = ghostty_render_state_row_get(rows, GHOSTTY_RENDER_STATE_ROW_DATA_DIRTY, &dirty)
            _ = ghostty_render_state_row_get(rows, GHOSTTY_RENDER_STATE_ROW_DATA_VIEWPORT_Y, &y)
            let key = withUnsafeBytes(of: id.bits) { raw in
                RowKey(high: raw.load(as: UInt64.self), low: raw.load(fromByteOffset: 8, as: UInt64.self))
            }
            if dirty || cache[key] == nil {
                // Built in place, so the row's arrays are reused without copying.
                build(&cache[key, default: RowData()], glyphs: glyphs)
                cache[key]!.stamp = stamp
            } else {
                cache[key]!.stamp = stamp
            }
            order.append((key, Int(y)))
        }
        _ = ghostty_render_state_clean(state)

        if cache.count > order.count * 2 + 16 {
            let current = stamp
            cache = cache.filter { $0.value.stamp == current }
        }
    }

    private func build(_ row: inout RowData, glyphs: GlyphCache) {
        row.background.removeAll(keepingCapacity: true)
        row.text.removeAll(keepingCapacity: true)
        row.colorText.removeAll(keepingCapacity: true)
        row.decoration.removeAll(keepingCapacity: true)

        var cellIterator: GhosttyRenderStateRowCells? = cells
        _ = ghostty_render_state_row_get(rows, GHOSTTY_RENDER_STATE_ROW_DATA_CELLS, &cellIterator)

        var selection = GhosttyRenderStateRowSelection()
        selection.size = MemoryLayout<GhosttyRenderStateRowSelection>.size
        let hasSelection = ghostty_render_state_row_get(
            rows, GHOSTTY_RENDER_STATE_ROW_DATA_SELECTION, &selection) == GHOSTTY_SUCCESS

        let cellWidth = glyphs.cellWidth
        let cellHeight = UInt16(glyphs.cellHeight)
        let defaultForeground = packed(colors.foreground)
        let defaultBackground = packed(colors.background)

        var column = -1
        var runStart = 0
        var runColor: UInt32 = 0
        func flushRun(to end: Int) {
            guard runColor != 0, end > runStart else { return }
            row.background.append(Instance(
                x: Int16(runStart * cellWidth), y: 0,
                width: UInt16((end - runStart) * cellWidth), height: cellHeight, color: runColor))
        }

        while ghostty_render_state_row_cells_next(cells) {
            column += 1
            var length: UInt32 = 0
            var hasStyling = false
            _ = ghostty_render_state_row_cells_get(cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_LEN, &length)
            _ = ghostty_render_state_row_cells_get(cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_HAS_STYLING, &hasStyling)

            var foreground = defaultForeground
            var background: UInt32 = 0
            var fontStyle = 0
            var underline = Int32(0)
            var strikethrough = false
            var overline = false
            var invisible = false

            if hasStyling {
                _ = ghostty_render_state_row_cells_get(cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_STYLE, &style)
                var color = GhosttyColorRgb()
                if ghostty_render_state_row_cells_get(cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_FG_COLOR, &color) == GHOSTTY_SUCCESS {
                    foreground = packed(color)
                }
                if ghostty_render_state_row_cells_get(cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_BG_COLOR, &color) == GHOSTTY_SUCCESS {
                    background = packed(color)
                }
                if style.bold { fontStyle |= GlyphCache.Style.bold }
                if style.italic { fontStyle |= GlyphCache.Style.italic }
                if style.inverse {
                    let swapped = background == 0 ? defaultBackground : background
                    background = foreground
                    foreground = swapped
                }
                if style.faint { foreground = (foreground & 0x00FF_FFFF) | 0x8000_0000 }
                underline = Int32(style.underline)
                strikethrough = style.strikethrough
                overline = style.overline
                invisible = style.invisible
            } else if length == 0 {
                // Erased cells can carry a background without having a style.
                var color = GhosttyColorRgb()
                if ghostty_render_state_row_cells_get(cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_BG_COLOR, &color) == GHOSTTY_SUCCESS {
                    background = packed(color)
                }
            }

            if hasSelection, column >= Int(selection.start_x), column <= Int(selection.end_x) {
                background = selectionColor
            }

            if background != runColor {
                flushRun(to: column)
                runStart = column
                runColor = background
            }

            guard length > 0, !invisible else { continue }

            let glyph: Glyph
            if length == 1 {
                var codepoint: UInt32 = 0
                _ = ghostty_render_state_row_cells_get(cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_BUF, &codepoint)
                if codepoint == 0x20 && underline == 0 && !strikethrough && !overline { continue }
                glyph = glyphs.glyph(codepoint: codepoint, style: fontStyle)
            } else {
                let count = Int(length)
                if count > cluster.count { continue }
                _ = cluster.withUnsafeMutableBufferPointer {
                    ghostty_render_state_row_cells_get(cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_BUF, $0.baseAddress)
                }
                glyph = glyphs.glyph(cluster: Array(cluster[..<count]), style: fontStyle)
            }

            let x = column * cellWidth
            if !glyph.isEmpty {
                let instance = Instance(
                    x: Int16(x + Int(glyph.left)), y: glyph.top,
                    width: glyph.width, height: glyph.height,
                    u: glyph.u, v: glyph.v,
                    color: glyph.isColor ? (foreground | 0xFF00_0000) : foreground)
                if glyph.isColor { row.colorText.append(instance) } else { row.text.append(instance) }
            }

            func line(y: Int, thickness: Int) {
                row.decoration.append(Instance(
                    x: Int16(x), y: Int16(y), width: UInt16(cellWidth),
                    height: UInt16(thickness), color: foreground))
            }
            let thickness = glyphs.underlineThickness
            if underline != 0 {
                line(y: glyphs.baseline + thickness * 2, thickness: thickness)
                if underline == 2 { line(y: glyphs.baseline + thickness * 4, thickness: thickness) }
            }
            if strikethrough { line(y: glyphs.baseline - glyphs.cellHeight / 4, thickness: thickness) }
            if overline { line(y: 0, thickness: thickness) }
        }
        flushRun(to: column + 1)
    }

    /// `rowLimit` stops rows past the block's content from drawing, which matters
    /// for the extra overscan row.
    func emit(into frame: Frame, left: Int, top: Int, cellHeight: Int, rowLimit: Int = .max) {
        for (key, y) in order where y < rowLimit {
            guard let row = cache[key] else { continue }
            let rowTop = top + y * cellHeight
            frame.append(row.background, to: \.background, x: left, y: rowTop)
            frame.append(row.text, to: \.text, x: left, y: rowTop)
            frame.append(row.colorText, to: \.colorText, x: left, y: rowTop)
            frame.append(row.decoration, to: \.decoration, x: left, y: rowTop)
        }
    }

    func emitCursor(into frame: Frame, left: Int, top: Int, glyphs: GlyphCache, focused: Bool) {
        guard cursor.visible, cursor.viewport_has_value else { return }
        let x = left + Int(cursor.viewport_x) * glyphs.cellWidth
        let y = top + Int(cursor.viewport_y) * glyphs.cellHeight
        let color = packed(colors.cursor_has_value ? colors.cursor : colors.foreground)
        let width = glyphs.cellWidth
        let height = glyphs.cellHeight

        func rect(_ dx: Int, _ dy: Int, _ w: Int, _ h: Int) {
            frame.background.append(Instance(
                x: Int16(x + dx), y: Int16(y + dy), width: UInt16(w), height: UInt16(h), color: color))
        }

        if !focused || cursor.visual_style == GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BLOCK_HOLLOW {
            let t = glyphs.underlineThickness
            rect(0, 0, width, t)
            rect(0, height - t, width, t)
            rect(0, t, t, height - t * 2)
            rect(width - t, t, t, height - t * 2)
        } else if cursor.visual_style == GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BAR {
            rect(0, 0, max(2, glyphs.underlineThickness * 2), height)
        } else if cursor.visual_style == GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_UNDERLINE {
            rect(0, height - max(2, glyphs.underlineThickness * 2), width, max(2, glyphs.underlineThickness * 2))
        } else {
            rect(0, 0, width, height)
            // The text under a block cursor has to flip to stay readable.
            let inverted = packed(colors.background)
            frame.recolorText(cellLeft: x, cellTop: y, cellWidth: width, cellHeight: height, color: inverted)
        }
    }
}
