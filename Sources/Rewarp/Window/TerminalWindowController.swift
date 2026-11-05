import AppKit
import RewarpCore

/// One tab: its panes and how they're arranged.
final class Tab {
    let content: PaneContainerView
    var focused: PaneID
    /// Set by renaming, and kept whichever pane is focused.
    var customTitle: String?

    init(pane: PaneView, id: PaneID, dividerColor: NSColor) {
        content = PaneContainerView(tree: .pane(id), dividerColor: dividerColor)
        content.add(pane, id: id)
        focused = id
    }

    var focusedPane: PaneView { content.pane(focused)! }
    var panes: [PaneView] { content.orderedPanes }
    var isMaximized: Bool { content.maximized != nil }
    var title: String { customTitle ?? focusedPane.title }
}

/// A menu item that runs a closure, for menus built on the fly.
final class ClosureMenuItem: NSMenuItem {
    private let run: () -> Void

    init(title: String, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(runClosure), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func runClosure() {
        run()
    }
}

final class TerminalWindowController: NSWindowController, NSWindowDelegate {
    static let contentMinimumSize = NSSize(width: 420, height: 260)

    private let theme: Theme
    private let palette: ChromePalette
    private let tabBar = TabBarView()
    private let titleStrip = TitleStripView()
    private let container = NSView()
    private var position = TabBarPosition.saved
    private var sidebarWidth: CGFloat = 220
    private static let sidebarWidths: ClosedRange<CGFloat> = 150...420
    private lazy var paletteView = PaletteView(theme: theme)
    private var paletteName = ""

    private let fonts: FontLibrary
    private let history: CommandHistory
    private var tabs: [Tab] = []
    private var selectedIndex = 0
    private var closedDirectories: [String] = []
    private var paneCounter = 0

    var onClose: ((TerminalWindowController) -> Void)?

    init(theme: Theme, fonts: FontLibrary, history: CommandHistory) {
        self.theme = theme
        self.fonts = fonts
        self.history = history
        palette = ChromePalette(theme: theme)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = palette.chrome
        window.minSize = Self.contentMinimumSize
        window.tabbingMode = .disallowed
        window.isRestorable = false
        window.center()

        super.init(window: window)
        window.delegate = self

        let content = NSView()
        window.contentView = content
        content.addSubview(titleStrip)
        content.addSubview(tabBar)
        content.addSubview(container)
        container.wantsLayer = true
        titleStrip.color = palette.chrome
        tabBar.position = position
        layoutChrome()

        tabBar.palette = palette
        tabBar.onSelect = { [weak self] in self?.select(tab: $0) }
        tabBar.onClose = { [weak self] in self?.close(tab: $0) }
        tabBar.onNewTab = { [weak self] in self?.newTab() }
        tabBar.onMove = { [weak self] in self?.moveTab(from: $0, to: $1) }
        tabBar.onRename = { [weak self] index, title in self?.rename(tab: index, to: title) }
        tabBar.onRenameEnded = { [weak self] in self?.activeTab?.focusedPane.focusInput() }
        tabBar.onResizeSidebar = { [weak self] in self?.setSidebar(width: $0) }
        tabBar.makeMenu = { [weak self] in self?.makeTabMenu(for: $0) ?? NSMenu() }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func layoutChrome() {
        guard let content = window?.contentView else { return }
        let bounds = content.bounds
        switch position {
        case .top:
            titleStrip.isHidden = true
            tabBar.frame = NSRect(x: 0, y: bounds.height - TabBarView.height, width: bounds.width, height: TabBarView.height)
            container.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - TabBarView.height)
        case .left, .right:
            titleStrip.isHidden = false
            let strip = TitleStripView.height
            let height = bounds.height - strip
            titleStrip.frame = NSRect(x: 0, y: height, width: bounds.width, height: strip)
            let width = min(sidebarWidth, bounds.width - 240)
            let isLeft = position == .left
            tabBar.frame = NSRect(x: isLeft ? 0 : bounds.width - width, y: 0, width: width, height: height)
            container.frame = NSRect(x: isLeft ? width : 0, y: 0, width: bounds.width - width, height: height)
        }
        tabBar.needsDisplay = true
    }

