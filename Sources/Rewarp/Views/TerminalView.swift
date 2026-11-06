import AppKit
import CGhosttyVT
import QuartzCore
import RewarpCore

struct FontSet {
    let terminal: GlyphCache
    let chrome: GlyphCache
}

/// Glyphs are rasterised for one backing scale, so a window that moves to a display
/// with a different density needs a different set.
final class FontLibrary {
    let pointSize: CGFloat
    private var sets: [CGFloat: FontSet] = [:]

    init(pointSize: CGFloat) {
        self.pointSize = pointSize
    }

    func fonts(scale: CGFloat) -> FontSet {
        if let set = sets[scale] { return set }
        let device = MetalContext.shared.device
        let set = FontSet(terminal: GlyphCache(device: device, family: nil, pointSize: pointSize, scale: scale),
                          chrome: GlyphCache(device: device, family: nil, pointSize: pointSize - 2, scale: scale))
        sets[scale] = set
        return set
    }
}

/// Draws a pane: the block list, a full-screen program, or a plain terminal when
/// the shell has no integration. Input handling is in the extensions.
final class TerminalView: NSView, NSTextInputClient {
    static let paddingX: CGFloat = 14
    static let paddingY: CGFloat = 8

    enum Display {
        /// The shell has no integration, so its terminal fills the pane.
        case plain
        case list
        case fullScreen(Block)
    }

    /// One block's on-screen placement for the current frame. Everything a frame
    /// needs is copied here under the lock, so drawing never touches live state.
    struct PlacedBlock {
        let block: Block
        let entry: BlockLayout.Entry
        let firstRow: Int
        let isRunning: Bool
        let didFail: Bool
        let presentation: BlockPresentation
    }

    struct BlockPresentation {
        var rows: Int
        var commandLines: [String]
        var context: String
        var duration: String
        var isFinished: Bool
    }

    let session: PaneSession
    let theme: Theme
    private(set) var fonts: FontSet
    private let library: FontLibrary
    var onFocus: (() -> Void)?
    var onFocusInput: (() -> Void)?
    var onInsertIntoInput: ((String) -> Void)?
    var onReinput: ((String) -> Void)?
    var onSplit: ((SplitAxis) -> Void)?
    var onToggleZoom: (() -> Void)?
    var onClose: (() -> Void)?

    /// Height reserved at the bottom for the input editor, in points.
    var bottomInset: CGFloat = 0 {
        didSet {
            if bottomInset != oldValue { session.requestFrame() }
        }
    }

    var glyphs: GlyphCache { fonts.terminal }
    var scale: CGFloat { scaleForTesting ?? window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }
    var scaleForTesting: CGFloat?

    let keyEncoder = KeyEncoder()
    let mouseEncoder = MouseEncoder()
    let gesture: GhosttySelectionGesture
    /// The terminal holding the selection. Filtering replaces the terminal a block
    /// draws from, so this is kept rather than looked up, and it's only touched
    /// under the lock.
    var gestureTerminal: VTTerminal?

    var layout: BlockLayout
    var scroll = BlockScroll()
    var placed: [PlacedBlock] = []
    var listOrigin = 0
    var presentations: [Int: BlockPresentation] = [:]
    var surfaces: [Int: TerminalSurface] = [:]
    var bookmarkTops: [Int] = []
    /// The grid size, kept here because the main thread is what sets it.
    var gridColumns = 80
    var gridRows = 24

    var selectedBlocks = Set<Int>()
    var activeBlock: Int?
    var hoveredBlock: Int?
    var hoveredControl: BlockControl?
    var press: Press?
    var textSelectionBlock: Block?
    var isPointerInside = false
    var stickyHeaderEnabled = true
    var finder = BlockFinder()
    var findQuery: TextQuery?
    /// Limits find to one block, for find within a selected block.
    var findScope: Int?
    var lastMenuTitles: [String] = []

    var markedTextValue = ""
    var keyText = ""
    var isInterpreting = false
    var pressedButtons = Set<Int>()
    var scrollRemainder: CGFloat = 0

    private var plainSurface = TerminalSurface()
    private let frameData = Frame()
    private var renderer: PaneRenderer?
    private var displayLink: CADisplayLink?
    private var idleTicks = 0
    private var lastColumns = 0
    private let startedAt = CACurrentMediaTime()
    private static let bootstrapGrace: Double = 3
    /// Off-screen surfaces kept for quick return. Each holds a render state of
    /// about 350 KB, so keeping one per block would grow without end.
    private static let spareSurfaces = 8
    /// How many exist, so that end-to-end tests can see them being freed.
    static var liveCount = 0

