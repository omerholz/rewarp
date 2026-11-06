import AppKit
import RewarpCore

/// The floating bar for find and for block filtering. Both take a query with
/// options, so they differ only in which controls they show.
final class QueryBar: NSView, NSTextFieldDelegate {
    enum Mode {
        case find
        case filter
    }

    let field = NSTextField()
    private let countLabel = NSTextField(labelWithString: "")
    private let contextField = NSTextField()
    private var regexButton: NSButton!
    private var caseButton: NSButton!
    private var invertButton: NSButton!
    private let palette: ChromePalette

    var onChange: ((TextQuery, Int, Bool) -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onClose: (() -> Void)?

    static let size = NSSize(width: 386, height: 40)

    init(mode: Mode, theme: Theme) {
        palette = ChromePalette(theme: theme)
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        wantsLayer = true
        layer?.backgroundColor = palette.chrome.cgColor
        layer?.borderColor = palette.divider.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 8

        configure(field, placeholder: mode == .find ? "Find" : "Filter")
        field.frame = NSRect(x: 10, y: 8, width: 190, height: 24)
        addSubview(field)

        regexButton = toggle(".*", x: 206)
        caseButton = toggle("Aa", x: 238)
        var x: CGFloat = 270

        if mode == .filter {
            invertButton = toggle("!", x: x)
            x += 32
            configure(contextField, placeholder: "0")
            contextField.frame = NSRect(x: x, y: 8, width: 34, height: 24)
            addSubview(contextField)
            x += 40
        } else {
            countLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            countLabel.textColor = palette.secondaryText
            countLabel.alignment = .right
            countLabel.frame = NSRect(x: x, y: 11, width: 66, height: 16)
            addSubview(countLabel)
            x += 72
        }

        let close = NSButton(title: "\u{2715}", target: self, action: #selector(closePressed))
        close.isBordered = false
        close.contentTintColor = palette.secondaryText
        close.frame = NSRect(x: x, y: 8, width: 26, height: 24)
        addSubview(close)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func configure(_ field: NSTextField, placeholder: String) {
        field.delegate = self
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = palette.text
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .foregroundColor: palette.secondaryText,
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
        ])
    }

    private func toggle(_ title: String, x: CGFloat) -> NSButton {
        let button = NSButton(title: title, target: self, action: #selector(optionChanged))
        button.setButtonType(.pushOnPushOff)
        button.isBordered = false
        button.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        button.contentTintColor = palette.secondaryText
        button.frame = NSRect(x: x, y: 8, width: 28, height: 24)
        addSubview(button)
        return button
    }

    func setCount(_ text: String) {
        countLabel.stringValue = text
    }

    func setText(_ text: String) {
        // Pasted text can span lines, and a query can't.
        field.stringValue = text.replacingOccurrences(of: "\n", with: " ")
        notifyChange()
    }

    var query: TextQuery {
        TextQuery(text: field.stringValue, isRegex: regexButton.state == .on, isCaseSensitive: caseButton.state == .on)
    }

    private func notifyChange() {
        onChange?(query, max(0, contextField.integerValue), invertButton?.state == .on)
    }

    @objc private func optionChanged() {
        notifyChange()
    }

    @objc private func closePressed() {
        onClose?()
    }

    func controlTextDidChange(_ notification: Notification) {
        notifyChange()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if NSEvent.modifierFlags.contains(.shift) { onPrevious?() } else { onNext?() }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onClose?()
            return true
        default:
            return false
        }
    }
}