    func setTabPosition(_ newPosition: TabBarPosition) {
        guard newPosition != position else { return }
        position = newPosition
        tabBar.position = newPosition
        layoutChrome()
        layoutActiveTab()
        refreshTabBar()
    }

    private func setSidebar(width: CGFloat) {
        sidebarWidth = min(max(width, Self.sidebarWidths.lowerBound), Self.sidebarWidths.upperBound)
        layoutChrome()
        layoutActiveTab()
    }

    func windowDidResize(_ notification: Notification) {
        layoutChrome()
        layoutActiveTab()
    }

    func windowWillClose(_ notification: Notification) {
        for tab in tabs {
            for pane in tab.panes { pane.session.terminate() }
        }
        // Leaving the window is what ends a pane's display link, which otherwise
        // keeps the pane alive for good.
        container.subviews.forEach { $0.removeFromSuperview() }
        onClose?(self)
    }

    private var activeTab: Tab? {
        tabs.indices.contains(selectedIndex) ? tabs[selectedIndex] : nil
    }

    private var defaultDirectory: String {
        activeTab?.focusedPane.session.currentDirectory ?? ShellLaunch.homeDirectory
    }

    // MARK: Panes

    private func nextPaneID() -> PaneID {
        paneCounter += 1
        return PaneID(paneCounter)
    }

    private func makePane(directory: String) -> PaneView {
        let pane = PaneView(theme: theme, fonts: fonts, scale: window?.backingScaleFactor ?? 2,
                            workingDirectory: directory, history: history)
        pane.onFocus = { [weak self] in self?.paneFocused($0) }
        pane.onTitleChange = { [weak self] _ in self?.refreshTabBar() }
        pane.onExit = { [weak self] in self?.remove(pane: $0) }
        pane.onClosePane = { [weak self] in self?.remove(pane: $0) }
        pane.onSplit = { [weak self] in self?.split($0) }
        pane.onToggleZoom = { [weak self] in self?.toggleZoom() }
        return pane
    }

    private func paneFocused(_ pane: PaneView) {
        guard let tab = tabs.first(where: { $0.content.id(of: pane) != nil }),
              let id = tab.content.id(of: pane) else { return }
        tab.focused = id
        refreshTabBar()
    }

    func split(_ axis: SplitAxis) {
        guard let tab = activeTab else { return }
        tab.content.maximized = nil
        let id = nextPaneID()
        let pane = makePane(directory: tab.focusedPane.session.currentDirectory)
        tab.content.add(pane, id: id)
        tab.content.tree = tab.content.tree.splitting(tab.focused, axis: axis, adding: id)
        layoutActiveTab()
        pane.start()
        focus(id, in: tab)
    }

    private func focus(_ id: PaneID, in tab: Tab) {
        // A hidden pane must never hold the keyboard.
        if let maximized = tab.content.maximized, maximized != id {
            tab.content.maximized = nil
            tab.content.layoutSubtreeIfNeeded()
        }
        tab.focused = id
        tab.focusedPane.focusInput()
    }

    func closeFocusedPane() {
        guard let tab = activeTab else { return }
        remove(pane: tab.focusedPane)
    }

    private func remove(pane: PaneView) {
        guard let tabIndex = tabs.firstIndex(where: { $0.content.id(of: pane) != nil }),
              let id = tabs[tabIndex].content.id(of: pane) else { return }
        let tab = tabs[tabIndex]
        pane.session.terminate()

        guard let remaining = tab.content.tree.removing(id) else {
            closedDirectories.append(pane.session.currentDirectory)
            removeTab(at: tabIndex)
            return
        }
        tab.content.maximized = tab.content.maximized == id ? nil : tab.content.maximized
        tab.content.remove(id)
        tab.content.tree = remaining
        if tab.focused == id, let first = remaining.paneIDs.first { tab.focused = first }
        layoutActiveTab()
        if tabIndex == selectedIndex { focus(tab.focused, in: tab) }
        refreshTabBar()
    }

