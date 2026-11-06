import AppKit

/// The menu bar. Warp's default shortcuts live here, so that AppKit routes them
/// before the terminal view ever sees the key.
enum MainMenu {
    static func make(target: AppDelegate) -> NSMenu {
        let bar = NSMenu()

        func menu(_ title: String, _ items: [NSMenuItem]) {
            let holder = NSMenuItem()
            let submenu = NSMenu(title: title)
            items.forEach(submenu.addItem)
            holder.submenu = submenu
            bar.addItem(holder)
        }

        func item(_ title: String, _ action: Selector, _ key: String, _ modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.target = target
            return item
        }

        func arrow(_ value: Int) -> String {
            String(UnicodeScalar(value)!)
        }

        let left = arrow(NSLeftArrowFunctionKey)
        let right = arrow(NSRightArrowFunctionKey)
        let up = arrow(NSUpArrowFunctionKey)
        let down = arrow(NSDownArrowFunctionKey)

        let about = NSMenuItem(title: "About Rewarp", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        let quit = NSMenuItem(title: "Quit Rewarp", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let hide = NSMenuItem(title: "Hide Rewarp", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        menu("Rewarp", [about, .separator(), hide, .separator(), quit])

        menu("File", [
            item("New Window", #selector(AppDelegate.newWindow), "n"),
            item("New Tab", #selector(AppDelegate.newTab), "t"),
            item("Reopen Closed Tab", #selector(AppDelegate.reopenClosedTab), "T", [.command, .shift]),
            .separator(),
            item("Split Pane Right", #selector(AppDelegate.splitRight), "d"),
            item("Split Pane Down", #selector(AppDelegate.splitDown), "D", [.command, .shift]),
            .separator(),
            item("Close", #selector(AppDelegate.closePane), "w"),
        ])

        let copy = NSMenuItem(title: "Copy", action: #selector(TerminalView.copy(_:)), keyEquivalent: "c")
        let paste = NSMenuItem(title: "Paste", action: #selector(TerminalView.paste(_:)), keyEquivalent: "v")
        let cut = NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        let undo = NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        let selectAll = NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu("Edit", [undo, redo, .separator(), cut, copy, paste, selectAll])

        menu("View", [
            item("Command Palette", #selector(AppDelegate.commandPalette), "p"),
            item("Navigation Palette", #selector(AppDelegate.navigationPalette), "P", [.command, .shift]),
            .separator(),
            item("Find", #selector(AppDelegate.find), "f"),
            item("Find Next", #selector(AppDelegate.findNext), "g"),
            item("Find Previous", #selector(AppDelegate.findPrevious), "G", [.command, .shift]),
            item("Toggle Block Filter", #selector(AppDelegate.toggleBlockFilter), "F", [.option, .shift]),
            .separator(),
            item("Toggle Sticky Command Header", #selector(AppDelegate.toggleStickyHeader), "s", [.control]),
            .separator(),
            item("Tab Bar on Top", #selector(AppDelegate.tabBarTop), ""),
            item("Tab Bar on Left", #selector(AppDelegate.tabBarLeft), ""),
            item("Tab Bar on Right", #selector(AppDelegate.tabBarRight), ""),
        ])

        menu("Blocks", [
            item("Select Previous Block", #selector(AppDelegate.selectPreviousBlock), up),
            item("Select Next Block", #selector(AppDelegate.selectNextBlock), down),
            item("Previous Bookmark", #selector(AppDelegate.bookmarkUp), up, [.option]),
            item("Next Bookmark", #selector(AppDelegate.bookmarkDown), down, [.option]),
            item("Scroll to Top of Block", #selector(AppDelegate.scrollToBlockTop), up, [.command, .shift]),
            item("Scroll to Bottom of Block", #selector(AppDelegate.scrollToBlockBottom), down, [.command, .shift]),
            .separator(),
            item("Copy Command", #selector(AppDelegate.copyCommand), "C", [.command, .shift]),
            item("Copy Output", #selector(AppDelegate.copyOutput), "C", [.command, .shift, .option]),
            item("Toggle Bookmark", #selector(AppDelegate.bookmarkBlock), "b"),
            item("Reinput", #selector(AppDelegate.reinputBlock), "i"),
            item("Reinput as Root", #selector(AppDelegate.reinputBlockAsRoot), "I", [.command, .shift]),
            .separator(),
            item("Clear Blocks", #selector(AppDelegate.clearBlocks), "k"),
            item("Focus Terminal Input", #selector(AppDelegate.focusInput), "l"),
        ])

        var tabItems: [NSMenuItem] = [
            item("Previous Tab", #selector(AppDelegate.previousTab), "{", [.command, .shift]),
            item("Next Tab", #selector(AppDelegate.nextTab), "}", [.command, .shift]),
            item("Move Tab Left", #selector(AppDelegate.moveTabLeft), left, [.control, .shift]),
            item("Move Tab Right", #selector(AppDelegate.moveTabRight), right, [.control, .shift]),
            item("Rename Tab", #selector(AppDelegate.renameTab), ""),
            item("Close Tab", #selector(AppDelegate.closeTab), ""),
            item("Close Other Tabs", #selector(AppDelegate.closeOtherTabs), ""),
            item("Close Tabs to the Right", #selector(AppDelegate.closeTabsToTheRight), ""),
            .separator(),
        ]
        for number in 1...8 {
            let entry = item("Tab \(number)", #selector(AppDelegate.selectTab(_:)), "\(number)")
            entry.tag = number - 1
            tabItems.append(entry)
        }
        tabItems.append(item("Last Tab", #selector(AppDelegate.selectLastTab), "9"))
        menu("Tabs", tabItems)

        menu("Panes", [
            item("Previous Pane", #selector(AppDelegate.previousPane), "["),
            item("Next Pane", #selector(AppDelegate.nextPane), "]"),
            .separator(),
            item("Switch Pane Left", #selector(AppDelegate.focusLeft), left, [.command, .option]),
            item("Switch Pane Right", #selector(AppDelegate.focusRight), right, [.command, .option]),
            item("Switch Pane Up", #selector(AppDelegate.focusUp), up, [.command, .option]),
            item("Switch Pane Down", #selector(AppDelegate.focusDown), down, [.command, .option]),
            .separator(),
            item("Move Divider Left", #selector(AppDelegate.resizeLeft), left, [.command, .control]),
            item("Move Divider Right", #selector(AppDelegate.resizeRight), right, [.command, .control]),
            item("Move Divider Up", #selector(AppDelegate.resizeUp), up, [.command, .control]),
            item("Move Divider Down", #selector(AppDelegate.resizeDown), down, [.command, .control]),
            .separator(),
            item("Toggle Maximize Pane", #selector(AppDelegate.toggleZoom), "\r", [.command, .shift]),
        ])

        let window = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        window.submenu = windowMenu
        bar.addItem(window)
        NSApp.windowsMenu = windowMenu

        return bar
    }

    /// Every menu command, for the command palette, so that a new menu item shows
    /// up there without any extra work.
    static func paletteEntries() -> [PaletteView.Entry] {
        var entries: [PaletteView.Entry] = []
        for holder in NSApp.mainMenu?.items.dropFirst() ?? [] {
            for item in holder.submenu?.items ?? [] where !item.isSeparatorItem && !item.title.hasPrefix("Tab ") {
                guard let action = item.action, item.target != nil else { continue }
                entries.append(.init(title: item.title, detail: shortcut(of: item)) { [weak item] in
                    guard let item else { return }
                    NSApp.sendAction(action, to: item.target, from: item)
                })
            }
        }
        return entries
    }

    private static func shortcut(of item: NSMenuItem) -> String? {
        guard !item.keyEquivalent.isEmpty else { return nil }
        var text = ""
        let mods = item.keyEquivalentModifierMask
        if mods.contains(.control) { text += "\u{2303}" }
        if mods.contains(.option) { text += "\u{2325}" }
        if mods.contains(.shift) { text += "\u{21E7}" }
        if mods.contains(.command) { text += "\u{2318}" }
        let key: String
        switch Int(item.keyEquivalent.utf16.first ?? 0) {
        case NSUpArrowFunctionKey: key = "\u{2191}"
        case NSDownArrowFunctionKey: key = "\u{2193}"
        case NSLeftArrowFunctionKey: key = "\u{2190}"
        case NSRightArrowFunctionKey: key = "\u{2192}"
        case 13: key = "\u{21A9}"
        default: key = item.keyEquivalent.uppercased()
        }
        return text + key
    }
}
