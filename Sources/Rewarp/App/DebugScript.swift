import AppKit
import RewarpCore

/// Where copies go. Automated runs use a private pasteboard so that they never
/// touch the user's clipboard.
enum Clipboard {
    static var pasteboard: NSPasteboard = .general

    static func write(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    static func read() -> String? {
        pasteboard.string(forType: .string)
    }
}

/// Scripted runs for checks that need the real app. Nothing here is active unless
/// the environment asks for it.
///
/// REWARP_SEND     a command to run once the shell is ready
/// REWARP_CAPTURE  PNG path written after REWARP_WAIT seconds, then the app quits
/// REWARP_STATS    file that receives frame timing, one line per second
/// REWARP_CONTROL  a FIFO of commands for end-to-end tests, see `ControlChannel`
enum DebugScript {
    static var isAutomated: Bool {
        ProcessInfo.processInfo.environment["REWARP_CONTROL"] != nil
    }

    /// An automated run that should still be seen, for visual checks.
    static var isVisible: Bool {
        ProcessInfo.processInfo.environment["REWARP_VISIBLE"] != nil
    }

    static func runIfRequested(view: TerminalView, session: PaneSession) {
        let env = ProcessInfo.processInfo.environment
        let wait = env["REWARP_WAIT"].flatMap(Double.init) ?? 2

        // Held for the prompt like any other command, because a shell that's still
        // starting can swallow what's written to it.
        if let text = env["REWARP_SEND"] {
            session.submit(command: text)
        }
        if let path = env["REWARP_STATS"] {
            FrameStats.shared.start(writingTo: path)
        }
        if let path = env["REWARP_CAPTURE"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1 + wait) {
                view.capture(to: path)
                NSApp.terminate(nil)
            }
        }
    }
}

/// Drives the app from a test process. Input arrives as synthesized NSEvents sent
/// through the window, so tests exercise the same responder chain as a real user.
/// Each command writes its reply to `<fifo>.reply`.
final class ControlChannel {
    private let path: String
    private let window: () -> NSWindow?
    private let pane: () -> PaneView?
    private let controller: () -> TerminalWindowController?
    private var buffer = Data()
    private var source: DispatchSourceRead?
    private var eventNumber = 0

    init(path: String,
         window: @escaping () -> NSWindow?,
         pane: @escaping () -> PaneView?,
         controller: @escaping () -> TerminalWindowController?) {
        self.path = path
        self.window = window
        self.pane = pane
        self.controller = controller
    }

