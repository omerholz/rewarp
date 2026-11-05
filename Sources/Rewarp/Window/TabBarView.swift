import AppKit
import RewarpCore

/// Where a window shows its tabs. Warp offers the top and a left sidebar, and the
/// right sidebar is Rewarp's own addition.
enum TabBarPosition: String {
    case top
    case left
    case right

    private static let key = "tabBarPosition"

    static var saved: TabBarPosition {
        get {
            guard !DebugScript.isAutomated else { return .top }
            return UserDefaults.standard.string(forKey: key).flatMap(TabBarPosition.init) ?? .top
        }
        set {
            guard !DebugScript.isAutomated else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }
}

/// The tabs, either as a strip across the title bar or as a sidebar.
final class TabBarView: NSView, NSTextFieldDelegate {
    struct Item {
        var title: String
        var subtitle: String?
    }

    static let height: CGFloat = 38
    static let controlBarHeight: CGFloat = 34
    static let rowHeight: CGFloat = 46
    private static let trafficLightInset: CGFloat = 80
    private static let maximumTabWidth: CGFloat = 220
    private static let minimumTabWidth: CGFloat = 96
    private static let newTabWidth: CGFloat = 34
    private static let resizeMargin: CGFloat = 4

    var items: [Item] = [] { didSet { needsDisplay = true } }
    var selected = 0 { didSet { needsDisplay = true } }
    var palette = ChromePalette(theme: .dusk) { didSet { needsDisplay = true } }
    var position = TabBarPosition.top {
        didSet {
            cancelRename()
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }

    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onNewTab: (() -> Void)?
    var onMove: ((Int, Int) -> Void)?
    var onRename: ((Int, String) -> Void)?
    var onRenameEnded: (() -> Void)?
    var onResizeSidebar: ((CGFloat) -> Void)?
    var makeMenu: ((Int) -> NSMenu)?

    private var hovered: Int?
    private var hoveringClose = false
    private var dragging: Int?
    private var isResizing = false
    private var renameField: NSTextField?
    private var renamingIndex: Int?

    override var isFlipped: Bool { true }

    /// Clicking a tab from another app should act on that tab.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var isVertical: Bool { position != .top }
    var isRenaming: Bool { renamingIndex != nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    private var isFullScreen: Bool { window?.styleMask.contains(.fullScreen) ?? false }
    private var leading: CGFloat { isFullScreen ? 8 : Self.trafficLightInset }

    private var tabWidth: CGFloat {
        guard !items.isEmpty else { return Self.maximumTabWidth }
        let available = bounds.width - leading - Self.newTabWidth - 8
        return min(Self.maximumTabWidth, max(Self.minimumTabWidth, available / CGFloat(items.count)))
    }

    func tabRect(_ index: Int) -> NSRect {
        if isVertical {
            return NSRect(x: 0, y: Self.controlBarHeight + CGFloat(index) * Self.rowHeight,
                          width: bounds.width, height: Self.rowHeight)
        }
        return NSRect(x: leading + CGFloat(index) * tabWidth, y: 6, width: tabWidth, height: bounds.height - 6)
    }

    private func closeRect(_ index: Int) -> NSRect {
        let tab = tabRect(index)
        return NSRect(x: tab.maxX - 24, y: tab.midY - 8, width: 16, height: 16)
    }

    private var newTabRect: NSRect {
        if isVertical {
            return NSRect(x: bounds.width - 34, y: 5, width: 26, height: 24)
        }
        let x = leading + CGFloat(items.count) * tabWidth
        return NSRect(x: x + 4, y: 8, width: Self.newTabWidth - 8, height: bounds.height - 12)
    }

    /// The sidebar's inner edge, which drags to resize it.
    private var resizeRect: NSRect {
        guard isVertical else { return .zero }
        let x = position == .left ? bounds.width - Self.resizeMargin : 0
        return NSRect(x: x, y: 0, width: Self.resizeMargin, height: bounds.height)
    }

    override func resetCursorRects() {
        if isVertical { addCursorRect(resizeRect, cursor: .resizeLeftRight) }
    }

    override func draw(_ dirtyRect: NSRect) {
        palette.chrome.setFill()
        bounds.fill()
        if isVertical {
            palette.divider.setFill()
            NSRect(x: position == .left ? bounds.width - 1 : 0, y: 0, width: 1, height: bounds.height).fill()
            ("Tabs" as NSString).draw(at: NSPoint(x: 14, y: 9), withAttributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: palette.secondaryText,
            ])
        }

        for index in items.indices {
            if isVertical { drawRow(index) } else { drawTab(index) }
        }

        let plus = NSBezierPath()
        let center = NSPoint(x: newTabRect.midX, y: newTabRect.midY)
        plus.move(to: NSPoint(x: center.x - 5, y: center.y))
        plus.line(to: NSPoint(x: center.x + 5, y: center.y))
        plus.move(to: NSPoint(x: center.x, y: center.y - 5))
        plus.line(to: NSPoint(x: center.x, y: center.y + 5))
        plus.lineWidth = 1.3
        palette.secondaryText.setStroke()
        plus.stroke()
    }

    private func drawClose(_ index: Int) {
        let close = closeRect(index)
        if index == hovered && hoveringClose {
            palette.hover.setFill()
            NSBezierPath(roundedRect: close, xRadius: 4, yRadius: 4).fill()
        }
        let path = NSBezierPath()
        let inset = close.insetBy(dx: 5, dy: 5)
        path.move(to: NSPoint(x: inset.minX, y: inset.minY))
        path.line(to: NSPoint(x: inset.maxX, y: inset.maxY))
        path.move(to: NSPoint(x: inset.maxX, y: inset.minY))
        path.line(to: NSPoint(x: inset.minX, y: inset.maxY))
        path.lineWidth = 1.2
        palette.secondaryText.setStroke()
        path.stroke()
    }

    private func drawTab(_ index: Int) {
        let rect = tabRect(index)
        let isSelected = index == selected
        if isSelected || index == hovered {
            (isSelected ? palette.background : palette.hover).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 0), xRadius: 7, yRadius: 7).fill()
            if isSelected {
                NSRect(x: rect.minX + 2, y: rect.maxY - 7, width: rect.width - 4, height: 7).fill()
            }
        }

