import CGhosttyVT
import Foundation
import os

public enum SessionEvent {
    /// The shell is about to show a prompt.
    case promptStarted
    /// The shell is at a prompt and can accept a command.
    case ready
    case blockStarted(Block)
    case blockFinished(Block)
    case gitBranchChanged(String?)
    /// A program entered or left the alternate screen.
    case fullScreenChanged(Bool)
    case titleChanged(String)
    case workingDirectoryChanged(String)
    case bell
    case exited(status: Int32)
}

/// One pane's shell: a PTY, the terminals it feeds, and the router between them.
///
/// Bytes from the PTY go to the shell terminal until the shell reports that a
/// command started. They then go to a new terminal owned by that command's block
/// until the command ends.
///
/// The read thread and the main thread share this state, guarded by `lock`. The
/// app can only reach it through `withState`, which takes the lock, so that
/// forgetting the lock is a compile error rather than a crash.
public final class PaneSession {
    public enum Phase: Equatable {
        /// No shell integration seen, so this behaves as a plain terminal.
        case plain
        /// The shell is drawing its prompt.
        case prompt
        /// The shell is waiting for a command.
        case ready
        /// A command is running in the last block.
        case running
        case exited
    }

    /// Warp's default limit for a single block.
    public static let maximumRowsPerBlock = 50_000

    let lock = OSAllocatedUnfairLock()
    private(set) var phase: Phase = .plain
    private(set) var shell: VTTerminal
    private(set) var blocks: [Block] = []
    private(set) var workingDirectory: String
    private(set) var cols: Int
    private(set) var rows: Int
    private(set) var cellWidth: Int
    private(set) var cellHeight: Int
    /// The checked-out branch, refreshed off the read thread at every prompt.
    private(set) var gitBranch: String?
    /// The PATH the shell itself is using, once it has reported it.
    private(set) var shellPath: String?
    /// Aliases and functions defined in the shell.
    private(set) var shellNames: [String] = []

    /// Called on the main thread.
    public var onEvent: ((SessionEvent) -> Void)?
    /// Called on the main thread after new output, at most once per wakeup.
    public var onNeedsDisplay: (() -> Void)?

    private var theme: Theme
    private var process: PTYProcess?
    private var target: VTTerminal
    private var nextBlockId = 1
    private var frameRequested = false
    private var pendingEvents: [RawEvent] = []
    /// Commands submitted before the shell could take them, oldest first.
    private var pendingCommands: [String] = []
    private var awaitingStringTerminator = false
    private var pendingWrites: [[UInt8]] = []
    private var wasFullScreen = false
    private var renderHeldSince: Double?
    private var bellPending = false
    private var integrationAnnounced = false
    /// Whether the shell was started with integration, so reports are on the way.
    private(set) var expectsIntegration = false
    private var showsStartup = false
    /// What the shell quotes in its reports. Everything in the stream can be printed
    /// by something else: a file being read, a background job at the prompt, or a
    /// remote shell with an integration of its own. Nil means no reports are expected.
    var reportToken: String?
    /// How long a program can hold drawing back, so one that never releases its
    /// hold can't freeze the pane.
    private static let maximumRenderHold: Double = 1

    private enum RawEvent {
        case promptStart
        case inputStart
        case outputStart(command: String)
        case commandEnd(exitCode: Int32?)
    }

    public init(cols: Int, rows: Int, cellWidth: Int, cellHeight: Int, theme: Theme, workingDirectory: String) {
        self.cols = cols
        self.rows = rows
        self.cellWidth = cellWidth
        self.cellHeight = cellHeight
        self.theme = theme
        self.workingDirectory = workingDirectory
        let shell = VTTerminal(cols: cols, rows: rows, cellWidth: cellWidth, cellHeight: cellHeight)
        self.shell = shell
        self.target = shell
        configure(shell)
        // The shell's reports can be long, such as the names of all its aliases.
        var limit = 256 * 1024
        _ = ghostty_terminal_set(shell.handle, GHOSTTY_TERMINAL_OPT_UNKNOWN_MAX_BYTES, &limit)
    }

    // MARK: Process

    public func start(launch: PTYProcess.Launch) throws {
        expectsIntegration = launch.hasIntegration
        reportToken = launch.integrationToken
        let process = try PTYProcess(
            launch: launch, cols: cols, rows: rows,
            widthPx: cols * cellWidth, heightPx: rows * cellHeight)
        self.process = process
        refreshBranch(for: workingDirectory)
        process.start(
            // Weak, because a pane can close while its shell is still printing.
            onData: { [weak self] in self?.ingest($0) },
            onExit: { [weak self] status in self?.processExited(status) })
    }

