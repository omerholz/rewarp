import AppKit
import RewarpCore

/// A searchable overlay for running actions or jumping between sessions.
final class PaletteView: NSView, NSTextFieldDelegate {
    struct Entry {
        var title: String
        var detail: String?
        var run: () -> Void
    }

    private let field = NSTextField()
    private let list = InlineMenuView()
    private let palette: ChromePalette
    private var entries: [Entry] = []
    private var filtered: [Entry] = []
    private var restoreFocus: NSResponder?

    static let width: CGFloat = 560
    private static let fieldHeight: CGFloat = 40

    init(theme: Theme) {
        palette = ChromePalette(theme: theme)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = palette.chrome.cgColor
        layer?.borderColor = palette.divider.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        isHidden = true

        field.delegate = self
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = palette.text
        field.font = .systemFont(ofSize: 14)
        addSubview(field)

        list.palette = palette
        list.accent = NSColor(rgb: theme.accent)
        list.startsAtTop = true
        list.onPick = { [weak self] in self?.run($0) }
        addSubview(list)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    var isOpen: Bool { !isHidden }
    var itemTitles: [String] { filtered.map(\.title) }

    func open(entries: [Entry], placeholder: String, in parent: NSView) {
        self.entries = entries
        restoreFocus = window?.firstResponder
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .foregroundColor: palette.secondaryText, .font: NSFont.systemFont(ofSize: 14),
        ])
        field.stringValue = ""
        isHidden = false
        refilter()
        relayout(in: parent)
        window?.makeFirstResponder(field)
    }

    func close() {
        isHidden = true
        if let responder = restoreFocus { window?.makeFirstResponder(responder) }
        restoreFocus = nil
        // Entries hold closures, which must not keep anything alive after closing.
        entries = []
        filtered = []
    }

    func relayout(in parent: NSView) {
        let height = Self.fieldHeight + list.preferredHeight
        let width = min(Self.width, parent.bounds.width - 40)
        frame = NSRect(x: (parent.bounds.width - width) / 2, y: parent.bounds.height - TabBarView.height - 60 - height,
                       width: width, height: height)
        field.frame = NSRect(x: 14, y: 10, width: width - 28, height: 22)
        list.frame = NSRect(x: 0, y: Self.fieldHeight, width: width, height: list.preferredHeight)
    }

    func type(_ text: String) {
        field.stringValue += text
        refilter()
    }

    private func refilter() {
        let query = field.stringValue.trimmingCharacters(in: .whitespaces)
        let scored = entries.enumerated().compactMap { index, entry -> (Int, Entry, FuzzyMatcher.Match)? in
            guard let match = FuzzyMatcher.match(query, in: entry.title) else { return nil }
            return (index, entry, match)
        }
        // An empty query keeps the order the entries came in, which puts the most
        // useful ones first.
        let ordered = query.isEmpty ? scored : scored.sorted { $0.2.score > $1.2.score }
        filtered = ordered.map(\.1)
        list.show(items: ordered.map {
            InlineMenuView.Item(title: $0.1.title, detail: $0.1.detail, matches: Set($0.2.positions))
        }, selecting: ordered.isEmpty ? nil : 0)
        if let parent = superview { relayout(in: parent) }
    }

    private func run(_ index: Int) {
        guard filtered.indices.contains(index) else { return }
        let entry = filtered[index]
        close()
        entry.run()
    }

    func controlTextDidChange(_ notification: Notification) {
        refilter()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if let index = list.selectedIndex { run(index) }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            close()
            return true
        case #selector(NSResponder.moveDown(_:)):
            list.moveSelection(by: 1)
            return true
        case #selector(NSResponder.moveUp(_:)):
            list.moveSelection(by: -1)
            return true
        case #selector(NSResponder.pageDown(_:)), #selector(NSResponder.scrollPageDown(_:)):
            list.moveSelection(by: 8)
            return true
        case #selector(NSResponder.pageUp(_:)), #selector(NSResponder.scrollPageUp(_:)):
            list.moveSelection(by: -8)
            return true
        default:
            return false
        }
    }
}
