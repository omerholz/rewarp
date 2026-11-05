import AppKit
import RewarpCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let theme = Theme.dusk
    private var controllers: [TerminalWindowController] = []
    private var control: ControlChannel?
    private var tabPosition = TabBarPosition.saved
    private let fonts = FontLibrary(pointSize: 13)
    private lazy var history: CommandHistory = {
        let environment = ProcessInfo.processInfo.environment
        return CommandHistory(entries: ShellHistoryFile.load(
            shell: ShellLaunch.userShell(), environment: environment,
            home: ShellLaunch.homeDirectory))
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make(target: self)
        installKeyRouter()
        newWindow()
        if !DebugScript.isAutomated { NSApp.activate(ignoringOtherApps: true) }

        if let pane = controllers.first?.focusedPane {
            DebugScript.runIfRequested(view: pane.terminal, session: pane.session)
        }
        if let path = ProcessInfo.processInfo.environment["REWARP_CONTROL"] {
            let channel = ControlChannel(
                path: path,
                window: { [weak self] in self?.current?.window },
                pane: { [weak self] in self?.current?.focusedPane },
                controller: { [weak self] in self?.current })
            channel.start()
            control = channel
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// The text system claims keys like Option-arrow before the menu sees them, so
    /// shortcuts in the menu get first refusal on modified keys, unless a running
    /// program owns the keyboard.
    private func installKeyRouter() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            AppDelegate.routeToMenu(event) ? nil : event
        }
    }

    static func routeToMenu(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.option, .control, .shift])
        guard !modifiers.isEmpty, !event.modifierFlags.contains(.command) else { return false }
        // Control-Tab can't be a menu key equivalent, so it's handled here.
        if event.keyCode == 48, modifiers.contains(.control), let delegate = NSApp.delegate as? AppDelegate {
            modifiers.contains(.shift) ? delegate.previousTab() : delegate.nextTab()
            return true
        }
        if let terminal = event.window?.firstResponder as? TerminalView, terminal.keysGoToProgram { return false }
        return NSApp.mainMenu?.performKeyEquivalent(with: event) == true
    }

    private var current: TerminalWindowController? {
        controllers.first { $0.window?.isKeyWindow == true } ?? controllers.last
    }

    @objc func newWindow() {
        let controller = TerminalWindowController(theme: theme, fonts: fonts, history: history)
        controller.onClose = { [weak self] closed in
            self?.controllers.removeAll { $0 === closed }
        }
        controllers.append(controller)
        // Automated runs stay invisible, so they don't flash over the user's work.
        if DebugScript.isAutomated, !DebugScript.isVisible { controller.window?.alphaValue = 0 }
        controller.showWindow(nil)
        controller.newTab(directory: ShellLaunch.homeDirectory)
    }

    @objc func newTab() { current?.newTab() }
    @objc func reopenClosedTab() { current?.reopenClosedTab() }
    @objc func splitRight() { current?.split(.horizontal) }
    @objc func splitDown() { current?.split(.vertical) }
    @objc func closePane() { current?.closeFocusedPane() }
    @objc func previousTab() { current?.selectNextTab(forward: false) }
    @objc func nextTab() { current?.selectNextTab(forward: true) }
    @objc func moveTabLeft() { current?.moveTab(by: -1) }
    @objc func moveTabRight() { current?.moveTab(by: 1) }
    @objc func selectTab(_ sender: NSMenuItem) { current?.select(tab: sender.tag) }
    @objc func selectLastTab() { current?.selectLastTab() }
    @objc func previousPane() { current?.cyclePane(forward: false) }
    @objc func nextPane() { current?.cyclePane(forward: true) }
    @objc func focusLeft() { current?.focusPane(.left) }
    @objc func focusRight() { current?.focusPane(.right) }
    @objc func focusUp() { current?.focusPane(.up) }
    @objc func focusDown() { current?.focusPane(.down) }
    @objc func resizeLeft() { current?.resizePane(.left) }
    @objc func resizeRight() { current?.resizePane(.right) }
    @objc func resizeUp() { current?.resizePane(.up) }
    @objc func resizeDown() { current?.resizePane(.down) }
    @objc func toggleZoom() { current?.toggleZoom() }

    private var focusedTerminal: TerminalView? { current?.focusedPane?.terminal }

    @objc func selectPreviousBlock() { focusedTerminal?.selectAdjacentBlock(up: true) }
    @objc func selectNextBlock() { focusedTerminal?.selectAdjacentBlock(up: false) }
    @objc func bookmarkUp() { focusedTerminal?.jumpToBookmark(up: true) }
    @objc func bookmarkDown() { focusedTerminal?.jumpToBookmark(up: false) }
    @objc func scrollToBlockTop() { focusedTerminal?.scrollToEdge(ofSelectedBlock: true) }
    @objc func scrollToBlockBottom() { focusedTerminal?.scrollToEdge(ofSelectedBlock: false) }
    @objc func copyCommand() { focusedTerminal?.copyBlockCommand(nil) }
    @objc func copyOutput() { focusedTerminal?.copyBlockOutput(nil) }
    @objc func bookmarkBlock() { focusedTerminal?.toggleBookmark(nil) }
    @objc func reinputBlock() { focusedTerminal?.reinputBlocks(nil) }
    @objc func reinputBlockAsRoot() { focusedTerminal?.reinputBlocksAsRoot(nil) }
    @objc func clearBlocks() { focusedTerminal?.clearBlocks(nil) }
    @objc func focusInput() { current?.focusedPane?.focusInput() }
    @objc func renameTab() { current?.renameActiveTab() }
    @objc func closeTab() { current?.closeActiveTab() }
    @objc func closeOtherTabs() { current.map { $0.closeOtherTabs(than: $0.selectedTabIndex) } }
    @objc func closeTabsToTheRight() { current.map { $0.closeTabs(rightOf: $0.selectedTabIndex) } }
    @objc func tabBarTop() { setTabPosition(.top) }
    @objc func tabBarLeft() { setTabPosition(.left) }
    @objc func tabBarRight() { setTabPosition(.right) }

    func setTabPosition(_ position: TabBarPosition) {
        TabBarPosition.saved = position
        tabPosition = position
        controllers.forEach { $0.setTabPosition(position) }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(tabBarTop): item.state = tabPosition == .top ? .on : .off
        case #selector(tabBarLeft): item.state = tabPosition == .left ? .on : .off
        case #selector(tabBarRight): item.state = tabPosition == .right ? .on : .off
        default: break
        }
        return true
    }

    @objc func commandPalette() { current?.toggleCommandPalette() }
    @objc func navigationPalette() { current?.toggleNavigationPalette() }
    @objc func find() { current?.focusedPane?.openFind() }
    @objc func findNext() { current?.focusedPane?.findNext(forward: true) }
    @objc func findPrevious() { current?.focusedPane?.findNext(forward: false) }
    @objc func toggleBlockFilter() { current?.focusedPane?.toggleFilter() }
    @objc func toggleStickyHeader() {
        guard let terminal = focusedTerminal else { return }
        terminal.stickyHeaderEnabled.toggle()
        terminal.session.requestFrame()
    }
}
