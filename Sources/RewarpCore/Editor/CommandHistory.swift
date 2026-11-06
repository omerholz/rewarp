import Foundation

/// Commands from the shell's own history file, plus this session's.
public final class CommandHistory {
    /// Oldest first, without repeats. A repeated command moves to the end.
    public private(set) var entries: [String] = []

    public init(entries initial: [String] = []) {
        // Walks backward so that loading a long file stays linear.
        var seen = Set<String>()
        var kept: [String] = []
        for entry in initial.reversed() {
            let trimmed = Self.trim(entry)
            if !trimmed.isEmpty, seen.insert(trimmed).inserted { kept.append(trimmed) }
        }
        entries = kept.reversed()
    }

    private static func trim(_ command: String) -> String {
        command.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func add(_ command: String) {
        // A leading space opts out of Rewarp history even if the shell's own
        // history policy differs. Inspect it before trimming away that signal.
        guard !command.hasPrefix(" ") else { return }
        let trimmed = Self.trim(command)
        guard !trimmed.isEmpty else { return }
        entries.removeAll { $0 == trimmed }
        entries.append(trimmed)
    }

    /// The most recent command that extends `prefix`.
    public func suggestion(for prefix: String) -> String? {
        guard !prefix.isEmpty else { return nil }
        // hasPrefix comes first because counting characters walks the whole string.
        return entries.last { $0.hasPrefix(prefix) && $0.utf8.count > prefix.utf8.count }
    }

    /// Most recent first. An empty prefix matches everything.
    public func matching(prefix: String, limit: Int) -> [String] {
        var results: [String] = []
        for entry in entries.reversed() where prefix.isEmpty || entry.hasPrefix(prefix) {
            results.append(entry)
            if results.count == limit { break }
        }
        return results
    }
}

/// Reads the history files of the shells Rewarp supports.
public enum ShellHistoryFile {
    public static func load(shell: String, environment: [String: String], home: String) -> [String] {
        switch (shell as NSString).lastPathComponent {
        case "zsh":
            let path = environment["HISTFILE"] ?? "\(home)/.zsh_history"
            return FileManager.default.contents(atPath: path).map(parseZsh) ?? []
        case "bash":
            let path = environment["HISTFILE"] ?? "\(home)/.bash_history"
            return FileManager.default.contents(atPath: path).map(parseBash) ?? []
        case "fish":
            let path = "\(home)/.local/share/fish/fish_history"
            return FileManager.default.contents(atPath: path).map(parseFish) ?? []
        default:
            return []
        }
    }

    /// zsh writes either bare lines or `: <time>:<duration>;<command>`. A newline
    /// inside a command is stored as backslash-newline, and bytes that clash with
    /// zsh's internal tokens are "metafied": 0x83 followed by the byte XOR 0x20.
    public static func parseZsh(_ data: Data) -> [String] {
        let bytes = unmetafy(data)
        var commands: [String] = []
        var current: [UInt8] = []
        var lineStart = 0

        func finish(lineEnd: Int) {
            var line = bytes[lineStart..<lineEnd]
            if line.last == 0x5C {
                line = line.dropLast()
                current.append(contentsOf: line)
                current.append(0x0A)
                return
            }
            current.append(contentsOf: line)
            var slice = current[...]
            if slice.first == 0x3A, slice.dropFirst().first == 0x20,
               let separator = slice.firstIndex(of: 0x3B) {
                slice = slice[(separator + 1)...]
            }
            if !slice.isEmpty {
                commands.append(String(decoding: slice, as: UTF8.self))
            }
            current.removeAll(keepingCapacity: true)
        }

        for index in bytes.indices where bytes[index] == 0x0A {
            finish(lineEnd: index)
            lineStart = index + 1
        }
        if lineStart < bytes.count { finish(lineEnd: bytes.count) }
        return commands
    }

    private static func unmetafy(_ data: Data) -> [UInt8] {
        var output: [UInt8] = []
        output.reserveCapacity(data.count)
        var iterator = data.makeIterator()
        while let byte = iterator.next() {
            if byte == 0x83 {
                if let next = iterator.next() { output.append(next ^ 0x20) }
            } else {
                output.append(byte)
            }
        }
        return output
    }

    /// Lines starting with `#<digits>` are timestamps from HISTTIMEFORMAT.
    public static func parseBash(_ data: Data) -> [String] {
        String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .filter { line in
                !(line.hasPrefix("#") && line.dropFirst().allSatisfy(\.isNumber) && line.count > 1)
            }
            .map(String.init)
    }

    /// fish's file is close to YAML: `- cmd: <command>` then metadata lines.
    public static func parseFish(_ data: Data) -> [String] {
        String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .compactMap { line -> String? in
                guard line.hasPrefix("- cmd: ") else { return nil }
                return String(line.dropFirst(7))
                    .replacingOccurrences(of: "\\n", with: "\n")
                    .replacingOccurrences(of: "\\\\", with: "\\")
            }
    }
}
