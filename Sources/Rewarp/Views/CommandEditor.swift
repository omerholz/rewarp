import AppKit
import RewarpCore

/// The text view at the heart of the input. AppKit provides IME, undo, selection
/// and accessibility, and this class adds the shell-specific behaviour.
final class CommandEditor: NSTextView {
    var onSubmit: ((String) -> Void)?
    var onChange: (() -> Void)?
    var onArrowUp: (() -> Bool)?
    var onArrowDown: (() -> Bool)?
    var onEscape: (() -> Bool)?
    var onTab: (() -> Bool)?
    var onBackTab: (() -> Bool)?
    var onReturn: (() -> Bool)?
    var onRunSelection: (() -> Bool)?
    var onCommandSearch: (() -> Void)?
    var onCancelInput: (() -> Void)?
    var onClearScreen: (() -> Void)?
    var onFocused: (() -> Void)?

    /// The rest of the suggested command, drawn after the text as ghost text.
    var ghostText: String? {
        didSet {
            if ghostText != oldValue { needsDisplay = true }
        }
    }

    /// The modifiers of the key being handled, for commands AppKit reports
    /// without them.
    private var keyModifiers: NSEvent.ModifierFlags = []

    var ghostColor = NSColor.gray
    var hintColor = NSColor.gray
    var hintText = "Run commands"

    convenience init(font: NSFont) {
        // Built by hand because this forces TextKit 1, which is what provides
        // temporary attributes for highlighting.
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        storage.addLayoutManager(manager)
        let container = NSTextContainer(size: NSSize(width: 100, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        self.init(frame: .zero, textContainer: container)

        self.font = font
        drawsBackground = false
        isRichText = false
        allowsUndo = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        textContainerInset = .zero
        isVerticallyResizable = false
        isHorizontallyResizable = false
        autoresizingMask = [.width]
    }

    var usedHeight: CGFloat {
        guard let manager = layoutManager, let container = textContainer else { return 0 }
        manager.ensureLayout(for: container)
        return max(manager.usedRect(for: container).height, font.map { manager.defaultLineHeight(for: $0) } ?? 16)
    }

    private var isOnFirstLine: Bool {
        guard let manager = layoutManager else { return true }
        let caret = selectedRange().location
        guard !string.isEmpty else { return true }
        let glyph = manager.glyphIndexForCharacter(at: min(caret, max(0, string.utf16.count - 1)))
        var range = NSRange()
        manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &range)
        return range.location == 0
    }

    private var isOnLastLine: Bool {
        guard let manager = layoutManager, !string.isEmpty else { return true }
        let length = string.utf16.count
        let caret = selectedRange().location
        if caret >= length { return true }
        var range = NSRange()
        manager.lineFragmentRect(forGlyphAt: manager.glyphIndexForCharacter(at: caret), effectiveRange: &range)
        return NSMaxRange(range) >= manager.numberOfGlyphs
    }

    private var caretIsAtEnd: Bool {
        selectedRange().length == 0 && selectedRange().location == string.utf16.count
    }

    func setText(_ text: String) {
        string = text
        setSelectedRange(NSRange(location: text.utf16.count, length: 0))
        didChangeText()
    }

    func insert(_ text: String) {
        insertText(text, replacementRange: selectedRange())
    }

    func acceptGhostText() -> Bool {
        guard let ghost = ghostText, caretIsAtEnd else { return false }
        ghostText = nil
        insertText(ghost, replacementRange: selectedRange())
        return true
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { onFocused?() }
        return result
    }

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if mods == [.control], let key = event.charactersIgnoringModifiers?.lowercased() {
            switch key {
            case "c":
                onCancelInput?()
                return
            case "r":
                onCommandSearch?()
                return
            case "l":
                onClearScreen?()
                return
            case "j":
                insertNewlineIgnoringFieldEditor(nil)
                return
            case "w":
                deleteWordBackward(nil)
                return
            default:
                break
            }
        }
        keyModifiers = mods
        super.keyDown(with: event)
    }

    /// AppKit offers key equivalents to views before the menu bar, which is what
    /// lets Command-Enter act on an open menu.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if window?.firstResponder === self, mods == [.command], event.keyCode == 36,
           onRunSelection?() == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func doCommand(by selector: Selector) {
        switch selector {
        case #selector(insertNewline(_:)):
            if keyModifiers.contains(.shift) {
                insertNewlineIgnoringFieldEditor(nil)
            } else if onReturn?() != true {
                submitCurrentText()
            }
        case #selector(moveUp(_:)):
            if !(isOnFirstLine && onArrowUp?() == true) { super.doCommand(by: selector) }
        case #selector(moveDown(_:)):
            if !(isOnLastLine && onArrowDown?() == true) { super.doCommand(by: selector) }
        case #selector(insertTab(_:)):
            if onTab?() != true { super.doCommand(by: selector) }
        case #selector(insertBacktab(_:)):
            if onBackTab?() != true { super.doCommand(by: selector) }
        case #selector(moveRight(_:)), #selector(moveForward(_:)), #selector(moveToEndOfLine(_:)),
             #selector(moveToRightEndOfLine(_:)), #selector(moveToEndOfParagraph(_:)):
            if !acceptGhostText() { super.doCommand(by: selector) }
        case #selector(cancelOperation(_:)):
            if onEscape?() == true { return }
            if ghostText != nil {
                ghostText = nil
            }
        default:
            super.doCommand(by: selector)
        }
    }

    func submitCurrentText() {
        let command = string
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        setText("")
        ghostText = nil
        onSubmit?(command)
    }

    override func didChangeText() {
        super.didChangeText()
        onChange?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let manager = layoutManager, let font else { return }

        if string.isEmpty {
            (hintText as NSString).draw(at: .zero, withAttributes: [.font: font, .foregroundColor: hintColor])
        }

        guard let ghost = ghostText else { return }
        var origin = NSPoint.zero
        if manager.numberOfGlyphs > 0 {
            let last = manager.numberOfGlyphs - 1
            let line = manager.lineFragmentUsedRect(forGlyphAt: last, effectiveRange: nil)
            origin = NSPoint(x: line.maxX, y: line.minY)
        }
        (ghost as NSString).draw(at: origin, withAttributes: [.font: font, .foregroundColor: ghostColor])
    }
}
