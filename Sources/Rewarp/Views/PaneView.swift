import AppKit
import RewarpCore

/// One pane: a session and the views that show it.
final class PaneView: NSView {
    /// How long a command runs before the input gets out of the way. Fast commands
    /// finish first, so the layout never jumps for them.
    private static let hideInputDelay: TimeInterval = 0.12
    /// How long a shell at a prompt gets to report that it's reading input.
    private static let assumeReadyDelay: TimeInterval = 1
    /// Just past TerminalView's grace period, so the display changes first.
    private static let integrationGrace: TimeInterval = 3.1
    /// How long startup files run before anything they printed is shown. Long enough
    /// that a normal start never flickers.
    private static let startupPatience: TimeInterval = 2

    let session: PaneSession
    let terminal: TerminalView
    let input: InputBar

    var onFocus: ((PaneView) -> Void)?
    var onTitleChange: ((PaneView) -> Void)?
    var onExit: ((PaneView) -> Void)?
    var onSplit: ((SplitAxis) -> Void)?
    var onToggleZoom: (() -> Void)?
    var onClosePane: ((PaneView) -> Void)?

    private(set) var title = "zsh"
    /// The working directory and branch, shown under the input and in the sidebar.
    private(set) var contextText = ""
    private var hideTimer: Timer?
    private let theme: Theme
    private var findBar: QueryBar?
    private var filterBar: QueryBar?
    /// Weak, because clearing the list should free a block even with a filter on it.
    private weak var filterTarget: Block?
    private var liveQueryTimer: Timer?
    private var isInputHidden = false

    init(theme: Theme, fonts library: FontLibrary, scale: CGFloat, workingDirectory: String, history: CommandHistory) {
        self.theme = theme
        let fonts = library.fonts(scale: scale)
        session = PaneSession(cols: 80, rows: 24, cellWidth: fonts.terminal.cellWidth,
                              cellHeight: fonts.terminal.cellHeight, theme: theme,
                              workingDirectory: workingDirectory)
        terminal = TerminalView(session: session, theme: theme, library: library, fonts: fonts)
        input = InputBar(theme: theme, fontSize: library.pointSize, history: history)
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(terminal)
        addSubview(input)
        updateContext(directory: workingDirectory)

        terminal.onFocus = { [weak self] in
            guard let self else { return }
            self.onFocus?(self)
        }
        terminal.onFocusInput = { [weak self] in self?.focusInput() }
        terminal.onInsertIntoInput = { [weak self] in self?.input.editor.insert($0) }
        terminal.onReinput = { [weak self] text in
            guard let self else { return }
            self.terminal.clearBlockSelection()
            self.input.editor.setText(text)
            self.focusInput()
        }
        terminal.onSplit = { [weak self] in self?.onSplit?($0) }
        terminal.onToggleZoom = { [weak self] in self?.onToggleZoom?() }
        terminal.onClose = { [weak self] in
            guard let self else { return }
            self.onClosePane?(self)
        }

        input.onSubmit = { [weak self] in self?.session.submit(command: $0) }
        input.contextProvider = { [weak self] in
            self?.session.completionContext ?? (ShellLaunch.homeDirectory, nil, [])
        }
        input.onHeightChange = { [weak self] in self?.needsLayout = true }
        input.onClearScreen = { [weak self] in self?.terminal.clearBlocks(nil) }
        input.onFocused = { [weak self] in
            guard let self else { return }
            self.terminal.clearBlockSelection()
            self.onFocus?(self)
        }

        session.onEvent = { [weak self] event in self?.handle(event) }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        liveQueryTimer?.invalidate()
    }

    override var isFlipped: Bool { true }

