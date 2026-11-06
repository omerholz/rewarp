import AppKit
import RewarpCore

/// The input area: context chips above the editor, and the menus that open over
/// the block list. Everything here belongs to one pane.
final class InputBar: NSView {
    enum MenuMode: Equatable {
        case none
        case history
        case completions
        case search
    }

    let editor: CommandEditor
    let history: CommandHistory
    private let contextLabel = NSTextField(labelWithString: "")
    private let theme: Theme
    private let listMenu = InlineMenuView()
    private let engine = CompletionEngine()
    private var mode = MenuMode.none
    /// The input as it was when a menu opened, for Escape to put back.
    private var anchorText = ""
    private var completionRange: Range<Int> = 0..<0
    private var completions: [Completion] = []
    private var isPreviewing = false

    var onSubmit: ((String) -> Void)?
    var onHeightChange: (() -> Void)?
    var onClearScreen: (() -> Void)?
    var onFocused: (() -> Void)?
    var contextProvider: (() -> (directory: String, path: String?, names: [String]))?

    static let verticalPadding: CGFloat = 8
    static let contextHeight: CGFloat = 18

    init(theme: Theme, fontSize: CGFloat, history: CommandHistory) {
        self.theme = theme
        self.history = history
        editor = CommandEditor(font: .monospacedSystemFont(ofSize: fontSize, weight: .regular))
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(rgb: theme.background).cgColor

        let palette = ChromePalette(theme: theme)
        contextLabel.font = .monospacedSystemFont(ofSize: fontSize - 2, weight: .regular)
        contextLabel.textColor = palette.secondaryText
        contextLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(contextLabel)

        editor.textColor = palette.text
        editor.insertionPointColor = NSColor(rgb: theme.cursor)
        editor.ghostColor = palette.secondaryText
        editor.hintColor = palette.secondaryText
        editor.selectedTextAttributes = [.backgroundColor: NSColor(rgb: theme.selection)]
        addSubview(editor)
        addSubview(listMenu)
        listMenu.isHidden = true
        listMenu.palette = palette
        listMenu.accent = NSColor(rgb: theme.accent)
        listMenu.onPick = { [weak self] in self?.pickMenuItem($0) }

        editor.onSubmit = { [weak self] in self?.submit($0) }
        editor.onChange = { [weak self] in self?.editorChanged() }
        editor.onArrowUp = { [weak self] in self?.arrowUp() ?? false }
        editor.onArrowDown = { [weak self] in self?.arrowDown() ?? false }
        editor.onEscape = { [weak self] in self?.closeMenu() ?? false }
        editor.onTab = { [weak self] in self?.tabPressed(backward: false) ?? false }
        editor.onBackTab = { [weak self] in self?.tabPressed(backward: true) ?? false }
        editor.onCommandSearch = { [weak self] in self?.openSearch() }
        editor.onRunSelection = { [weak self] in self?.runSelection() ?? false }
        editor.onReturn = { [weak self] in self?.returnPressed() ?? false }
        editor.onCancelInput = { [weak self] in self?.cancelInput() }
        editor.onClearScreen = { [weak self] in self?.onClearScreen?() }
        editor.onFocused = { [weak self] in self?.onFocused?() }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    var isMenuOpen: Bool { mode != .none }
    var menuItems: [String] { listMenu.items.map(\.title) }
    var menuModeName: String { "\(mode)" }
    var selectedMenuItem: Int? { listMenu.selectedIndex }

    func setContext(_ text: String) {
        contextLabel.stringValue = text
    }

    /// The height this bar wants, given the pane height it can grow into.
    func preferredHeight(paneHeight: CGFloat) -> CGFloat {
        let text = min(editor.usedHeight, paneHeight / 2)
        return Self.verticalPadding * 2 + Self.contextHeight + text
    }

    override func layout() {
        super.layout()
        let x = TerminalView.paddingX
        let width = max(0, bounds.width - x * 2)
        contextLabel.frame = NSRect(x: x, y: Self.verticalPadding, width: width, height: Self.contextHeight)
        let top = Self.verticalPadding + Self.contextHeight
        editor.frame = NSRect(x: x, y: top, width: width, height: max(0, bounds.height - top - Self.verticalPadding))
        layoutMenu()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(rgb: theme.background.mixed(with: theme.foreground, 0.14)).setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }

    /// The menu opens upward, outside this view's bounds, over the block list.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if !listMenu.isHidden {
            let local = convert(point, from: superview)
            if listMenu.frame.contains(local) { return listMenu }
        }
        return super.hitTest(point)
    }

    private func submit(_ command: String) {
        closeMenu(restore: false)
        history.add(command)
        onSubmit?(command)
    }

    private func editorChanged() {
        highlight()
        if !isPreviewing {
            switch mode {
            case .completions:
                refreshCompletions()
            case .history:
                closeMenu(restore: false)
            case .search:
                refreshSearch()
            case .none:
                break
            }
        }
        updateGhostText()
        onHeightChange?()
    }

    private func updateGhostText() {
        guard mode == .none, editor.selectedRange().length == 0,
              editor.selectedRange().location == editor.string.utf16.count else {
            editor.ghostText = nil
            return
        }
        let text = editor.string
        editor.ghostText = history.suggestion(for: text).map { String($0.dropFirst(text.count)) }
    }

    private func highlight() {
        guard let manager = editor.layoutManager else { return }
        let length = editor.string.utf16.count
        manager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: length))
        guard mode != .search else { return }
        for token in ShellLexer.tokens(in: editor.string) {
            guard let color = color(for: token.kind) else { continue }
            manager.addTemporaryAttribute(.foregroundColor, value: color,
                                          forCharacterRange: NSRange(location: token.range.lowerBound,
                                                                     length: token.range.count))
        }
    }

    private func color(for kind: ShellLexer.Kind) -> NSColor? {
        switch kind {
        case .command: return NSColor(rgb: theme.ansi[2])
        case .flag: return NSColor(rgb: theme.ansi[6])
        case .string: return NSColor(rgb: theme.ansi[3])
        case .variable: return NSColor(rgb: theme.ansi[5])
        case .comment: return NSColor(rgb: theme.ansi[8])
        case .controlOperator, .redirect: return NSColor(rgb: theme.ansi[4])
        case .unterminated: return NSColor(rgb: theme.ansi[1])
        case .argument: return nil
        }
    }

    // MARK: Menus

    private func show(_ items: [InlineMenuView.Item], mode: MenuMode, selecting index: Int?) {
        self.mode = mode
        listMenu.show(items: items, selecting: index)
        editor.ghostText = nil
        layoutMenu()
        highlight()
    }

    private func layoutMenu() {
        let height = listMenu.preferredHeight
        listMenu.frame = NSRect(x: 0, y: -height, width: bounds.width, height: height)
    }

    @discardableResult
    private func closeMenu(restore: Bool = true) -> Bool {
        guard mode != .none else { return false }
        let closing = mode
        mode = .none
        listMenu.hide()
        if restore && closing != .completions {
            preview(anchorText)
        } else {
            highlight()
        }
        updateGhostText()
        return true
    }

    /// Writes into the input without the menu treating it as typing.
    private func preview(_ text: String) {
        isPreviewing = true
        editor.setText(text)
        isPreviewing = false
    }

    /// Enter submits what's in the input. A highlighted item was already written
    /// there, so this holds for every menu except search, which fills the input.
    private func returnPressed() -> Bool {
        if mode == .search, let item = listMenu.selectedItem {
            closeMenu(restore: false)
            preview(item.title)
            return true
        }
        if mode == .completions, listMenu.selectedIndex != nil {
            acceptSelectedCompletion()
            return true
        }
        return false
    }

    /// Command-Enter runs the highlighted item straight away.
    private func runSelection() -> Bool {
        guard mode != .none else { return false }
        if mode == .search, let item = listMenu.selectedItem {
            preview(item.title)
        }
        closeMenu(restore: false)
        editor.submitCurrentText()
        return true
    }

    private func cancelInput() {
        closeMenu(restore: false)
        editor.setText("")
    }

    private func pickMenuItem(_ index: Int) {
        listMenu.select(index)
        switch mode {
        case .completions:
            previewCompletion(index)
            acceptSelectedCompletion()
        case .history:
            if let item = listMenu.selectedItem { preview(item.title) }
            closeMenu(restore: false)
        case .search:
            _ = returnPressed()
        case .none:
            break
        }
        window?.makeFirstResponder(editor)
    }

    // MARK: History

    /// Up on the first line opens the history menu, filtered by what's typed.
    private func arrowUp() -> Bool {
        switch mode {
        case .none:
            let results = history.matching(prefix: editor.string, limit: 50)
            guard !results.isEmpty else { return false }
            anchorText = editor.string
            show(results.map { .init(title: $0) }, mode: .history, selecting: 0)
            previewMenuSelection()
        case .history, .search:
            // The newest entry sits at the bottom, so up goes further back.
            listMenu.moveSelection(by: 1)
            previewMenuSelection()
        case .completions:
            moveCompletion(by: -1)
        }
        return true
    }

    private func arrowDown() -> Bool {
        switch mode {
        case .none:
            return false
        case .history:
            if listMenu.selectedIndex == 0 {
                closeMenu()
            } else {
                listMenu.moveSelection(by: -1)
                previewMenuSelection()
            }
        case .search:
            listMenu.moveSelection(by: -1)
        case .completions:
            moveCompletion(by: 1)
        }
        return true
    }

    private func previewMenuSelection() {
        guard mode == .history, let item = listMenu.selectedItem else { return }
        preview(item.title)
    }

    // MARK: Command search

    private func openSearch() {
        closeMenu(restore: false)
        anchorText = editor.string
        mode = .search
        refreshSearch()
    }

    private func refreshSearch() {
        let query = editor.string.trimmingCharacters(in: .whitespaces)
        let matches = history.entries.reversed().compactMap { entry -> (String, FuzzyMatcher.Match)? in
            FuzzyMatcher.match(query, in: entry).map { (entry, $0) }
        }
        // An empty query lists history newest first. Otherwise, best match first.
        let ordered = query.isEmpty ? matches : matches.sorted { $0.1.score > $1.1.score }
        show(ordered.prefix(50).map { .init(title: $0.0, matches: Set($0.1.positions)) },
             mode: .search, selecting: ordered.isEmpty ? nil : 0)
    }

    // MARK: Completions

    private func completionResult() -> CompletionResult {
        let context: (directory: String, path: String?, names: [String]) =
            contextProvider?() ?? (ShellLaunch.homeDirectory, nil, [])
        var environment = ProcessInfo.processInfo.environment
        if let path = context.path { environment["PATH"] = path }
        engine.shellNames = context.names
        return engine.complete(line: editor.string, cursor: editor.selectedRange().location,
                               directory: context.directory, environment: environment)
    }

    private func replace(_ range: Range<Int>, with text: String) {
        isPreviewing = true
        editor.setSelectedRange(NSRange(location: range.lowerBound, length: range.count))
        editor.insertText(text, replacementRange: editor.selectedRange())
        isPreviewing = false
    }

    private func tabPressed(backward: Bool) -> Bool {
        if mode == .completions {
            moveCompletion(by: backward ? -1 : 1)
            return true
        }
        closeMenu(restore: false)

        let result = completionResult()
        guard !result.items.isEmpty else { return true }
        if result.items.count == 1 {
            completionRange = result.range
            completions = result.items
            apply(result.items[0])
            return true
        }
        // Fill in what every match shares, then let the user pick the rest.
        var range = result.range
        if result.commonPrefix.utf16.count > range.count {
            replace(range, with: result.commonPrefix)
            range = range.lowerBound..<(range.lowerBound + result.commonPrefix.utf16.count)
        }
        open(result.items, range: range)
        return true
    }

    private func open(_ items: [Completion], range: Range<Int>) {
        completions = items
        completionRange = range
        anchorText = editor.string
        show(items.map { .init(title: $0.text, detail: $0.detail, icon: Self.icon(for: $0.kind)) },
             mode: .completions, selecting: nil)
    }

    private func refreshCompletions() {
        let result = completionResult()
        guard !result.items.isEmpty else {
            closeMenu(restore: false)
            return
        }
        open(result.items, range: result.range)
    }

    private func moveCompletion(by delta: Int) {
        let next: Int
        if let current = listMenu.selectedIndex {
            next = (current + delta + completions.count) % completions.count
        } else {
            next = delta > 0 ? 0 : completions.count - 1
        }
        listMenu.select(next)
        previewCompletion(next)
    }

    /// Choosing an item writes it straight into the input.
    private func previewCompletion(_ index: Int) {
        guard completions.indices.contains(index) else { return }
        let text = completions[index].insertion
        replace(completionRange, with: text)
        completionRange = completionRange.lowerBound..<(completionRange.lowerBound + text.utf16.count)
    }

    private func acceptSelectedCompletion() {
        guard let index = listMenu.selectedIndex, completions.indices.contains(index) else { return }
        apply(completions[index])
    }

    private func apply(_ completion: Completion) {
        replace(completionRange, with: completion.insertion)
        let end = completionRange.lowerBound + completion.insertion.utf16.count
        if completion.appendsSpace {
            editor.setSelectedRange(NSRange(location: end, length: 0))
            replace(end..<end, with: " ")
        }
        closeMenu(restore: false)
    }

    private static func icon(for kind: Completion.Kind) -> String {
        switch kind {
        case .command: return "\u{276F}"
        case .directory: return "\u{25B8}"
        case .file: return "\u{2022}"
        case .flag: return "\u{2013}"
        case .branch, .tag: return "\u{2387}"
        case .host: return "@"
        case .variable: return "$"
        case .script, .subcommand: return "\u{203A}"
        }
    }
}