    public func terminate() {
        process?.terminate()
    }

    public func sendToProcess(_ bytes: [UInt8]) {
        process?.write(bytes)
    }

    /// Pastes through the library's encoder, which strips bytes that could
    /// otherwise break out of a bracketed paste and run as commands.
    public func paste(_ text: String) {
        lock.lock()
        let bracketed = target.isModeSet(2004)
        lock.unlock()

        process?.write(Self.encodedPaste(text, bracketed: bracketed))
    }

    private static func encodedPaste(_ text: String, bracketed: Bool) -> [UInt8] {
        var input = Array(text.utf8CString.dropLast())
        var output = [CChar](repeating: 0, count: input.count + 32)
        var written = 0
        let result = input.withUnsafeMutableBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                ghostty_paste_encode(source.baseAddress, source.count, bracketed,
                                     destination.baseAddress, destination.count, &written)
            }
        }
        guard result == GHOSTTY_SUCCESS else { return [] }
        return output[..<written].map { UInt8(bitPattern: $0) }
    }

    private func processExited(_ status: Int32) {
        lock.lock()
        phase = .exited
        lock.unlock()
        post(.exited(status: status))
    }

    // MARK: Router

    /// Feeds PTY output through the router. Public so tests can drive it
    /// without a process.
    public func ingest(_ bytes: UnsafeRawBufferPointer) {
        guard let base = bytes.bindMemory(to: UInt8.self).baseAddress else { return }
        let count = bytes.count

        lock.lock()
        var offset = 0

        // The previous read ended between the ESC and the \ of a string
        // terminator. The \ belongs to the terminal that saw the ESC.
        if awaitingStringTerminator {
            awaitingStringTerminator = false
            if base[0] == 0x5C {
                ghostty_terminal_vt_write(target.handle, base, 1)
                offset = 1
            }
            applyPendingEvents()
        }

        while offset < count {
            var stop = GhosttyTerminalWriteStop()
            stop.size = MemoryLayout<GhosttyTerminalWriteStop>.size
            let result = ghostty_terminal_vt_write_until(
                target.handle, base + offset, count - offset,
                UInt32(GHOSTTY_TERMINAL_BOUNDARY_OSC_END.rawValue), &stop)
            guard result == GHOSTTY_SUCCESS else { break }
            offset += stop.consumed

            if stop.end == GHOSTTY_TERMINAL_STRING_END_ST_ESC {
                guard offset < count else {
                    awaitingStringTerminator = true
                    break
                }
                if base[offset] == 0x5C {
                    ghostty_terminal_vt_write(target.handle, base + offset, 1)
                    offset += 1
                }
            }
            applyPendingEvents()
        }

        let isFullScreen = phase == .running && target.isAlternateScreen
        if isFullScreen != wasFullScreen {
            wasFullScreen = isFullScreen
            post(.fullScreenChanged(isFullScreen))
        }

        let writes = takeWrites()
        let requestFrame = !frameRequested
        frameRequested = true
        lock.unlock()

        for write in writes { process?.write(write) }
        if requestFrame { notifyNeedsDisplay() }
    }

    /// Replies are queued and written after the lock is released, because a full
    /// PTY buffer would otherwise stall everything waiting on that lock.
    private func takeWrites() -> [[UInt8]] {
        guard !pendingWrites.isEmpty else { return [] }
        let writes = pendingWrites
        pendingWrites.removeAll(keepingCapacity: true)
        return writes
    }

    private func notifyNeedsDisplay() {
        DispatchQueue.main.async { [weak self] in self?.onNeedsDisplay?() }
    }

    /// Runs under the lock.
    private func becomeReady() {
        phase = .ready
        post(.ready)
        // One at a time, so that each command starts from its own prompt.
        if !pendingCommands.isEmpty {
            pendingWrites.append(Self.encode(command: pendingCommands.removeFirst()))
        }
    }

    /// Runs under the lock, after the parser has stopped, because callbacks
    /// must not touch terminals while one is being written to.
    private func applyPendingEvents() {
        guard !pendingEvents.isEmpty else { return }
        let events = pendingEvents
        pendingEvents.removeAll(keepingCapacity: true)
        for event in events {
            switch event {
            case .promptStart:
                finishRunningBlock(exitCode: nil)
                phase = .prompt
                post(.promptStarted)
            case .inputStart:
                finishRunningBlock(exitCode: nil)
                becomeReady()
            case .outputStart(let command):
                startBlock(command: command)
            case .commandEnd(let exitCode):
                finishRunningBlock(exitCode: exitCode)
            }
        }
    }

    private func startBlock(command: String) {
        finishRunningBlock(exitCode: nil)
        let terminal = VTTerminal(cols: cols, rows: rows, cellWidth: cellWidth, cellHeight: cellHeight)
        configure(terminal)
        terminal.setScrollbackLimit(lines: Self.maximumRowsPerBlock)
        let block = Block(id: nextBlockId, terminal: terminal, command: command,
                          workingDirectory: workingDirectory, gitBranch: gitBranch, startedAt: Date())
        nextBlockId += 1
        blocks.append(block)
        target = terminal
        phase = .running
        post(.blockStarted(block))
    }

    private func finishRunningBlock(exitCode: Int32?) {
        guard phase == .running, let block = blocks.last else { return }
        block.finishedAt = Date()
        block.exitCode = exitCode
        target = shell
        phase = .prompt
        post(.blockFinished(block))
    }

    private func post(_ event: SessionEvent) {
        DispatchQueue.main.async { [weak self] in self?.onEvent?(event) }
    }

    // MARK: Commands

    /// Runs a command at the prompt, or holds it until the shell is ready.
    public func submit(command: String) {
        lock.lock()
        let ready = phase == .ready && pendingCommands.isEmpty
        if !ready { pendingCommands.append(command) }
        lock.unlock()
        if ready { process?.write(Self.encode(command: command)) }
    }

    /// A safety net for when the shell never reports that it's reading input, as
    /// can happen with an unusual line editor setup. The kernel buffers terminal
    /// input, so a command sent now is still read as soon as the shell gets there.
    public func assumeReadyIfStillAtPrompt() {
        lock.lock()
        if phase == .prompt { becomeReady() }
        let writes = takeWrites()
        lock.unlock()
        for write in writes { process?.write(write) }
    }

    /// Gives up on integration, so a command held for the prompt isn't lost.
    public func fallBackToPlainTerminal() {
        lock.lock()
        let commands = pendingCommands
        pendingCommands.removeAll()
        lock.unlock()
        for command in commands { process?.write(Self.encode(command: command)) }
        requestFrame()
    }

    /// Commands go through the paste encoder because the input can't show control
    /// characters, and the line editor would run them as keys. Those that still
    /// hold newlines or tabs after that are bracketed, so that the shell treats them
    /// as part of the buffer rather than as Enter or Tab.
    static func encode(command: String) -> [UInt8] {
        let needsBrackets = command.unicodeScalars.contains { $0.value < 0x20 }
        return encodedPaste(command, bracketed: needsBrackets) + [0x0D]
    }

    // MARK: Layout

    public func resize(cols: Int, rows: Int, cellWidth: Int, cellHeight: Int) {
        lock.lock()
        self.cols = cols
        self.rows = rows
        self.cellWidth = cellWidth
        self.cellHeight = cellHeight
        shell.resize(cols: cols, rows: rows, cellWidth: cellWidth, cellHeight: cellHeight)
        for block in blocks {
            block.terminal.resize(cols: cols, rows: rows, cellWidth: cellWidth, cellHeight: cellHeight)
            if block.filter != nil { rebuildFilter(of: block) }
        }
        frameRequested = true
        lock.unlock()
        process?.resize(cols: cols, rows: rows, widthPx: cols * cellWidth, heightPx: rows * cellHeight)
    }

    /// The renderer calls this once per frame. Returns whether output arrived
    /// since the last call.
    public func consumeFrameRequest() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let requested = frameRequested
        frameRequested = false
        return requested
    }

    public func requestFrame() {
        lock.lock()
        let shouldNotify = !frameRequested
        frameRequested = true
        lock.unlock()
        if shouldNotify { notifyNeedsDisplay() }
    }

    /// Whether a program has asked for drawing to wait, with synchronized output,
    /// so that a half-drawn frame is never shown.
    public var isHoldingFrames: Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let since = renderHeldSince else { return false }
        return ProcessInfo.processInfo.systemUptime - since < Self.maximumRenderHold
    }

    public var currentDirectory: String {
        withState { $0.session.workingDirectory }
    }

    public var currentBranch: String? {
        withState { $0.session.gitBranch }
    }

    /// What completion needs from the shell, read together under the lock.
    public var completionContext: (directory: String, path: String?, names: [String]) {
        withState { ($0.session.workingDirectory, $0.session.shellPath, $0.session.shellNames) }
    }

    /// Runs `body` holding the lock, with access to everything the read thread can
    /// change. The lock isn't recursive, so nothing in `body` may call back into a
    /// session method that takes it, and `State` must not be kept after `body` ends.
    public func withState<Result>(_ body: (State) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(State(session: self))
    }

    /// The shared state of a session, as seen from inside `withState`.
    public struct State {
        fileprivate let session: PaneSession

        public var phase: Phase { session.phase }
        public var blocks: [Block] { session.blocks }
        public var shell: VTTerminal { session.shell }
        public var cols: Int { session.cols }
        public var rows: Int { session.rows }
        public var hasIntegration: Bool { session.hasIntegration }
        public var expectsIntegration: Bool { session.expectsIntegration }
        public var routesInputToProgram: Bool { session.routesInputToProgram }
        public var isShowingStartup: Bool { session.isShowingStartup }
        /// The terminal that receives input and whose modes decide how keys encode.
        public var inputTerminal: VTTerminal { session.inputTerminal }

        public func terminal(of block: Block) -> VTTerminal { block.terminal }
        /// The terminal to draw, which is the filtered one while a filter is active.
        public func displayTerminal(of block: Block) -> VTTerminal { block.displayTerminal }
        public func isRunning(_ block: Block) -> Bool { block.isRunning }
        public func didFail(_ block: Block) -> Bool { block.didFail }
        public func exitCode(of block: Block) -> Int32? { block.exitCode }
        public func duration(of block: Block) -> TimeInterval { block.duration }
        public func outputText(of block: Block) -> String { block.outputText }
        public func hasFilter(_ block: Block) -> Bool { block.filter != nil }
    }

    /// Applies or clears a block's filter by rebuilding the terminal it draws from.
    public func setFilter(_ options: BlockFilterOptions?, on block: Block) {
        lock.lock()
        defer { lock.unlock() }
        block.filter = options
        rebuildFilter(of: block)
    }

    /// Refreshes the filter on a block that's still printing.
    public func refreshFilter(of block: Block) {
        lock.lock()
        defer { lock.unlock() }
        rebuildFilter(of: block)
    }

    private func rebuildFilter(of block: Block) {
        guard let options = block.filter else {
            block.filteredTerminal = nil
            return
        }
        var plain = block.terminal.rowTexts()
        let styled = block.terminal.styledRows()
        // Plain text trims rows that only have a background, so it can come up short.
        if plain.count < styled.count {
            plain += Array(repeating: "", count: styled.count - plain.count)
        }
        let source = styled.count == plain.count ? styled : plain
        let kept = options.keptRows(in: plain)
        let terminal = VTTerminal(cols: cols, rows: rows, cellWidth: cellWidth, cellHeight: cellHeight)
        terminal.apply(theme: theme)
        terminal.setScrollbackLimit(lines: Self.maximumRowsPerBlock)
        terminal.write(kept.map { source[$0] }.joined(separator: "\r\n"))
        block.filteredTerminal = terminal
    }

    /// The terminal that receives input and whose modes decide how keys encode.
    var inputTerminal: VTTerminal { target }

    /// Whether the shell has reported anything through its integration yet.
    var hasIntegration: Bool { phase != .plain || integrationAnnounced }

    /// Whether keys and the mouse belong to a program rather than to the block list.
    var routesInputToProgram: Bool { phase == .running || !hasIntegration || isShowingStartup }

    /// The shell's startup files printed something and there's still no prompt.
    var isShowingStartup: Bool { showsStartup && phase == .plain }

    public enum StartupProgress {
        /// The shell has reached a prompt, or never will report one.
        case finished
        /// Still starting, and silent so far.
        case quiet
        /// Still starting, and it has printed something.
        case waiting
    }

    /// Startup output normally stays hidden, but a shell that printed something and
    /// hasn't reached a prompt may well be asking a question, as an update check
    /// does. Nothing would ever happen if the user couldn't see it and answer it.
    public func revealStartupIfWaiting() -> StartupProgress {
        lock.lock()
        defer { lock.unlock() }
        guard phase == .plain, expectsIntegration else { return .finished }
        guard shell.contentRows() > 0 else { return .quiet }
        showsStartup = true
        frameRequested = true
        return .waiting
    }

    public func removeAllBlocks() {
        lock.lock()
        if phase == .running, let running = blocks.last {
            blocks = [running]
        } else {
            blocks.removeAll()
        }
        frameRequested = true
        lock.unlock()
        notifyNeedsDisplay()
    }

    // MARK: Terminal callbacks

    private func configure(_ terminal: VTTerminal) {
        terminal.apply(theme: theme)
        let handle = terminal.handle
        let userdata = Unmanaged.passUnretained(self).toOpaque()
        func set(_ option: GhosttyTerminalOption, _ value: UnsafeRawPointer?) {
            _ = ghostty_terminal_set(handle, option, value)
        }
        set(GHOSTTY_TERMINAL_OPT_USERDATA, userdata)
        set(GHOSTTY_TERMINAL_OPT_WRITE_PTY, unsafeBitCast(writePtyCallback, to: UnsafeRawPointer.self))
        set(GHOSTTY_TERMINAL_OPT_BELL, unsafeBitCast(bellCallback, to: UnsafeRawPointer.self))
        set(GHOSTTY_TERMINAL_OPT_TITLE_CHANGED, unsafeBitCast(titleCallback, to: UnsafeRawPointer.self))
        set(GHOSTTY_TERMINAL_OPT_PWD_CHANGED, unsafeBitCast(pwdCallback, to: UnsafeRawPointer.self))
        set(GHOSTTY_TERMINAL_OPT_SIZE, unsafeBitCast(sizeCallback, to: UnsafeRawPointer.self))
        set(GHOSTTY_TERMINAL_OPT_DEVICE_ATTRIBUTES, unsafeBitCast(deviceAttributesCallback, to: UnsafeRawPointer.self))
        set(GHOSTTY_TERMINAL_OPT_XTVERSION, unsafeBitCast(xtversionCallback, to: UnsafeRawPointer.self))
        set(GHOSTTY_TERMINAL_OPT_COLOR_SCHEME, unsafeBitCast(colorSchemeCallback, to: UnsafeRawPointer.self))
        set(GHOSTTY_TERMINAL_OPT_RENDER_HOLD, unsafeBitCast(renderHoldCallback, to: UnsafeRawPointer.self))
        var limit = 128
        _ = ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_UNKNOWN_MAX_BYTES, &limit)
        set(GHOSTTY_TERMINAL_OPT_UNKNOWN_SEQUENCE, unsafeBitCast(unknownSequenceCallback, to: UnsafeRawPointer.self))
    }

    fileprivate func handleWritePty(_ bytes: UnsafeBufferPointer<UInt8>) {
        // Runs under the lock, so a blocking PTY write here could deadlock.
        pendingWrites.append(Array(bytes))
    }

    /// The private `7701;key=token;value` channel from the shell integration. This is
    /// how the shell says everything, because only a report quoting the token can be
    /// trusted to come from it.
    fileprivate func handleReport(_ content: String) {
        guard let reportToken, content.hasPrefix("7701;"), let equals = content.firstIndex(of: "=") else { return }
        let key = content[content.index(content.startIndex, offsetBy: 5)..<equals]
        let fields = content[content.index(after: equals)...]
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
        guard fields.count == 2, fields[0] == reportToken else { return }
        let value = String(fields[1]).removingPercentEncoding ?? ""
        switch key {
        case "hello": integrationAnnounced = true
        case "path": shellPath = value
        case "names": shellNames = value.split(separator: " ").map(String.init)
        case "cwd": changeDirectory(to: value)
        case "prompt": pendingEvents.append(.promptStart)
        case "ready": pendingEvents.append(.inputStart)
        case "start": pendingEvents.append(.outputStart(command: value))
        case "done": pendingEvents.append(.commandEnd(exitCode: Int32(value)))
        default: break
        }
    }

    fileprivate func handleTitleChanged(_ terminal: GhosttyTerminal?) {
        guard terminal == target.handle else { return }
        post(.titleChanged(target.title))
    }

    /// For shells without integration, whose prompt may send OSC 7 itself. A program's
    /// own never counts: over ssh, it names a directory on another machine.
    fileprivate func handlePwdChanged(_ terminal: GhosttyTerminal?) {
        guard reportToken == nil, terminal == shell.handle else { return }
        changeDirectory(to: Self.path(fromPwd: shell.pwd))
    }

    private func changeDirectory(to path: String) {
        workingDirectory = path
        post(.workingDirectoryChanged(path))
        refreshBranch(for: path)
    }

    /// Reads the branch away from the read thread, because this is file I/O and a
    /// slow disk or network mount must never hold up parsing.
    private func refreshBranch(for path: String) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let branch = GitInfo.branch(at: path)
            guard let self else { return }
            self.lock.lock()
            let changed = self.workingDirectory == path && self.gitBranch != branch
            if changed { self.gitBranch = branch }
            self.lock.unlock()
            if changed { self.post(.gitBranchChanged(branch)) }
        }
    }

    /// Coalesced, because binary output can contain a bell every few hundred bytes.
    fileprivate func handleBell() {
        guard !bellPending else { return }
        bellPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.bellPending = false
            self.lock.unlock()
            self.onEvent?(.bell)
        }
    }

    fileprivate func handleRenderHold(_ held: Bool) {
        renderHeldSince = held ? ProcessInfo.processInfo.systemUptime : nil
    }

    fileprivate var sizeReport: GhosttySizeReportSize {
        GhosttySizeReportSize(rows: UInt16(clamping: rows), columns: UInt16(clamping: cols),
                              cell_width: UInt32(cellWidth), cell_height: UInt32(cellHeight))
    }

    fileprivate var isDarkTheme: Bool { theme.isDark }

    /// OSC 7 reports a file:// URL. Other reports are already plain paths.
    static func path(fromPwd value: String) -> String {
        guard value.hasPrefix("file://"), let url = URL(string: value) else { return value }
        return url.path
    }
}