        let showClose = index == hovered || isSelected
        guard index != renamingIndex else { return }
        let textRect = NSRect(x: rect.minX + 14, y: rect.midY - 8,
                              width: rect.width - (showClose ? 44 : 28), height: 16)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        (items[index].title as NSString).draw(in: textRect, withAttributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: isSelected ? .medium : .regular),
            .foregroundColor: isSelected ? palette.text : palette.secondaryText,
            .paragraphStyle: paragraph,
        ])
        if showClose { drawClose(index) }
    }

    private func drawRow(_ index: Int) {
        let rect = tabRect(index)
        let isSelected = index == selected
        if isSelected || index == hovered {
            (isSelected ? palette.background : palette.hover).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 6, dy: 2), xRadius: 6, yRadius: 6).fill()
        }

        guard index != renamingIndex else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        let showClose = index == hovered
        let width = rect.width - (showClose ? 48 : 28)
        (items[index].title as NSString).draw(
            in: NSRect(x: rect.minX + 14, y: rect.minY + 7, width: width, height: 16),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: isSelected ? .medium : .regular),
                .foregroundColor: isSelected ? palette.text : palette.secondaryText,
                .paragraphStyle: paragraph,
            ])
        if let subtitle = items[index].subtitle {
            (subtitle as NSString).draw(
                in: NSRect(x: rect.minX + 14, y: rect.minY + 24, width: width, height: 14),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 10.5), .foregroundColor: palette.secondaryText,
                    .paragraphStyle: paragraph,
                ])
        }
        if showClose { drawClose(index) }
    }

    private func tabIndex(at point: NSPoint) -> Int? {
        items.indices.first { tabRect($0).contains(point) }
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        hovered = tabIndex(at: point)
        hoveringClose = hovered.map { closeRect($0).contains(point) } ?? false
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = nil
        hoveringClose = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isVertical, resizeRect.contains(point) {
            isResizing = true
        } else if newTabRect.contains(point) {
            onNewTab?()
        } else if let index = tabIndex(at: point) {
            if closeRect(index).contains(point) {
                onClose?(index)
            } else if event.clickCount == 2 {
                beginRename(index)
            } else {
                onSelect?(index)
                dragging = index
            }
        } else if isVertical {
            if event.clickCount == 2 { onNewTab?() }
        } else if event.clickCount == 2 {
            window?.performZoom(nil)
        } else {
            window?.performDrag(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if isResizing {
            let location = event.locationInWindow.x
            let width = position == .left ? location : (window?.contentView?.bounds.width ?? 0) - location
            onResizeSidebar?(width)
            return
        }
        guard let source = dragging else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let target = tabIndex(at: point), target != source {
            onMove?(source, target)
            dragging = target
        }
    }

    override func mouseUp(with event: NSEvent) {
        dragging = nil
        isResizing = false
    }

    /// Middle click closes a tab.
    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2, let index = tabIndex(at: convert(event.locationInWindow, from: nil)) else { return }
        onClose?(index)
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = tabIndex(at: point), let menu = makeMenu?(index) else { return }
        menu.popUp(positioning: nil, at: point, in: self)
    }

    // MARK: Renaming

    func beginRename(_ index: Int) {
        guard items.indices.contains(index) else { return }
        cancelRename()
        renamingIndex = index
        let rect = tabRect(index)
        let field = NSTextField(string: items[index].title)
        field.delegate = self
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = palette.text
        field.font = .systemFont(ofSize: 12)
        field.frame = isVertical
            ? NSRect(x: rect.minX + 14, y: rect.minY + 6, width: rect.width - 28, height: 18)
            : NSRect(x: rect.minX + 14, y: rect.midY - 9, width: rect.width - 28, height: 18)
        addSubview(field)
        renameField = field
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
        needsDisplay = true
    }

    private func cancelRename() {
        // Cleared first, because removing the field ends editing, and that would
        // otherwise come back through finishRename and commit the text.
        let field = renameField
        renameField = nil
        renamingIndex = nil
        field?.removeFromSuperview()
    }

    private func finishRename(commit: Bool) {
        guard let field = renameField, let index = renamingIndex else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        cancelRename()
        if commit { onRename?(index, text) }
        needsDisplay = true
        onRenameEnded?()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            finishRename(commit: true)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            finishRename(commit: false)
            return true
        default:
            return false
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        finishRename(commit: true)
    }
}