    init(session: PaneSession, theme: Theme, library: FontLibrary, fonts: FontSet) {
        self.session = session
        self.theme = theme
        self.library = library
        self.fonts = fonts
        layout = BlockLayout(cellHeight: fonts.terminal.cellHeight, footerHeight: 0)
        var gesture: GhosttySelectionGesture?
        guard ghostty_selection_gesture_new(nil, &gesture) == GHOSTTY_SUCCESS, let gesture else {
            fatalError("could not create the selection gesture")
        }
        self.gesture = gesture
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        session.onNeedsDisplay = { [weak self] in self?.wake() }
        Self.liveCount += 1
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        let terminal = gestureTerminal ?? session.withState { $0.shell }
        ghostty_selection_gesture_free(gesture, terminal.handle)
        Self.liveCount -= 1
    }

    override func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        renderer = PaneRenderer(layer: layer)
        return layer
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    /// Clicking into the app from elsewhere acts on what was clicked.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Layout

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else {
            displayLink?.invalidate()
            displayLink = nil
            return
        }
        let link = displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
        updateDrawableSize()

        let center = NotificationCenter.default
        center.removeObserver(self)
        center.addObserver(self, selector: #selector(keyWindowChanged),
                           name: NSWindow.didBecomeKeyNotification, object: window)
        center.addObserver(self, selector: #selector(keyWindowChanged),
                           name: NSWindow.didResignKeyNotification, object: window)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let current = library.fonts(scale: scale)
        if current.terminal !== fonts.terminal {
            fonts = current
            // Everything measured or drawn with the old cell size has to go. The
            // grid can come out the same size, but the session still needs to hear.
            surfaces.removeAll()
            plainSurface = TerminalSurface()
            presentations.removeAll()
            layout = BlockLayout(cellHeight: glyphs.cellHeight, footerHeight: 0)
            gridColumns = 0
        }
        updateDrawableSize()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateDrawableSize()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self))
    }

    private func updateDrawableSize() {
        guard let layer = layer as? CAMetalLayer, bounds.width > 0, bounds.height > 0 else { return }
        layer.contentsScale = scale
        layer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        let padX = Int(Self.paddingX * scale)
        let padY = Int(Self.paddingY * scale)
        let cols = max(1, (Int(layer.drawableSize.width) - padX * 2) / glyphs.cellWidth)
        let rows = max(1, (Int(layer.drawableSize.height) - padY * 2) / glyphs.cellHeight)
        if cols != gridColumns || rows != gridRows {
            gridColumns = cols
            gridRows = rows
            session.resize(cols: cols, rows: rows, cellWidth: glyphs.cellWidth, cellHeight: glyphs.cellHeight)
            for surface in surfaces.values { surface.needsCapture = true }
        }
        wake()
    }

    var listHeight: Int { max(0, Int((bounds.height - bottomInset) * scale)) }

    // MARK: Frames

    /// The display link only runs while something is changing, so an idle pane
    /// costs nothing at all.
    func wake() {
        idleTicks = 0
        displayLink?.isPaused = false
    }

    @objc private func tick(_ link: CADisplayLink) {
        // A program is partway through a frame. The request stays pending, so the
        // finished frame is drawn as soon as the hold ends.
        if session.isHoldingFrames { return }
        guard session.consumeFrameRequest() else {
            idleTicks += 1
            if idleTicks > 30 { link.isPaused = true }
            return
        }
        idleTicks = 0
        draw()
    }

    private func currentDisplay(_ state: PaneSession.State) -> Display {
        if state.isShowingStartup { return .plain }
        if let last = state.blocks.last, state.isRunning(last), state.terminal(of: last).isAlternateScreen {
            return .fullScreen(last)
        }
        if !state.hasIntegration,
           !state.expectsIntegration || CACurrentMediaTime() - startedAt > Self.bootstrapGrace {
            return .plain
        }
        return .list
    }

    /// Exposed to the pane, which hides the input for plain and full-screen modes.
    var display: Display {
        session.withState { currentDisplay($0) }
    }

    private func buildFrame() {
        frameData.reset()
        let left = Int(Self.paddingX * scale)
        let top = Int(Self.paddingY * scale)

        func emitWhole(_ surface: TerminalSurface) {
            surface.prepare(glyphs: glyphs, theme: theme)
            surface.emit(into: frameData, left: left, top: top, cellHeight: glyphs.cellHeight)
            surface.emitCursor(into: frameData, left: left, top: top, glyphs: glyphs, focused: isFocused)
        }

        // Only the capture holds the lock, so the parser waits as little as possible.
        enum Captured {
            case whole(TerminalSurface)
            case list([TerminalSurface])
        }
        let captured: Captured = session.withState { state in
            switch currentDisplay(state) {
            case .plain:
                plainSurface.capture(state.shell)
                return .whole(plainSurface)
            case .fullScreen(let block):
                let surface = surface(for: block)
                surface.capture(state.terminal(of: block))
                surface.needsCapture = true
                return .whole(surface)
            case .list:
                return .list(captureList(state))
            }
        }

        switch captured {
        case .whole(let surface):
            emitWhole(surface)
        case .list(let pending):
            for surface in pending { surface.prepare(glyphs: glyphs, theme: theme) }
            emitList(into: frameData)
        }
    }

    private func draw() {
        #if DEBUG || REWARP_TESTING
        let start = CACurrentMediaTime()
        #endif
        let generation = glyphs.generation
        buildFrame()
        // Filling the atlas moved glyphs this frame had already placed.
        if glyphs.generation != generation { buildFrame() }
        #if DEBUG || REWARP_TESTING
        let built = CACurrentMediaTime()
        #endif
        renderer?.draw(frameData, glyphs: glyphs, chromeGlyphs: fonts.chrome, clear: theme.background)
        #if DEBUG || REWARP_TESTING
        FrameStats.shared.record(build: built - start, total: CACurrentMediaTime() - start)
        #endif
    }

    #if DEBUG || REWARP_TESTING
    func prepareFrameForTesting() {
        buildFrame()
    }

    /// Writes the current frame to a PNG. Used by scripted checks.
    func capture(to path: String) {
        guard let layer = layer as? CAMetalLayer else { return }
        buildFrame()
        let size = layer.drawableSize
        guard let image = renderer?.capture(frameData, glyphs: glyphs, chromeGlyphs: fonts.chrome,
                                            clear: theme.background, width: Int(size.width),
                                            height: Int(size.height)) else { return }
        let bitmap = NSBitmapImageRep(cgImage: image)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
    #endif

    // MARK: Block list

    func surface(for block: Block) -> TerminalSurface {
        if let surface = surfaces[block.id] { return surface }
        let surface = TerminalSurface()
        surfaces[block.id] = surface
        return surface
    }

    private var headerMetrics: (top: Int, context: Int, gap: Int, below: Int) {
        (Int(8 * scale), fonts.chrome.cellHeight, Int(2 * scale), Int(4 * scale))
    }

    private var footerHeight: Int { Int(8 * scale) }

    private func headerHeight(commandLines: Int) -> Int {
        let m = headerMetrics
        return m.top + m.context + m.gap + commandLines * glyphs.cellHeight + m.below
    }

    private func syncLayout(_ state: PaneSession.State) {
        let blocks = state.blocks
        let columns = state.cols
        let countChanged = blocks.count != layout.entries.count
        let widthChanged = columns != lastColumns
        lastColumns = columns

        if layout.footerHeight != footerHeight {
            layout = BlockLayout(cellHeight: glyphs.cellHeight, footerHeight: footerHeight)
        }

        if !countChanged && !widthChanged && !layout.entries.isEmpty {
            // Only the newest block can still be changing.
            guard let last = blocks.last else { return }
            if state.isRunning(last) || presentations[last.id]?.isFinished != true {
                let presentation = present(last, columns: columns, state)
                presentations[last.id] = presentation
                layout.updateLast(outputRows: presentation.rows)
            }
            return
        }

        var specs: [BlockLayout.Spec] = []
        specs.reserveCapacity(blocks.count)
        for block in blocks {
            var presentation = presentations[block.id]
            if presentation == nil || widthChanged || !presentation!.isFinished {
                presentation = present(block, columns: columns, state)
                presentations[block.id] = presentation
            }
            specs.append(.init(id: block.id,
                               headerHeight: headerHeight(commandLines: presentation!.commandLines.count),
                               outputRows: presentation!.rows))
        }
        layout.rebuild(specs)

        // Blocks can be removed by clearing, so stale state goes at the same time.
        if countChanged {
            let live = Set(blocks.map(\.id))
            presentations = presentations.filter { live.contains($0.key) }
            surfaces = surfaces.filter { live.contains($0.key) }
            selectedBlocks.formIntersection(live)
            if let active = activeBlock, !live.contains(active) { activeBlock = nil }
            if let hovered = hoveredBlock, !live.contains(hovered) { hoveredBlock = nil }
        }
    }

    private func present(_ block: Block, columns: Int, _ state: PaneSession.State) -> BlockPresentation {
        var context = ShellLaunch.abbreviate(path: block.workingDirectory)
        if let branch = block.gitBranch { context += "  \u{E0A0} \(branch)" }
        let isRunning = state.isRunning(block)
        return BlockPresentation(
            rows: state.terminal(of: block).isAlternateScreen ? 0 : state.displayTerminal(of: block).contentRows(),
            commandLines: wrap(block.command, columns: columns),
            context: context,
            duration: isRunning ? "" : Self.format(duration: state.duration(of: block)),
            isFinished: !isRunning)
    }

    private func wrap(_ text: String, columns: Int) -> [String] {
        var lines: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var current = ""
            var width = 0
            for scalar in line.unicodeScalars {
                let cells = GlyphCache.cells(for: scalar)
                if width + cells > columns {
                    lines.append(current)
                    current = ""
                    width = 0
                }
                current.unicodeScalars.append(scalar)
                width += cells
            }
            lines.append(current)
        }
        return lines.isEmpty ? [""] : lines
    }

    static func format(duration: TimeInterval) -> String {
        if duration < 60 { return String(format: "%.2fs", duration) }
        let seconds = Int(duration.rounded())
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m \(seconds % 60)s" }
        return "\(minutes)m \(seconds % 60)s"
    }

    /// Returns the surfaces that captured new state.
    private func captureList(_ state: PaneSession.State) -> [TerminalSurface] {
        syncLayout(state)
        let viewport = listHeight
        let content = layout.contentHeight
        scroll.settle(content: content, viewport: viewport)
        // Blocks sit directly above the input, so a short list hugs the bottom.
        listOrigin = max(0, viewport - content) - scroll.offset

        placed.removeAll(keepingCapacity: true)
        var pending: [TerminalSurface] = []
        let cellHeight = glyphs.cellHeight
        let blocks = state.blocks

        for index in layout.visibleRange(top: scroll.offset, height: viewport) {
            let entry = layout.entries[index]
            let block = blocks[index]
            guard let presentation = presentations[block.id] else { continue }
            let isRunning = state.isRunning(block)
            var firstRow = 0
            if entry.outputRows > 0 {
                firstRow = min(max(0, (scroll.offset - entry.outputTop) / cellHeight), entry.outputRows - 1)
                let surface = surface(for: block)
                if isRunning || surface.needsCapture || surface.capturedRow != firstRow
                    || !surface.isCurrent(with: glyphs) {
                    let terminal = state.displayTerminal(of: block)
                    terminal.setViewport(topRow: firstRow)
                    surface.capture(terminal)
                    surface.capturedRow = firstRow
                    surface.needsCapture = false
                    pending.append(surface)
                }
            }
            placed.append(PlacedBlock(block: block, entry: entry, firstRow: firstRow, isRunning: isRunning,
                                      didFail: state.didFail(block), presentation: presentation))
        }

        // The scrollbar draws after the lock is gone, so it gets its own copy.
        bookmarkTops = isPointerInside
            ? zip(blocks, layout.entries).filter(\.0.isBookmarked).map(\.1.top)
            : []

        if surfaces.count > placed.count + Self.spareSurfaces {
            let visible = Set(placed.map(\.block.id))
            surfaces = surfaces.filter { visible.contains($0.key) }
        }
        return pending
    }

    private func emitList(into frame: Frame) {
        let left = Int(Self.paddingX * scale)
        let width = Int(bounds.width * scale)
        let m = headerMetrics
        let failedColor = theme.ansi[1]
        let failedTint = packed(theme.background.mixed(with: failedColor, 0.12))
        let divider = packed(theme.background.mixed(with: theme.foreground, 0.12))
        let secondary = packed(theme.foreground.mixed(with: theme.background, 0.42))
        let foreground = packed(theme.foreground)
        let cellHeight = glyphs.cellHeight
        let chromeGlyphs = fonts.chrome

        for item in placed {
            let top = listOrigin + item.entry.top
            let height = item.entry.height

            if item.didFail {
                frame.background.insert(rect(0, top, width, height, failedTint), at: 0)
                frame.background.append(rect(0, top, Int(3 * scale), height, packed(failedColor)))
            }
            frame.background.append(rect(0, top + height - 1, width, 1, divider))

            var y = top + m.top
            let contextEnd = chromeGlyphs.emit(item.presentation.context, x: left, top: y, color: secondary,
                                               limit: width - left, into: &frame.chromeText)
            if !item.presentation.duration.isEmpty {
                chromeGlyphs.emit("(\(item.presentation.duration))", x: contextEnd + chromeGlyphs.cellWidth, top: y,
                                  color: secondary, into: &frame.chromeText)
            }
            y += m.context + m.gap

            for line in item.presentation.commandLines {
                glyphs.emit(line, x: left, top: y, color: foreground, style: GlyphCache.Style.bold,
                            limit: width, into: &frame.text)
                y += cellHeight
            }

            if item.entry.outputRows > 0, let surface = surfaces[item.block.id] {
                let outputTop = listOrigin + item.entry.outputTop + item.firstRow * cellHeight
                emitFindHighlights(for: item, left: left, into: frame)
                surface.emit(into: frame, left: left, top: outputTop, cellHeight: cellHeight,
                             rowLimit: item.entry.outputRows - item.firstRow)
                if item.isRunning {
                    surface.emitCursor(into: frame, left: left, top: outputTop, glyphs: glyphs, focused: isFocused)
                }
            }
        }

        emitSelectionBorders(into: frame, width: width)
        emitToolbelt(into: frame, width: width)
        emitStickyHeader(into: frame, width: width)
        emitScrollbar(into: frame, width: width)
    }

    /// A filled rectangle, clipped to the view. Clipping keeps the block's real
    /// edges even when it's far taller than the 16-bit instance format can reach.
    func rect(_ x: Int, _ y: Int, _ width: Int, _ height: Int, _ color: UInt32) -> Instance {
        let top = max(y, 0)
        let bottom = min(y + height, Int(bounds.height * scale))
        return Instance(x: Int16(clamping: x), y: Int16(clamping: top), width: UInt16(clamping: max(0, width)),
                        height: UInt16(clamping: max(0, bottom - top)), color: color)
    }

    private func emitSelectionBorders(into frame: Frame, width: Int) {
        guard !selectedBlocks.isEmpty else { return }
        let accent = packed(theme.accent)
        let tint = packed(theme.accent, alpha: 28)
        let thin = max(1, Int(1 * scale))
        let thick = max(2, Int(2 * scale))

        // Adjacent selected blocks share one border instead of drawing two.
        var index = 0
        while index < placed.count {
            guard selectedBlocks.contains(placed[index].block.id) else {
                index += 1
                continue
            }
            let start = index
            while index + 1 < placed.count, selectedBlocks.contains(placed[index + 1].block.id) { index += 1 }
            let first = placed[start].entry
            let last = placed[index].entry
            let top = listOrigin + first.top
            let height = last.bottom - first.top
            let hasActive = placed[start...index].contains { $0.block.id == activeBlock }
            let border = hasActive ? thick : thin
            frame.overlay.append(rect(0, top, width, height, tint))
            frame.overlay.append(rect(0, top, width, border, accent))
            frame.overlay.append(rect(0, top + height - border, width, border, accent))
            frame.overlay.append(rect(0, top, border, height, accent))
            frame.overlay.append(rect(width - border, top, border, height, accent))
            index += 1
        }
    }

    // MARK: Focus

    /// Read from the window, never stored: AppKit drops a view's first responder
    /// status without calling resignFirstResponder when the view is reparented.
    var isFocused: Bool {
        guard let window else { return false }
        return window.isKeyWindow && window.firstResponder === self
    }

    override func becomeFirstResponder() -> Bool {
        onFocus?()
        session.requestFrame()
        return true
    }

    override func resignFirstResponder() -> Bool {
        session.requestFrame()
        return true
    }

    @objc private func keyWindowChanged() {
        session.requestFrame()
    }
}