    func start() {
        let launch = ShellLaunch.login(workingDirectory: session.currentDirectory)
        do {
            try session.start(launch: launch)
        } catch {
            NSLog("could not start the shell: \(error)")
            onExit?(self)
            return
        }
        // A shell with no integration can't use the input. One that should have it
        // gets a moment to report in, in case its startup files are slow.
        let wait = launch.hasIntegration ? Self.integrationGrace : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self, !self.session.withState({ $0.hasIntegration }) else { return }
            self.setInput(hidden: true)
            self.window?.makeFirstResponder(self.terminal)
            self.session.fallBackToPlainTerminal()
        }
        if launch.hasIntegration { watchStartup(after: Self.startupPatience) }
    }

    private func watchStartup(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            switch self.session.revealStartupIfWaiting() {
            case .finished:
                break
            case .quiet:
                self.watchStartup(after: 0.25)
            case .waiting:
                self.hideTimer?.invalidate()
                self.setInput(hidden: true)
                self.moveFocusWithinPane(to: self.terminal)
                self.terminal.wake()
            }
        }
    }

    func focusInput() {
        guard !isInputHidden else {
            window?.makeFirstResponder(terminal)
            return
        }
        window?.makeFirstResponder(input.editor)
    }

    override func layout() {
        super.layout()
        terminal.frame = bounds
        let height = isInputHidden ? 0 : input.preferredHeight(paneHeight: bounds.height)
        input.frame = NSRect(x: 0, y: bounds.height - height, width: bounds.width, height: height)
        input.isHidden = isInputHidden
        terminal.bottomInset = height
        for bar in [findBar, filterBar] {
            bar?.frame.origin = NSPoint(x: max(8, bounds.width - QueryBar.size.width - 12), y: 10)
        }
    }

    // MARK: Find and filter

    func openFind() {
        let bar = findBar ?? makeFindBar()
        // Find opened on a selected block stays inside that block.
        terminal.findScope = terminal.selectedBlocks.count == 1 ? terminal.selectedBlocks.first : nil
        if let selected = terminal.selectedText, !selected.contains("\n") {
            bar.setText(selected)
        }
        window?.makeFirstResponder(bar.field)
        bar.field.currentEditor()?.selectAll(nil)
        needsLayout = true
    }

    func closeFind() {
        guard let bar = findBar else { return }
        bar.removeFromSuperview()
        findBar = nil
        terminal.runFind(nil)
        terminal.findScope = nil
        updateLiveQueryTimer()
        focusInput()
    }

    func findNext(forward: Bool) {
        terminal.moveFind(next: forward)
        findBar?.setCount(terminal.finder.label)
    }

    private func makeFindBar() -> QueryBar {
        let bar = QueryBar(mode: .find, theme: theme)
        bar.onChange = { [weak self, weak bar] query, _, _ in
            guard let self else { return }
            self.terminal.runFind(query.text.isEmpty ? nil : query)
            bar?.setCount(self.terminal.finder.label)
            self.updateLiveQueryTimer()
        }
        bar.onNext = { [weak self] in self?.findNext(forward: true) }
        bar.onPrevious = { [weak self] in self?.findNext(forward: false) }
        bar.onClose = { [weak self] in self?.closeFind() }
        addSubview(bar)
        findBar = bar
        return bar
    }

    /// Opens the filter for the selected block, or the latest one.
    func openFilter() {
        guard let target = terminal.targetBlocks.last else { return }
        filterBar?.removeFromSuperview()
        filterTarget = target

        let bar = QueryBar(mode: .filter, theme: theme)
        bar.onChange = { [weak self] query, context, inverted in
            guard let self, let block = self.filterTarget else { return }
            let options = query.text.isEmpty ? nil : BlockFilterOptions(query: query, contextLines: context, isInverted: inverted)
            self.session.setFilter(options, on: block)
            self.terminal.blockDisplayChanged(block)
            self.updateLiveQueryTimer()
        }
        bar.onClose = { [weak self] in self?.closeFilterBar() }
        addSubview(bar)
        filterBar = bar
        needsLayout = true
        window?.makeFirstResponder(bar.field)
    }

    /// The filter stays on the block when the bar goes away.
    func closeFilterBar() {
        filterBar?.removeFromSuperview()
        filterBar = nil
        focusInput()
    }

    /// Clears a block's filter if it has one, or opens the filter if not.
    func toggleFilter() {
        guard let target = terminal.targetBlocks.last else { return }
        if session.withState({ $0.hasFilter(target) }) {
            session.setFilter(nil, on: target)
            terminal.blockDisplayChanged(target)
            closeFilterBar()
        } else {
            openFilter()
        }
    }

    /// Find and filter both follow a command that's still printing.
    private func updateLiveQueryTimer() {
        let filtering = filterTarget.map { block in session.withState { $0.hasFilter(block) } } ?? false
        let needed = findBar != nil || filtering
        if !needed {
            liveQueryTimer?.invalidate()
            liveQueryTimer = nil
            return
        }
        guard liveQueryTimer == nil else { return }
        liveQueryTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.refreshLiveQueries()
        }
    }

    private func refreshLiveQueries() {
        let running = session.withState { $0.phase == .running ? $0.blocks.last : nil }
        if let running { refreshLiveQueries(finished: running) }
    }

    /// Also runs when a block ends, so that its last output is never left out.
    private func refreshLiveQueries(finished block: Block) {
        if let bar = findBar, let query = terminal.findQuery {
            terminal.runFind(query)
            bar.setCount(terminal.finder.label)
        }
        if block === filterTarget {
            session.refreshFilter(of: block)
            terminal.blockDisplayChanged(block)
        }
    }

    private func setInput(hidden: Bool) {
        guard isInputHidden != hidden else { return }
        isInputHidden = hidden
        needsLayout = true
    }

    private func updateContext(directory: String) {
        var text = ShellLaunch.abbreviate(path: directory)
        if let branch = session.currentBranch { text += "   \(branch)" }
        contextText = text
        input.setContext(text)
    }

    /// Moves focus only when it's already inside this pane, because a command
    /// finishing must never pull focus out of a find bar or another pane.
    private func moveFocusWithinPane(to responder: NSResponder) {
        guard let current = window?.firstResponder as? NSView, current === terminal || current === input.editor else {
            return
        }
        window?.makeFirstResponder(responder)
    }

    private func handle(_ event: SessionEvent) {
        switch event {
        case .promptStarted:
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.assumeReadyDelay) { [weak self] in
                self?.session.assumeReadyIfStillAtPrompt()
            }
        case .ready:
            hideTimer?.invalidate()
            setInput(hidden: false)
            layoutSubtreeIfNeeded()
            moveFocusWithinPane(to: input.editor)
        case .blockStarted:
            hideTimer?.invalidate()
            hideTimer = Timer.scheduledTimer(withTimeInterval: Self.hideInputDelay, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.setInput(hidden: true)
                self.moveFocusWithinPane(to: self.terminal)
            }
        case .blockFinished(let block):
            refreshLiveQueries(finished: block)
        case .gitBranchChanged:
            updateContext(directory: session.currentDirectory)
            onTitleChange?(self)
        case .fullScreenChanged(let isFullScreen):
            // Full-screen programs own the whole pane straight away.
            if isFullScreen {
                hideTimer?.invalidate()
                setInput(hidden: true)
                moveFocusWithinPane(to: terminal)
            }
        case .titleChanged(let value):
            if !value.isEmpty {
                title = value
                onTitleChange?(self)
            }
        case .workingDirectoryChanged(let directory):
            updateContext(directory: directory)
            title = (directory as NSString).lastPathComponent
            onTitleChange?(self)
        case .exited:
            onExit?(self)
        case .bell:
            NSSound.beep()
        }
    }

    /// The pane's frame in points from the top-left of the window's content.
    private func debugFrameInWindow() -> [CGFloat] {
        guard let content = window?.contentView else { return [0, 0, 0, 0] }
        let rect = convert(bounds, to: content)
        return [rect.minX, content.bounds.height - rect.maxY, rect.width, rect.height]
    }

    private func debugDisplayRows() -> [String] {
        session.withState { state in
            state.blocks.last.map { state.displayTerminal(of: $0).rowTexts() } ?? []
        }
    }

    /// Text typed into the find or filter bar, as a user would.
    func debugTypeIntoBar(_ text: String) {
        let bar = filterBar ?? findBar
        bar?.setText((bar?.field.stringValue ?? "") + text)
    }

    /// A snapshot of what a user would see, for end-to-end tests.
    func debugState() -> [String: Any] {
        let (phase, blocks): (String, [[String: Any]]) = session.withState { state in
            let blocks: [[String: Any]] = state.blocks.map { block in
                [
                    "id": block.id,
                    "command": block.command,
                    "running": state.isRunning(block),
                    "exit": state.exitCode(of: block).map { $0 as Any } ?? NSNull(),
                    "failed": state.didFail(block),
                    "bookmarked": block.isBookmarked,
                    "output": state.outputText(of: block),
                    "rows": state.terminal(of: block).contentRows(),
                    "alt": state.terminal(of: block).isAlternateScreen,
                ]
            }
            return ("\(state.phase)", blocks)
        }

        var focus = "other"
        if let responder = window?.firstResponder {
            if responder === input.editor { focus = "input" } else if responder === terminal { focus = "terminal" }
        }
        var display = "list"
        switch terminal.display {
        case .plain: display = "plain"
        case .fullScreen: display = "fullscreen"
        case .list: break
        }
        return [
            "phase": phase,
            "display": display,
            "blocks": blocks,
            "focus": focus,
            "input": input.editor.string,
            "ghost": input.editor.ghostText ?? NSNull(),
            "inputHidden": isInputHidden,
            "inputHeight": input.frame.height,
            "menuOpen": input.isMenuOpen,
            "menuMode": input.menuModeName,
            "menuItems": input.menuItems,
            "menuSelected": input.selectedMenuItem ?? NSNull(),
            "findOpen": findBar != nil,
            "findLabel": terminal.finder.label,
            "findHits": terminal.finder.hits.count,
            "filterOpen": filterBar != nil,
            "displayRows": debugDisplayRows(),
            "selected": terminal.selectedBlocks.sorted(),
            "active": terminal.activeBlock ?? NSNull(),
            "hovered": terminal.hoveredBlock ?? NSNull(),
            "selectedText": terminal.selectedText ?? NSNull(),
            "scrollOffset": terminal.scroll.offset,
            "followsTail": terminal.scroll.followsTail,
            "contentHeight": terminal.layout.contentHeight,
            "listHeight": terminal.listHeight,
            "blockFrames": terminal.debugBlockFrames(),
            "contextMenu": terminal.lastMenuTitles,
            "paneFrame": debugFrameInWindow(),
            "paneHidden": isHidden,
            "windowFrame": [window?.contentView?.bounds.width ?? 0, window?.contentView?.bounds.height ?? 0],
        ]
    }
}
