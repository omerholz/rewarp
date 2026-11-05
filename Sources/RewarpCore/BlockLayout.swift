/// Where each block sits in the scrolling list, in device pixels. This is kept
/// apart from drawing so that it can be tested, and so that a pane with thousands
/// of blocks only ever touches the ones on screen.
public struct BlockLayout: Equatable {
    public struct Spec: Equatable {
        public var id: Int
        public var headerHeight: Int
        public var outputRows: Int

        public init(id: Int, headerHeight: Int, outputRows: Int) {
            self.id = id
            self.headerHeight = headerHeight
            self.outputRows = outputRows
        }
    }

    public struct Entry: Equatable {
        public var id: Int
        public var top: Int
        public var headerHeight: Int
        public var outputRows: Int
        public var height: Int

        public var bottom: Int { top + height }
        public var outputTop: Int { top + headerHeight }
    }

    public let cellHeight: Int
    public let footerHeight: Int
    public private(set) var entries: [Entry] = []

    public init(cellHeight: Int, footerHeight: Int) {
        self.cellHeight = cellHeight
        self.footerHeight = footerHeight
    }

    public var contentHeight: Int { entries.last?.bottom ?? 0 }

    public mutating func rebuild(_ specs: [Spec]) {
        entries.removeAll(keepingCapacity: true)
        var top = 0
        for spec in specs {
            let entry = makeEntry(spec, top: top)
            entries.append(entry)
            top = entry.bottom
        }
    }

    /// The common case while a command runs: only the newest block grows.
    public mutating func updateLast(outputRows: Int) {
        guard let last = entries.last, last.outputRows != outputRows else { return }
        let spec = Spec(id: last.id, headerHeight: last.headerHeight, outputRows: outputRows)
        entries[entries.count - 1] = makeEntry(spec, top: last.top)
    }

    private func makeEntry(_ spec: Spec, top: Int) -> Entry {
        Entry(id: spec.id, top: top, headerHeight: spec.headerHeight, outputRows: spec.outputRows,
              height: spec.headerHeight + spec.outputRows * cellHeight + footerHeight)
    }

    /// The entries overlapping a window of the list.
    public func visibleRange(top: Int, height: Int) -> Range<Int> {
        guard !entries.isEmpty, height > 0 else { return 0..<0 }
        let start = firstIndex { $0.bottom > top }
        let end = firstIndex { $0.top >= top + height }
        return start..<max(start, end)
    }

    /// Binary search for the first entry where `predicate` becomes true.
    private func firstIndex(where predicate: (Entry) -> Bool) -> Int {
        var low = 0
        var high = entries.count
        while low < high {
            let middle = (low + high) / 2
            if predicate(entries[middle]) {
                high = middle
            } else {
                low = middle + 1
            }
        }
        return low
    }
}

/// The scroll position of a block list.
public struct BlockScroll: Equatable {
    /// Pixels from the top of the list to the top of the viewport.
    public private(set) var offset = 0
    /// Whether new output keeps the list scrolled to the bottom.
    public private(set) var followsTail = true

    public init() {}

    public static func maximum(content: Int, viewport: Int) -> Int {
        max(0, content - viewport)
    }

    /// Re-applies the limits after the content or the viewport changed.
    public mutating func settle(content: Int, viewport: Int) {
        let limit = Self.maximum(content: content, viewport: viewport)
        offset = followsTail ? limit : min(offset, limit)
    }

    public mutating func scroll(by delta: Int, content: Int, viewport: Int) {
        scroll(to: offset + delta, content: content, viewport: viewport)
    }

    public mutating func scroll(to target: Int, content: Int, viewport: Int) {
        let limit = Self.maximum(content: content, viewport: viewport)
        offset = min(max(target, 0), limit)
        followsTail = offset >= limit
    }

    public mutating func scrollToBottom(content: Int, viewport: Int) {
        offset = Self.maximum(content: content, viewport: viewport)
        followsTail = true
    }
}