/// App chrome colours, derived from the terminal theme.
struct ChromePalette {
    let background: NSColor
    let chrome: NSColor
    let hover: NSColor
    let divider: NSColor
    let text: NSColor
    let secondaryText: NSColor

    init(theme: Theme) {
        let contrast = theme.isDark ? RGB(255, 255, 255) : RGB(0, 0, 0)
        background = NSColor(rgb: theme.background)
        chrome = NSColor(rgb: theme.background.mixed(with: RGB(0, 0, 0), 0.22))
        hover = NSColor(rgb: theme.background.mixed(with: contrast, 0.08))
        divider = NSColor(rgb: theme.background.mixed(with: contrast, 0.14))
        text = NSColor(rgb: theme.foreground)
        secondaryText = NSColor(rgb: theme.foreground.mixed(with: theme.background, 0.42))
    }
}

extension NSColor {
    convenience init(rgb: RGB) {
        self.init(srgbRed: CGFloat(rgb.r) / 255, green: CGFloat(rgb.g) / 255, blue: CGFloat(rgb.b) / 255, alpha: 1)
    }
}

/// The strip across the top of a window whose tabs are in a sidebar, which holds
/// the traffic lights and drags the window.
final class TitleStripView: NSView {
    static let height: CGFloat = 30

    var color = NSColor.black { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        bounds.fill()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.performZoom(nil)
        } else {
            window?.performDrag(with: event)
        }
    }
}
