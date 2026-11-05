import CoreGraphics
import Foundation
import Testing
@testable import RewarpCore

private let a = PaneID(1)
private let b = PaneID(2)
private let c = PaneID(3)
private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 600)

/// [a | [b over c]]
private let threePanes = PaneTree.pane(a)
    .splitting(a, axis: .horizontal, adding: b)
    .splitting(b, axis: .vertical, adding: c)

@Suite("Pane tree")
struct PaneTreeTests {
    @Test("Splitting puts the new pane beside the one that was split")
    func splitting() {
        #expect(threePanes.paneIDs == [a, b, c])
    }

    @Test("Removing a pane gives its space to its sibling")
    func removing() {
        #expect(threePanes.removing(c)?.paneIDs == [a, b])
        let frames = threePanes.removing(c)?.layout(in: bounds, dividerThickness: 1).panes
        #expect(frames?[b]?.height == 600)
    }

    @Test("Removing the last pane leaves nothing")
    func removingLast() {
        #expect(PaneTree.pane(a).removing(a) == nil)
    }

    @Test("Removing a pane that isn't there changes nothing")
    func removingUnknown() {
        #expect(threePanes.removing(PaneID(9)) == threePanes)
    }

    @Test("Panes fill the space without overlapping")
    func layout() {
        let layout = threePanes.layout(in: bounds, dividerThickness: 1)
        #expect(layout.panes[a] == CGRect(x: 0, y: 0, width: 500, height: 600))
        #expect(layout.panes[b]?.minX == 501)
        #expect(layout.panes[b]?.maxY == layout.dividers[1].frame.minY)
        #expect(layout.panes[c]?.maxY == 600)
        #expect(layout.dividers.count == 2)
    }

    @Test("Dividers know which split they belong to")
    func dividerPaths() {
        let layout = threePanes.layout(in: bounds, dividerThickness: 1)
        #expect(layout.dividers.map(\.path) == [[], [false]])
        #expect(layout.dividers.map(\.axis) == [.horizontal, .vertical])
    }

    @Test("Setting a ratio reaches the right split")
    func settingRatio() {
        let tree = threePanes.settingRatio(0.25, at: [false])
        let frames = tree.layout(in: bounds, dividerThickness: 1).panes
        #expect(frames[a]?.width == 500)
        #expect(frames[b]?.height == 150)
    }

    @Test("Ratios stay in range")
    func ratioLimits() {
        let tree = PaneTree.pane(a).splitting(a, axis: .horizontal, adding: b).settingRatio(5, at: [])
        guard case .split(_, let ratio, _, _) = tree else {
            Issue.record("expected a split")
            return
        }
        #expect(ratio == PaneTree.maximumRatio)
    }

    @Test("Resizing moves the nearest divider on that axis")
    func resizing() {
        let wider = threePanes.resizing(a, .right, by: 0.1).layout(in: bounds, dividerThickness: 1).panes
        #expect(wider[a]!.width > 500)
        let taller = threePanes.resizing(b, .down, by: 0.1).layout(in: bounds, dividerThickness: 1).panes
        #expect(taller[b]!.height > 300)
    }

    @Test("Resizing with no divider on that axis changes nothing")
    func resizingNoDivider() {
        #expect(threePanes.resizing(a, .up, by: 0.1) == threePanes)
    }

    @Test("Neighbours are found by position")
    func neighbours() {
        #expect(threePanes.neighbor(of: b, .down, in: bounds) == c)
        #expect(threePanes.neighbor(of: c, .up, in: bounds) == b)
        #expect(threePanes.neighbor(of: b, .left, in: bounds) == a)
        #expect(threePanes.neighbor(of: a, .left, in: bounds) == nil)
    }

    @Test("A layout survives being saved and loaded, which session restore needs")
    func codable() throws {
        let tree = threePanes.settingRatio(0.3, at: [])
        let data = try JSONEncoder().encode(tree)
        #expect(try JSONDecoder().decode(PaneTree.self, from: data) == tree)
    }
}