extension GhosttyString {
    var swiftString: String {
        guard let ptr, len > 0 else { return "" }
        return String(decoding: UnsafeBufferPointer(start: ptr, count: len), as: UTF8.self)
    }
}

private func session(_ userdata: UnsafeMutableRawPointer?) -> PaneSession {
    Unmanaged<PaneSession>.fromOpaque(userdata!).takeUnretainedValue()
}

private let versionString = strdup("Rewarp 0.1")!

private let writePtyCallback: GhosttyTerminalWritePtyFn = { _, userdata, data, len in
    guard let data else { return }
    session(userdata).handleWritePty(UnsafeBufferPointer(start: data, count: len))
}

private let bellCallback: GhosttyTerminalBellFn = { _, userdata in
    session(userdata).handleBell()
}

private let titleCallback: GhosttyTerminalTitleChangedFn = { terminal, userdata in
    session(userdata).handleTitleChanged(terminal)
}

private let pwdCallback: GhosttyTerminalPwdChangedFn = { terminal, userdata in
    session(userdata).handlePwdChanged(terminal)
}

private let sizeCallback: GhosttyTerminalSizeFn = { _, userdata, out in
    out?.pointee = session(userdata).sizeReport
    return true
}

private let colorSchemeCallback: GhosttyTerminalColorSchemeFn = { _, userdata, out in
    out?.pointee = session(userdata).isDarkTheme ? GHOSTTY_COLOR_SCHEME_DARK : GHOSTTY_COLOR_SCHEME_LIGHT
    return true
}