    func focusPane(_ direction: PaneDirection) {
        guard let tab = activeTab, !tab.isMaximized else { return }
        if let id = tab.content.tree.neighbor(of: tab.focused, direction, in: tab.content.bounds) {
            focus(id, in: tab)
        }
    }

    func cyclePane(forward: Bool) {
        guard let tab = activeTab else { return }
        let ids = tab.content.tree.paneIDs
        guard ids.count > 1, let index = ids.firstIndex(of: tab.focused) else { return }
        focus(ids[(index + (forward ? 1 : ids.count - 1)) % ids.count], in: tab)
    }

    func resizePane(_ direction: PaneDirection) {
        guard let tab = activeTab else { return }
        tab.content.tree = tab.content.tree.resizing(tab.focused, direction, by: 0.03)
    }

    func toggleZoom() {
        guard let tab = activeTab, tab.panes.count > 1 else { return }
        tab.content.maximized = tab.isMaximized ? nil : tab.focused
        focus(tab.focused, in: tab)
    }

    // MARK: Tabs

    /// New tabs open beside the current one, not at the far end.
    func newTab(directory: String? = nil) {
        let pane = makePane(directory: directory ?? defaultDirectory)
        let index = tabs.isEmpty ? 0 : selectedIndex + 1
        tabs.insert(Tab(pane: pane, id: nextPaneID(), dividerColor: palette.divider), at: index)
        select(tab: index)
        pane.start()
    }

    func select(tab index: Int) {
        guard tabs.indices.contains(index) else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        selectedIndex = index
        let tab = tabs[index]
        container.addSubview(tab.content)
        layoutActiveTab()
        focus(tab.focused, in: tab)
        refreshTabBar()
    }

    func selectNextTab(forward: Bool) {
        guard !tabs.isEmpty else { return }
        select(tab: (selectedIndex + (forward ? 1 : tabs.count - 1)) % tabs.count)
    }

    func selectLastTab() {
        select(tab: tabs.count - 1)
    }

    func close(tab index: Int) {
        guard tabs.indices.contains(index) else { return }
        for pane in tabs[index].panes {
            pane.session.terminate()
            closedDirectories.append(pane.session.currentDirectory)
        }
        removeTab(at: index)
    }

    func closeActiveTab() {
        close(tab: selectedIndex)
    }

    func closeOtherTabs(than index: Int) {
        guard tabs.indices.contains(index) else { return }
        let kept = tabs[index]
        for tab in tabs where tab !== kept {
            closedDirectories.append(tab.focusedPane.session.currentDirectory)
            tab.panes.forEach { $0.session.terminate() }
        }
        tabs = [kept]
        selectedIndex = 0
        select(tab: 0)
    }

    func closeTabs(rightOf index: Int) {
        guard tabs.indices.contains(index) else { return }
        for tab in tabs[(index + 1)...] {
            closedDirectories.append(tab.focusedPane.session.currentDirectory)
            tab.panes.forEach { $0.session.terminate() }
        }
        let selected = tabs[min(selectedIndex, index)]
        tabs.removeSubrange((index + 1)...)
        select(tab: tabs.firstIndex { $0 === selected } ?? index)
    }

    var selectedTabIndex: Int { selectedIndex }

    func renameActiveTab() {
        tabBar.beginRename(selectedIndex)
    }

    private func rename(tab index: Int, to title: String) {
        guard tabs.indices.contains(index) else { return }
        tabs[index].customTitle = title.isEmpty ? nil : title
        refreshTabBar()
    }

