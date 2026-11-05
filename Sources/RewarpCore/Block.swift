import Foundation

/// One command and its output. Each block owns a terminal, so anything the
/// command does to its screen, such as clearing scrollback, stays contained.
///
/// The public fields never change, apart from `isBookmarked`, which only the main
/// thread touches. Everything the read thread writes goes through
/// `PaneSession.withState`.
public final class Block {
    public let id: Int
    let terminal: VTTerminal
    public let command: String
    public let workingDirectory: String
    public let gitBranch: String?
    public let startedAt: Date
    var finishedAt: Date?
    var exitCode: Int32?
    public var isBookmarked = false
    /// What's on screen while a filter is active. Filtering hides rows and never
    /// touches the block's real output.
    var filter: BlockFilterOptions?
    var filteredTerminal: VTTerminal?

    init(id: Int, terminal: VTTerminal, command: String, workingDirectory: String, gitBranch: String?, startedAt: Date) {
        self.id = id
        self.terminal = terminal
        self.command = command
        self.workingDirectory = workingDirectory
        self.gitBranch = gitBranch
        self.startedAt = startedAt
    }

    var isRunning: Bool { finishedAt == nil }

    var didFail: Bool {
        guard let exitCode else { return false }
        return exitCode != 0
    }

    var duration: TimeInterval {
        (finishedAt ?? Date()).timeIntervalSince(startedAt)
    }
}

extension Block {
    /// The terminal to draw, which is the filtered one while a filter is active.
    var displayTerminal: VTTerminal { filteredTerminal ?? terminal }

    /// The output as text, without the blank rows that follow it.
    var outputText: String {
        var text = terminal.plainText()
        while text.last == "\n" { text.removeLast() }
        return text
    }
}
