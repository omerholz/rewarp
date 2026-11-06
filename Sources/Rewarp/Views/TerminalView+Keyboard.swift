import AppKit
import CGhosttyVT
import RewarpCore

extension TerminalView {
    /// Whether keys belong to a running program rather than to the block list.
    var keysGoToProgram: Bool {
        session.withState { $0.routesInputToProgram }
    }

    override func keyDown(with event: NSEvent) {
        guard keysGoToProgram else {
            handleBlockListKey(event)
            return
        }
        let wasComposing = hasMarkedText()
        keyText = ""
        isInterpreting = true
        interpretKeyEvents([event])
        isInterpreting = false

        // The input method kept the key, either to compose or to cancel composing.
        if hasMarkedText() || (wasComposing && keyText.isEmpty) { return }
        send(event, action: event.isARepeat ? GHOSTTY_KEY_ACTION_REPEAT : GHOSTTY_KEY_ACTION_PRESS, text: keyText)
    }

    override func keyUp(with event: NSEvent) {
        guard keysGoToProgram else { return }
        send(event, action: GHOSTTY_KEY_ACTION_RELEASE, text: "")
    }

    private func handleBlockListKey(_ event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 126:  // up
            shift ? extendBlockSelection(up: true) : selectAdjacentBlock(up: true)
        case 125:  // down
            shift ? extendBlockSelection(up: false) : selectAdjacentBlock(up: false)
        case 53:  // escape
            clearBlockSelection()
            onFocusInput?()
        case 116:  // page up
            scrollList(by: -listHeight)
        case 121:  // page down
            scrollList(by: listHeight)
        case 115:  // home
            scrollList(to: 0)
        case 119:  // end
            scrollList(to: layout.contentHeight)
        default:
            // Typing with a block selected carries on in the input.
            if let characters = event.characters, !characters.isEmpty,
               !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.control),
               printable(characters).isEmpty == false {
                clearBlockSelection()
                onFocusInput?()
                onInsertIntoInput?(characters)
            }
        }
    }

    private func send(_ event: NSEvent, action: GhosttyKeyAction, text: String) {
        session.withState { keyEncoder.syncModes(from: $0.inputTerminal.handle) }

        let bytes = keyEncoder.encode(event, action: action, text: printable(text))
        guard !bytes.isEmpty else { return }
        session.sendToProcess(bytes)
    }

    /// AppKit reports control characters and function keys as text. The encoder
    /// derives those from the key itself and must not see them as typed text.
    private func printable(_ text: String) -> String {
        guard let scalar = text.unicodeScalars.first, text.unicodeScalars.count == 1 else { return text }
        if scalar.value < 0x20 || scalar.value == 0x7F || (0xF700...0xF8FF).contains(scalar.value) { return "" }
        return text
    }

    override func doCommand(by selector: Selector) {
        // Handled by the encoder. Overriding this stops AppKit from beeping.
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        markedTextValue = ""
        if isInterpreting {
            keyText += text
        } else {
            session.sendToProcess(Array(text.utf8))
        }
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        markedTextValue = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
    }

    func unmarkText() { markedTextValue = "" }
    func hasMarkedText() -> Bool { !markedTextValue.isEmpty }
    func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }

    func markedRange() -> NSRange {
        hasMarkedText() ? NSRange(location: 0, length: markedTextValue.utf16.count) : NSRange(location: NSNotFound, length: 0)
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        window?.convertToScreen(convert(bounds, to: nil)) ?? .zero
    }

    func characterIndex(for point: NSPoint) -> Int { NSNotFound }
}