    private func makeTabMenu(for index: Int) -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, enabled: Bool = true, _ run: @escaping () -> Void) {
            let item = ClosureMenuItem(title: title, run: run)
            item.isEnabled = enabled
            menu.addItem(item)
        }
        menu.autoenablesItems = false
        add("Rename Tab") { [weak self] in self?.tabBar.beginRename(index) }
        menu.addItem(.separator())
        add("Close Tab") { [weak self] in self?.close(tab: index) }
        add("Close Other Tabs", enabled: tabs.count > 1) { [weak self] in self?.closeOtherTabs(than: index) }
        add("Close Tabs to the Right", enabled: index < tabs.count - 1) { [weak self] in self?.closeTabs(rightOf: index) }
        menu.addItem(.separator())
        add("Tab Bar on Top") { [weak self] in self?.applyPositionEverywhere(.top) }
        add("Tab Bar on Left") { [weak self] in self?.applyPositionEverywhere(.left) }
        add("Tab Bar on Right") { [weak self] in self?.applyPositionEverywhere(.right) }
        return menu
    }

    private func applyPositionEverywhere(_ position: TabBarPosition) {
        (NSApp.delegate as? AppDelegate)?.setTabPosition(position)
    }

    func reopenClosedTab() {
        guard let directory = closedDirectories.popLast() else { return }
        newTab(directory: directory)
    }

    private func removeTab(at index: Int) {
        tabs.remove(at: index)
        if tabs.isEmpty {
            window?.close()
            return
        }
        select(tab: min(index >= selectedIndex ? selectedIndex : selectedIndex - 1, tabs.count - 1))
    }

    func moveTab(by offset: Int) {
        moveTab(from: selectedIndex, to: selectedIndex + offset)
    }

    private func moveTab(from source: Int, to destination: Int) {
        guard tabs.indices.contains(source), tabs.indices.contains(destination) else { return }
        let selected = tabs[selectedIndex]
        tabs.insert(tabs.remove(at: source), at: destination)
        selectedIndex = tabs.firstIndex { $0 === selected } ?? 0
        refreshTabBar()
    }

    private func layoutActiveTab() {
        guard let view = activeTab?.content else { return }
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
    }

    private func refreshTabBar() {
        tabBar.items = tabs.map { .init(title: $0.title, subtitle: $0.focusedPane.contextText) }
        tabBar.selected = selectedIndex
        window?.title = activeTab?.title ?? "Rewarp"
    }

    // MARK: Palettes

    func toggleCommandPalette() {
        togglePalette(named: "commands", placeholder: "Search actions", entries: MainMenu.paletteEntries())
    }

    func toggleNavigationPalette() {
        var entries: [PaletteView.Entry] = []
        for (tabIndex, tab) in tabs.enumerated() {
            for pane in tab.panes {
                let label = tabIndex == selectedIndex && pane === tab.focusedPane ? "Current" : "Tab \(tabIndex + 1)"
                let id = tab.content.id(of: pane)
                entries.append(.init(title: pane.title, detail: label) { [weak self, weak tab] in
                    guard let self, let tab, let id, let index = self.tabs.firstIndex(where: { $0 === tab }) else { return }
                    self.select(tab: index)
                    self.focus(id, in: tab)
                })
            }
        }
        togglePalette(named: "sessions", placeholder: "Search sessions", entries: entries)
    }

    private func togglePalette(named name: String, placeholder: String, entries: [PaletteView.Entry]) {
        guard let content = window?.contentView else { return }
        if paletteView.superview == nil { content.addSubview(paletteView) }
        if paletteView.isOpen {
            let wasSame = paletteName == name
            paletteView.close()
            if wasSame { return }
        }
        paletteName = name
        paletteView.open(entries: entries, placeholder: placeholder, in: content)
    }

    var debugPaletteOpen: Bool { paletteView.isOpen }
    var debugPaletteName: String { paletteView.isOpen ? paletteName : "" }
    var debugPaletteItems: [String] { paletteView.isOpen ? paletteView.itemTitles : [] }

    func debugTypeIntoPalette(_ text: String) {
        paletteView.type(text)
    }

    var focusedPane: PaneView? { activeTab?.focusedPane }
    var debugTabCount: Int { tabs.count }
    var debugTabTitles: [String] { tabs.map(\.title) }
    var debugTabPosition: String { position.rawValue }
    var debugIsRenaming: Bool { tabBar.isRenaming }

    /// Each tab's frame in points from the top-left of the window's content.
    var debugTabFrames: [[CGFloat]] {
        guard let content = window?.contentView else { return [] }
        return tabs.indices.map { index in
            let rect = tabBar.convert(tabBar.tabRect(index), to: content)
            return [rect.minX, content.bounds.height - rect.maxY, rect.width, rect.height]
        }
    }
    var debugPaneCount: Int { activeTab?.panes.count ?? 0 }
}
