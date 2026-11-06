import CoreGraphics

public struct PaneID: Hashable, Codable, Sendable {
    public let rawValue: Int

    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }
}

public enum SplitAxis: String, Codable, Sendable {
    /// Children side by side.
    case horizontal
    /// Children stacked.
    case vertical
}

public enum PaneDirection: Sendable {
    case left, right, up, down

    var axis: SplitAxis { self == .left || self == .right ? .horizontal : .vertical }
}

/// How a tab's panes are arranged. This is plain data, so that it can be saved,
/// restored, moved between tabs and tested without any views.
public indirect enum PaneTree: Equatable, Codable, Sendable {
    case pane(PaneID)
    case split(SplitAxis, ratio: Double, first: PaneTree, second: PaneTree)

    /// A divider's position in the tree, as first-or-second turns from the root.
    public typealias Path = [Bool]

    public struct Divider: Equatable, Sendable {
        public var path: Path
        public var axis: SplitAxis
        public var frame: CGRect
        /// The split this divider belongs to, for turning a drag into a ratio.
        public var bounds: CGRect
    }

    public struct Layout: Equatable, Sendable {
        public var panes: [PaneID: CGRect] = [:]
        public var dividers: [Divider] = []
    }

    public static let minimumRatio = 0.1
    public static let maximumRatio = 0.9

    /// Left to right, top to bottom.
    public var paneIDs: [PaneID] {
        switch self {
        case .pane(let id):
            return [id]
        case .split(_, _, let first, let second):
            return first.paneIDs + second.paneIDs
        }
    }

    public func contains(_ id: PaneID) -> Bool {
        paneIDs.contains(id)
    }

    /// Replaces a pane with a split of that pane and a new one.
    public func splitting(_ id: PaneID, axis: SplitAxis, adding new: PaneID) -> PaneTree {
        switch self {
        case .pane(let existing):
            guard existing == id else { return self }
            return .split(axis, ratio: 0.5, first: self, second: .pane(new))
        case .split(let splitAxis, let ratio, let first, let second):
            return .split(splitAxis, ratio: ratio,
                          first: first.splitting(id, axis: axis, adding: new),
                          second: second.splitting(id, axis: axis, adding: new))
        }
    }

    /// The tree without a pane, or nil when that was the only one. The pane's
    /// sibling takes the whole of the space they shared.
    public func removing(_ id: PaneID) -> PaneTree? {
        switch self {
        case .pane(let existing):
            return existing == id ? nil : self
        case .split(let axis, let ratio, let first, let second):
            guard let keptFirst = first.removing(id) else { return second }
            guard let keptSecond = second.removing(id) else { return first }
            return .split(axis, ratio: ratio, first: keptFirst, second: keptSecond)
        }
    }

    public func settingRatio(_ newRatio: Double, at path: Path) -> PaneTree {
        guard case .split(let axis, let ratio, let first, let second) = self else { return self }
        guard let turn = path.first else {
            return .split(axis, ratio: Self.clamp(newRatio), first: first, second: second)
        }
        let rest = Array(path.dropFirst())
        return turn
            ? .split(axis, ratio: ratio, first: first.settingRatio(newRatio, at: rest), second: second)
            : .split(axis, ratio: ratio, first: first, second: second.settingRatio(newRatio, at: rest))
    }

    /// Moves the divider nearest to a pane on the axis of the direction.
    public func resizing(_ id: PaneID, _ direction: PaneDirection, by amount: Double) -> PaneTree {
        guard let path = nearestDivider(to: id, axis: direction.axis) else { return self }
        let delta = direction == .left || direction == .up ? -amount : amount
        return settingRatio(ratio(at: path) + delta, at: path)
    }

    private func ratio(at path: Path) -> Double {
        guard case .split(_, let ratio, let first, let second) = self else { return 0.5 }
        guard let turn = path.first else { return ratio }
        return (turn ? first : second).ratio(at: Array(path.dropFirst()))
    }

    private func nearestDivider(to id: PaneID, axis: SplitAxis) -> Path? {
        guard case .split(let splitAxis, _, let first, let second) = self, contains(id) else { return nil }
        let turn = first.contains(id)
        if let deeper = (turn ? first : second).nearestDivider(to: id, axis: axis) {
            return [turn] + deeper
        }
        return splitAxis == axis ? [] : nil
    }

    private static func clamp(_ ratio: Double) -> Double {
        min(max(ratio, minimumRatio), maximumRatio)
    }

    public func layout(in bounds: CGRect, dividerThickness: CGFloat) -> Layout {
        var layout = Layout()
        place(in: bounds, thickness: dividerThickness, path: [], into: &layout)
        return layout
    }

    private func place(in rect: CGRect, thickness t: CGFloat, path: Path, into layout: inout Layout) {
        switch self {
        case .pane(let id):
            layout.panes[id] = rect
        case .split(let axis, let ratio, let first, let second):
            let firstFrame: CGRect
            let secondFrame: CGRect
            let divider: CGRect
            switch axis {
            case .horizontal:
                let width = ((rect.width - t) * CGFloat(ratio)).rounded()
                firstFrame = CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height)
                divider = CGRect(x: rect.minX + width, y: rect.minY, width: t, height: rect.height)
                secondFrame = CGRect(x: rect.minX + width + t, y: rect.minY,
                                     width: rect.width - width - t, height: rect.height)
            case .vertical:
                let height = ((rect.height - t) * CGFloat(ratio)).rounded()
                firstFrame = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: height)
                divider = CGRect(x: rect.minX, y: rect.minY + height, width: rect.width, height: t)
                secondFrame = CGRect(x: rect.minX, y: rect.minY + height + t, width: rect.width,
                                     height: rect.height - height - t)
            }
            layout.dividers.append(Divider(path: path, axis: axis, frame: divider, bounds: rect))
            first.place(in: firstFrame, thickness: t, path: path + [true], into: &layout)
            second.place(in: secondFrame, thickness: t, path: path + [false], into: &layout)
        }
    }

    /// The closest pane in a direction, among those sharing an edge with this one.
    public func neighbor(of id: PaneID, _ direction: PaneDirection, in bounds: CGRect) -> PaneID? {
        let frames = layout(in: bounds, dividerThickness: 1).panes
        guard let current = frames[id] else { return nil }
        var best: (id: PaneID, gap: CGFloat)?
        for (other, frame) in frames where other != id {
            let gap: CGFloat
            let overlaps: Bool
            switch direction {
            case .left:
                gap = current.minX - frame.maxX
                overlaps = frame.maxY > current.minY && frame.minY < current.maxY
            case .right:
                gap = frame.minX - current.maxX
                overlaps = frame.maxY > current.minY && frame.minY < current.maxY
            case .up:
                gap = current.minY - frame.maxY
                overlaps = frame.maxX > current.minX && frame.minX < current.maxX
            case .down:
                gap = frame.minY - current.maxY
                overlaps = frame.maxX > current.minX && frame.minX < current.maxX
            }
            guard overlaps, gap >= 0 else { continue }
            if best == nil || gap < best!.gap { best = (other, gap) }
        }
        return best?.id
    }
}