private let deviceAttributesCallback: GhosttyTerminalDeviceAttributesFn = { _, _, out in
    guard let out else { return false }
    // Identifies as a VT220 with ANSI colour and clipboard, as Ghostty does.
    out.pointee.primary.conformance_level = 62
    withUnsafeMutableBytes(of: &out.pointee.primary.features) { raw in
        let features = raw.bindMemory(to: UInt16.self)
        features[0] = 22
        features[1] = 52
    }
    out.pointee.primary.num_features = 2
    out.pointee.secondary.device_type = 1
    out.pointee.secondary.firmware_version = 10
    out.pointee.secondary.rom_cartridge = 0
    out.pointee.tertiary.unit_id = 0
    return true
}

private let xtversionCallback: GhosttyTerminalXtversionFn = { _, _ in
    GhosttyString(ptr: UnsafeRawPointer(versionString).assumingMemoryBound(to: UInt8.self), len: strlen(versionString))
}

private let renderHoldCallback: GhosttyTerminalRenderHoldFn = { _, userdata, held in
    session(userdata).handleRenderHold(held)
}

private let unknownSequenceCallback: GhosttyTerminalUnknownSequenceFn = { _, userdata, sequence in
    guard let sequence, sequence.pointee.tag == GHOSTTY_TERMINAL_UNKNOWN_SEQUENCE_OSC else { return }
    session(userdata).handleReport(sequence.pointee.value.osc.content.swiftString)
}