    func start() {
        Clipboard.pasteboard = NSPasteboard(name: NSPasteboard.Name("dev.rewarp.tests.\(getpid())"))
        // Opened read-write so the FIFO always has a writer and never reports EOF.
        let descriptor = open(path, O_RDWR | O_NONBLOCK)
        guard descriptor >= 0 else { fatalError("could not open \(path)") }
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: .main)
        source.setEventHandler { [weak self] in
            var chunk = [UInt8](repeating: 0, count: 65536)
            let count = read(descriptor, &chunk, chunk.count)
            guard count > 0, let self else { return }
            self.buffer.append(contentsOf: chunk[..<count])
            while let newline = self.buffer.firstIndex(of: 0x0A) {
                let line = self.buffer[self.buffer.startIndex..<newline]
                self.buffer.removeSubrange(self.buffer.startIndex...newline)
                self.handle(String(decoding: line, as: UTF8.self))
            }
        }
        source.resume()
        self.source = source
    }

    private func reply(_ text: String) {
        try? text.write(toFile: path + ".reply.tmp", atomically: false, encoding: .utf8)
        rename(path + ".reply.tmp", path + ".reply")
    }

    private func handle(_ line: String) {
        guard let data = line.data(using: .utf8),
              let command = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let name = command["cmd"] as? String else {
            reply("{\"error\":\"bad command\"}")
            return
        }

        switch name {
        case "type":
            for character in (command["text"] as? String ?? "") { sendCharacter(character) }
        case "key":
            sendKey(code: UInt16(command["code"] as? Int ?? 0), mods: flags(command["mods"]))
        case "click":
            click(x: value(command["x"]), y: value(command["y"]), count: command["count"] as? Int ?? 1,
                  mods: flags(command["mods"]), button: command["button"] as? String ?? "left")
        case "drag":
            drag(from: NSPoint(x: value(command["x1"]), y: value(command["y1"])),
                 to: NSPoint(x: value(command["x2"]), y: value(command["y2"])), mods: flags(command["mods"]))
        case "setScale":
            pane()?.terminal.scaleForTesting = value(command["scale"])
            pane()?.terminal.viewDidChangeBackingProperties()
        case "resizeWindow":
            window()?.setContentSize(NSSize(width: value(command["width"]), height: value(command["height"])))
        case "closeWindow":
            window()?.close()
        case "press":
            mouse(.leftMouseDown, NSPoint(x: value(command["x"]), y: value(command["y"])), count: 1, mods: [])
        case "dragTo":
            mouse(.leftMouseDragged, NSPoint(x: value(command["x"]), y: value(command["y"])), count: 1, mods: [])
        case "release":
            mouse(.leftMouseUp, NSPoint(x: value(command["x"]), y: value(command["y"])), count: 1, mods: [])
        case "move":
            mouse(.mouseMoved, NSPoint(x: value(command["x"]), y: value(command["y"])), count: 0, mods: [])
        case "scroll":
            scroll(x: value(command["x"]), y: value(command["y"]), delta: value(command["dy"]))
        case "menu":
            pressMenu(command["path"] as? [String] ?? [])
        case "barType":
            pane()?.debugTypeIntoBar(command["text"] as? String ?? "")
        case "paletteType":
            controller()?.debugTypeIntoPalette(command["text"] as? String ?? "")
        case "pasteboard":
            Clipboard.write(command["text"] as? String ?? "")
        case "capture":
            pane()?.terminal.capture(to: command["path"] as? String ?? "/dev/null")
        case "state":
            break
        default:
            reply("{\"error\":\"unknown command \(name)\"}")
            return
        }

        // Events settle on the main queue before the state is read, so that a
        // test sees the result of what it just did.
        DispatchQueue.main.async { [weak self] in
            DispatchQueue.main.async { self?.reply(self?.stateJSON() ?? "{}") }
        }
    }

    private func value(_ any: Any?) -> CGFloat {
        CGFloat((any as? NSNumber)?.doubleValue ?? 0)
    }

    private func flags(_ any: Any?) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        for name in any as? [String] ?? [] {
            switch name {
            case "cmd": flags.insert(.command)
            case "shift": flags.insert(.shift)
            case "ctrl": flags.insert(.control)
            case "opt": flags.insert(.option)
            default: break
            }
        }
        return flags
    }

    // MARK: Synthesized input

    private func nextEventNumber() -> Int {
        eventNumber += 1
        return eventNumber
    }

    private func sendCharacter(_ character: Character) {
        guard let window = window() else { return }
        let text = String(character)
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: text,
                charactersIgnoringModifiers: text, isARepeat: false, keyCode: 0) else { continue }
            window.sendEvent(event)
        }
    }

    private func sendKey(code: UInt16, mods: NSEvent.ModifierFlags) {
        guard let window = window() else { return }
        var characters = Self.characters(forKeyCode: code, mods: mods)
        if mods.contains(.shift), code < 50 { characters = characters.uppercased() }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: mods, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) else { continue }
            // Shortcuts go through the menu first, exactly as AppKit and the key
            // router would send them.
            if type == .keyDown {
                if mods.contains(.command), window.contentView?.performKeyEquivalent(with: event) == true { return }
                // Responder-chain items need a key window, which a hidden test app
                // doesn't have, so they're sent to the first responder directly.
                if mods.contains(.command), let action = responderAction(for: characters, mods: mods),
                   window.firstResponder?.tryToPerform(action, with: nil) == true {
                    return
                }
                if mods.contains(.command), NSApp.mainMenu?.performKeyEquivalent(with: event) == true { return }
                if AppDelegate.routeToMenu(event) { return }
            }
            window.sendEvent(event)
        }
    }

    private func responderAction(for characters: String, mods: NSEvent.ModifierFlags) -> Selector? {
        for holder in NSApp.mainMenu?.items ?? [] {
            for item in holder.submenu?.items ?? [] where item.target == nil {
                if item.keyEquivalent == characters, item.keyEquivalentModifierMask == mods { return item.action }
            }
        }
        return nil
    }

    private static func characters(forKeyCode code: UInt16, mods: NSEvent.ModifierFlags) -> String {
        func scalar(_ value: Int) -> String { String(UnicodeScalar(value)!) }
        switch code {
        case 36: return "\r"
        case 48: return "\t"
        case 51: return "\u{7F}"
        case 53: return "\u{1B}"
        case 123: return scalar(NSLeftArrowFunctionKey)
        case 124: return scalar(NSRightArrowFunctionKey)
        case 125: return scalar(NSDownArrowFunctionKey)
        case 126: return scalar(NSUpArrowFunctionKey)
        case 115: return scalar(NSHomeFunctionKey)
        case 119: return scalar(NSEndFunctionKey)
        case 116: return scalar(NSPageUpFunctionKey)
        case 121: return scalar(NSPageDownFunctionKey)
        default:
            let letters: [UInt16: String] = [
                0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v", 11: "b",
                12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 31: "o", 32: "u", 34: "i", 35: "p",
                37: "l", 38: "j", 40: "k", 45: "n", 46: "m", 30: "]",
                18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
            ]
            return letters[code] ?? ""
        }
    }

    /// Takes points from the top-left of the window's content.
    private func windowPoint(_ point: NSPoint) -> NSPoint {
        NSPoint(x: point.x, y: (window()?.contentView?.bounds.height ?? 0) - point.y)
    }

    private func mouse(_ type: NSEvent.EventType, _ point: NSPoint, count: Int, mods: NSEvent.ModifierFlags) {
        guard let window = window() else { return }
        guard let event = NSEvent.mouseEvent(
            with: type, location: windowPoint(point), modifierFlags: mods, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: nextEventNumber(), clickCount: count,
            pressure: 1) else { return }
        window.sendEvent(event)
        // A real move reaches the tab bar through its tracking area, which needs a
        // key window. This one is invisible, so it gets the event directly.
        if type == .mouseMoved, let bar = window.contentView?.hitTest(event.locationInWindow) as? TabBarView {
            bar.mouseMoved(with: event)
        }
    }

    private func click(x: CGFloat, y: CGFloat, count: Int, mods: NSEvent.ModifierFlags, button: String) {
        let point = NSPoint(x: x, y: y)
        if button == "middle" {
            middleClick(at: point)
            return
        }
        if button == "right" {
            // Opening the real menu would block the run loop, so tests read the
            // menu's contents through the state instead.
            pane()?.terminal.prepareContextMenuForTesting(at: point, in: window())
            return
        }
        for click in 1...max(1, count) {
            mouse(.leftMouseDown, point, count: click, mods: mods)
            mouse(.leftMouseUp, point, count: click, mods: mods)
        }
    }

    /// NSEvent has no way to build a middle click directly.
    private func middleClick(at point: NSPoint) {
        guard let window = window(), let source = CGEventSource(stateID: .privateState),
              let event = CGEvent(mouseEventSource: source, mouseType: .otherMouseDown,
                                  mouseCursorPosition: window.convertPoint(toScreen: windowPoint(point)),
                                  mouseButton: .center),
              let down = NSEvent(cgEvent: event) else { return }
        window.sendEvent(down)
    }

    private func drag(from start: NSPoint, to end: NSPoint, mods: NSEvent.ModifierFlags) {
        mouse(.leftMouseDown, start, count: 1, mods: mods)
        for step in 1...5 {
            let t = CGFloat(step) / 5
            mouse(.leftMouseDragged, NSPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t),
                  count: 1, mods: mods)
        }
        mouse(.leftMouseUp, end, count: 1, mods: mods)
    }

    private func scroll(x: CGFloat, y: CGFloat, delta: CGFloat) {
        guard let window = window(), let source = CGEventSource(stateID: .privateState),
              let cgEvent = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 1,
                                    wheel1: Int32(delta), wheel2: 0, wheel3: 0) else { return }
        cgEvent.location = window.convertPoint(toScreen: windowPoint(NSPoint(x: x, y: y)))
        if let event = NSEvent(cgEvent: cgEvent) { window.sendEvent(event) }
    }

    private func pressMenu(_ path: [String]) {
        var menu = NSApp.mainMenu
        for (index, title) in path.enumerated() {
            guard let item = menu?.items.first(where: { $0.title == title || $0.submenu?.title == title }) else { return }
            if index == path.count - 1 {
                if let action = item.action { NSApp.sendAction(action, to: item.target, from: item) }
            } else {
                menu = item.submenu
            }
        }
    }

    private func stateJSON() -> String {
        guard let pane = pane() else { return "{}" }
        // Hidden test windows may get no display link ticks, so lay out directly.
        pane.layoutSubtreeIfNeeded()
        pane.terminal.prepareFrameForTesting()
        var state = pane.debugState()
        state["pasteboard"] = Clipboard.read() ?? NSNull()
        state["windows"] = NSApp.windows.filter(\.isVisible).count
        state["liveTerminals"] = TerminalView.liveCount
        state["tabs"] = controller()?.debugTabCount ?? 0
        state["panes"] = controller()?.debugPaneCount ?? 0
        state["tabTitles"] = controller()?.debugTabTitles ?? []
        state["selectedTab"] = controller()?.selectedTabIndex ?? 0
        state["tabPosition"] = controller()?.debugTabPosition ?? ""
        state["tabFrames"] = controller()?.debugTabFrames ?? []
        state["heldTabFrame"] = controller()?.debugHeldTabFrame ?? NSNull()
        state["hoveredTab"] = controller()?.debugHoveredTab ?? NSNull()
        state["titleBarDragsWindow"] = controller()?.debugTitleBarDragsWindow ?? true
        state["renaming"] = controller()?.debugIsRenaming ?? false
        state["paletteOpen"] = controller()?.debugPaletteOpen ?? false
        state["paletteName"] = controller()?.debugPaletteName ?? ""
        state["paletteItems"] = controller()?.debugPaletteItems ?? []
        guard let data = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Records frame timing for scripted runs. Costs one branch per frame otherwise.
final class FrameStats {
    static let shared = FrameStats()

    private var handle: FileHandle?
    private var frames = 0
    private var buildTotal = 0.0
    private var drawTotal = 0.0
    private var worst = 0.0
    private var windowStart = 0.0

    func start(writingTo path: String) {
        FileManager.default.createFile(atPath: path, contents: nil)
        handle = FileHandle(forWritingAtPath: path)
        windowStart = CACurrentMediaTime()
    }

    func record(build: Double, total: Double) {
        guard let handle else { return }
        frames += 1
        buildTotal += build
        drawTotal += total
        worst = max(worst, total)

        let now = CACurrentMediaTime()
        guard now - windowStart >= 1 else { return }
        let line = String(format: "fps %d  build %.2f ms  total %.2f ms  worst %.2f ms\n",
                          frames, buildTotal / Double(frames) * 1000, drawTotal / Double(frames) * 1000,
                          worst * 1000)
        handle.write(Data(line.utf8))
        frames = 0
        buildTotal = 0
        drawTotal = 0
        worst = 0
        windowStart = now
    }
}
