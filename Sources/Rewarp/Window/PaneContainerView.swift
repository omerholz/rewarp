import AppKit
import RewarpCore

/// Shows one tab's panes, positioned from its `PaneTree`. Panes stay flat children
/// of this view, so a split never reparents one, and maximizing just hides the rest.
final class PaneContainerView: NSView {
    private static let dividerThickness: CGFloat = 1
    private static let grabMargin: CGFloat = 4

    var tree: PaneTree {
        didSet { needsLayout = true }
    }
    /// The pane filling the whole tab, when one is maximized.
    var maximized: PaneID? {
        didSet { needsLayout = true }
    }

    private let dividerColor: NSColor
    private var panes: [PaneID: PaneView] = [:]
    private var dividers: [PaneTree.Divider] = []
    private var dragging: PaneTree.Divider?

    init(tree: PaneTree, dividerColor: NSColor) {
        self.tree = tree
        self.dividerColor = dividerColor
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func add(_ pane: PaneView, id: PaneID) {
        panes[id] = pane
        addSubview(pane)
    }

    func remove(_ id: PaneID) {
        panes.removeValue(forKey: id)?.removeFromSuperview()
    }

    func pane(_ id: PaneID) -> PaneView? {
        panes[id]
    }

    func id(of pane: PaneView) -> PaneID? {
        panes.first { $0.value === pane }?.key
    }

    /// In tree order.
    var orderedPanes: [PaneView] {
        tree.paneIDs.compactMap { panes[$0] }
    }

    override func layout() {
        super.layout()
        let layout = tree.layout(in: bounds, dividerThickness: Self.dividerThickness)
        dividers = maximized == nil ? layout.dividers : []
        for (id, pane) in panes {
            pane.isHidden = maximized != nil && maximized != id
            pane.frame = maximized == id ? bounds : layout.panes[id] ?? .zero
        }
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        dividerColor.setFill()
        dividers.forEach { $0.frame.fill() }
    }

    private func grabRect(_ divider: PaneTree.Divider) -> NSRect {
        divider.frame.insetBy(dx: divider.axis == .horizontal ? -Self.grabMargin : 0,
                              dy: divider.axis == .vertical ? -Self.grabMargin : 0)
    }

    private func divider(at point: NSPoint) -> PaneTree.Divider? {
        dividers.first { grabRect($0).contains(point) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        return divider(at: convert(point, from: superview)) == nil ? super.hitTest(point) : self
    }

    override func resetCursorRects() {
        for divider in dividers {
            addCursorRect(grabRect(divider), cursor: divider.axis == .horizontal ? .resizeLeftRight : .resizeUpDown)
        }
    }

    override func mouseDown(with event: NSEvent) {
        dragging = divider(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragging else { return }
        let point = convert(event.locationInWindow, from: nil)
        let bounds = dragging.bounds
        let ratio = dragging.axis == .horizontal
            ? (point.x - bounds.minX) / bounds.width
            : (point.y - bounds.minY) / bounds.height
        tree = tree.settingRatio(Double(ratio), at: dragging.path)
    }

    override func mouseUp(with event: NSEvent) {
        dragging = nil
    }
}