/// A list that opens above the input, used for history, search and completions.
final class InlineMenuView: NSView {
    struct Item {
        var title: String
        var detail: String?
        var icon: String?
        /// Character offsets in `title` to show in bold.
        var matches: Set<Int> = []
    }

    private static let rowHeight: CGFloat = 24
    private static let maximumRows = 8

    private(set) var items: [Item] = []
    private(set) var selectedIndex: Int?
    private var firstVisible = 0
    var palette = ChromePalette(theme: .dusk)
    var accent = NSColor.systemBlue
    var onPick: ((Int) -> Void)?
    /// Palettes read downward. Menus above the input read upward.
    var startsAtTop = false

    var selectedItem: Item? { selectedIndex.flatMap { items.indices.contains($0) ? items[$0] : nil } }
    var preferredHeight: CGFloat {
        items.isEmpty ? 0 : CGFloat(min(items.count, Self.maximumRows)) * Self.rowHeight + 2
    }

    override var isFlipped: Bool { true }

    func show(items: [Item], selecting index: Int?) {
        self.items = items
        selectedIndex = index
        firstVisible = 0
        isHidden = items.isEmpty
        needsDisplay = true
    }

    func hide() {
        isHidden = true
        items = []
        selectedIndex = nil
    }

    func select(_ index: Int) {
        selectedIndex = index
        keepSelectionVisible()
        needsDisplay = true
    }

    func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        select(min(max((selectedIndex ?? -1) + delta, 0), items.count - 1))
    }

    private func keepSelectionVisible() {
        guard let selected = selectedIndex else { return }
        let visible = min(items.count, Self.maximumRows)
        if selected < firstVisible { firstVisible = selected }
        if selected >= firstVisible + visible { firstVisible = selected - visible + 1 }
    }

    /// Item 0 sits nearest the input, so the list reads upward.
    private func rowRect(_ index: Int) -> NSRect {
        let row = index - firstVisible
        let y = startsAtTop ? CGFloat(row) * Self.rowHeight : bounds.height - CGFloat(row + 1) * Self.rowHeight
        return NSRect(x: 0, y: y, width: bounds.width, height: Self.rowHeight)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let visible = min(items.count, Self.maximumRows)
        for index in firstVisible..<(firstVisible + visible) where rowRect(index).contains(point) {
            onPick?(index)
            return
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        palette.chrome.setFill()
        bounds.fill()
        palette.divider.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()

        let visible = min(items.count, Self.maximumRows)
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let bold = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        let leading = TerminalView.paddingX

        for index in firstVisible..<(firstVisible + visible) {
            let item = items[index]
            let rect = rowRect(index)
            if index == selectedIndex {
                palette.hover.setFill()
                rect.fill()
            }

            var x = leading
            if let icon = item.icon {
                (icon as NSString).draw(at: NSPoint(x: x, y: rect.minY + 4), withAttributes: [
                    .font: font, .foregroundColor: palette.secondaryText,
                ])
                x += 18
            }

            let line = item.title.replacingOccurrences(of: "\n", with: " ")
            let text = NSMutableAttributedString(string: line, attributes: [.font: font, .foregroundColor: palette.text])
            for offset in item.matches where offset < text.length {
                text.addAttributes([.font: bold, .foregroundColor: accent], range: NSRange(location: offset, length: 1))
            }
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))
            let detailWidth: CGFloat = item.detail == nil ? 0 : min(bounds.width * 0.5, 320)
            text.draw(in: NSRect(x: x, y: rect.minY + 4, width: bounds.width - x - leading - detailWidth, height: 18))

            if let detail = item.detail {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font, .foregroundColor: palette.secondaryText, .paragraphStyle: paragraph,
                ]
                (detail as NSString).draw(
                    in: NSRect(x: bounds.width - leading - detailWidth, y: rect.minY + 4, width: detailWidth, height: 18),
                    withAttributes: attributes)
            }
        }
    }
}
