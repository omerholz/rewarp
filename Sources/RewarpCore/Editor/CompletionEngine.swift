import Foundation

/// Makes text safe to put on a shell command line.
///
/// Candidates come from places an attacker can control, such as the branch names
/// and Makefile targets of a cloned repository. If one reached the input unquoted,
/// pressing Enter would run whatever it contained.
public enum ShellQuoting {
    /// Backslash-escapes anything that isn't known to be literal. Backslashes are
    /// used rather than quotes so that a shared prefix of two escaped strings can
    /// be filled in, with no quote left open.
    public static func escape(_ text: String) -> String {
        var output = ""
        for scalar in text.unicodeScalars {
            if !isLiteral(scalar) { output.append("\\") }
            output.unicodeScalars.append(scalar)
        }
        return output
    }

    /// Paths keep a leading tilde bare, because it only expands when unquoted.
    public static func escape(path: String) -> String {
        guard path.hasPrefix("~") else { return escape(path) }
        return "~" + escape(String(path.dropFirst()))
    }

    /// A newline can't be backslash-escaped, since that means a line continuation,
    /// and other control characters can hide what a command really does. Text
    /// containing them is never offered.
    public static func containsControlCharacters(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.value < 0x20 || (0x7F...0x9F).contains($0.value) }
    }

    private static func isLiteral(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "a"..."z", "A"..."Z", "0"..."9", "_", "-", ".", "/", "+", ",", "@", ":", "%":
            return true
        default:
            return scalar.value >= 0xA0
        }
    }
}

public struct Completion: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case command, directory, file, flag, branch, tag, host, variable, script, subcommand
    }

    /// The name as it really is, for showing and for matching against.
    public var text: String
    /// What goes in the input. Quoted unless a source deliberately says otherwise,
    /// so that a new source can't forget to.
    public var insertion: String
    public var kind: Kind
    public var detail: String?
    /// Whether accepting it should add a space, which a directory shouldn't.
    public var appendsSpace: Bool

    public init(text: String, kind: Kind, detail: String? = nil, appendsSpace: Bool = true,
                insertion: String? = nil) {
        self.text = text
        self.insertion = insertion ?? ShellQuoting.escape(text)
        self.kind = kind
        self.detail = detail
        self.appendsSpace = appendsSpace
    }
}

public struct CompletionResult: Equatable, Sendable {
    /// The UTF-16 range in the input that an item replaces.
    public var range: Range<Int>
    public var items: [Completion]
    /// What every item's insertion starts with, for filling in straight away.
    public var commonPrefix: String
}

/// Works out what's being typed and offers ways to finish it.
public final class CompletionEngine {
    /// Things the shell knows about that aren't on disk, such as aliases.
    public var shellNames: [String] = []

    private let fileManager = FileManager.default
    private var pathCache: (path: String, names: [String])?

    public init() {}

    public func complete(line: String, cursor: Int, directory: String, environment: [String: String]) -> CompletionResult {
        let context = Self.context(line: line, cursor: cursor)
        let word = context.word
        var items: [Completion]

        if word.hasPrefix("$") {
            let prefix = String(word.dropFirst())
            // The dollar sign has to stay bare, so only real names qualify.
            items = environment.keys.sorted().filter(Self.isVariableName).map {
                Completion(text: "$\($0)", kind: .variable, insertion: "$\($0)")
            }
            return finish(items, query: prefix, queryPrefix: "$", range: context.range)
        }

        if context.isCommandPosition {
            if Self.looksLikePath(word) {
                items = paths(for: word, directory: directory, environment: environment)
                return finishPaths(items, word: word, range: context.range)
            }
            items = commands(environment: environment)
        } else {
            items = arguments(context: context, directory: directory, environment: environment)
            if items.isEmpty || Self.looksLikePath(word) {
                let found = paths(for: word, directory: directory, environment: environment)
                return finishPaths(found, word: word, range: context.range)
            }
        }
        return finish(items, query: word, queryPrefix: "", range: context.range)
    }

    private func finish(_ items: [Completion], query: String, queryPrefix: String, range: Range<Int>) -> CompletionResult {
        let scored = items.compactMap { item -> (Completion, Int)? in
            let candidate = String(item.text.dropFirst(queryPrefix.count))
            guard let match = FuzzyMatcher.match(query, in: candidate) else { return nil }
            return (item, match.score)
        }
        var seen = Set<String>()
        let sorted = scored
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.text < $1.0.text }
            .map(\.0)
            .filter { seen.insert($0.text).inserted }
        return result(from: sorted, literal: queryPrefix + query, range: range)
    }

    /// Fuzzy matches are only a fallback. If anything starts with what was typed,
    /// a loose match must not stop Tab from finishing the word.
    private func result(from sorted: [Completion], literal: String, range: Range<Int>) -> CompletionResult {
        let safe = sorted.filter { !ShellQuoting.containsControlCharacters($0.text) }
        let lowered = literal.lowercased()
        let startsWith = safe.filter { $0.text.lowercased().hasPrefix(lowered) }
        let items = Array((startsWith.isEmpty ? safe : startsWith).prefix(200))
        let exact = items.filter { $0.text.hasPrefix(literal) }
        let prefix = !items.isEmpty && exact.count == items.count
            ? Self.withoutDanglingEscape(Self.commonPrefix(of: items.map(\.insertion))) : literal
        return CompletionResult(range: range, items: items, commonPrefix: prefix)
    }

    private func finishPaths(_ items: [Completion], word: String, range: Range<Int>) -> CompletionResult {
        let (directory, name) = Self.split(path: word)
        return finish(items, query: name, queryPrefix: directory, range: range)
    }

    // MARK: Parsing

    struct Context {
        var words: [String]
        var word: String
        var range: Range<Int>
        var isCommandPosition: Bool
    }

    /// Finds the word at the cursor and the simple command it belongs to.
    static func context(line: String, cursor: Int) -> Context {
        let utf16 = Array(line.utf16)
        let end = min(cursor, utf16.count)
        let before = String(decoding: utf16[..<end], as: UTF16.self)

        var words: [String] = []
        var isCommand = true
        for token in ShellLexer.tokens(in: before) {
            switch token.kind {
            case .controlOperator:
                words.removeAll()
                isCommand = true
            case .comment, .redirect:
                break
            case .command:
                words.append(token.text)
                isCommand = false
            case .flag, .string, .variable, .unterminated, .argument:
                // Assignments before a command don't count as its words.
                if isCommand, token.kind == .argument, token.text.contains("=") { continue }
                words.append(token.text)
            }
        }

        var openQuote: UInt16?
        var scan = 0
        var lastBreak = 0
        while scan < end {
            let unit = utf16[scan]
            if unit == 0x5C {
                scan += 2
                continue
            }
            if unit == 0x22 || unit == 0x27 {
                // A quote only closes the kind that opened it, so `"it's` stays open.
                if openQuote == nil {
                    openQuote = unit
                } else if openQuote == unit {
                    openQuote = nil
                }
            }
            if openQuote == nil, unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x7C || unit == 0x26
                || unit == 0x3B || unit == 0x28 || unit == 0x3C || unit == 0x3E || unit == 0x3D {
                lastBreak = scan + 1
            }
            scan += 1
        }
        let start = lastBreak
        let word = Self.unescape(String(decoding: utf16[start..<end], as: UTF16.self))

        let endsInSpace = start == end
        var previous = words
        if !endsInSpace, !previous.isEmpty { previous.removeLast() }
        return Context(words: previous, word: word, range: start..<end, isCommandPosition: previous.isEmpty)
    }

    static func unescape(_ word: String) -> String {
        var output = ""
        var escaped = false
        for character in word {
            if escaped {
                output.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                output.append(character)
            }
        }
        return output
    }

    private static func isVariableName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first, first != "_" || name.count > 1 else { return false }
        func isLetter(_ scalar: Unicode.Scalar) -> Bool {
            ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || scalar == "_"
        }
        return isLetter(first) && name.unicodeScalars.allSatisfy { isLetter($0) || ("0"..."9").contains($0) }
    }

    private static func looksLikePath(_ word: String) -> Bool {
        word.hasPrefix("~") || word.contains("/")
    }

    static func split(path word: String) -> (directory: String, name: String) {
        guard let slash = word.lastIndex(of: "/") else { return ("", word) }
        return (String(word[...slash]), String(word[word.index(after: slash)...]))
    }

    static func commonPrefix(of strings: [String]) -> String {
        guard var prefix = strings.first else { return "" }
        for string in strings.dropFirst() {
            prefix = String(prefix.commonPrefix(with: string))
            if prefix.isEmpty { break }
        }
        return prefix
    }

    /// A shared prefix can stop between a backslash and the character it escapes.
    private static func withoutDanglingEscape(_ text: String) -> String {
        text.reversed().prefix { $0 == "\\" }.count % 2 == 1 ? String(text.dropLast()) : text
    }

    // MARK: Sources

    private func commands(environment: [String: String]) -> [Completion] {
        let path = environment["PATH"] ?? ""
        if pathCache?.path != path {
            var names = Set<String>()
            for directory in path.split(separator: ":") {
                let entries = (try? fileManager.contentsOfDirectory(atPath: String(directory))) ?? []
                for entry in entries where !entry.hasPrefix(".") { names.insert(entry) }
            }
            pathCache = (path, names.sorted())
        }
        let builtins = Self.shellBuiltins.map { Completion(text: $0, kind: .command, detail: "builtin") }
        let external = pathCache?.names.map { Completion(text: $0, kind: .command) } ?? []
        let shell = shellNames.map { Completion(text: $0, kind: .command, detail: "alias") }
        return shell + builtins + external
    }

    private func paths(for word: String, directory: String, environment: [String: String],
                       directoriesOnly: Bool = false) -> [Completion] {
        let (directoryPart, namePart) = Self.split(path: word)
        var base = directoryPart
        if base.hasPrefix("~") {
            let home = environment["HOME"] ?? NSHomeDirectory()
            base = home + base.dropFirst()
        }
        if !base.hasPrefix("/") { base = (directory as NSString).appendingPathComponent(base) }

        let entries = (try? fileManager.contentsOfDirectory(atPath: base)) ?? []
        var items: [Completion] = []
        if namePart.isEmpty || namePart.hasPrefix(".") {
            for name in ["./", "../"] {
                let text = directoryPart + name
                items.append(Completion(text: text, kind: .directory, appendsSpace: false,
                                        insertion: ShellQuoting.escape(path: text)))
            }
        }
        for entry in entries {
            // Dotfiles are hidden until asked for, as in a shell.
            if entry.hasPrefix("."), !namePart.hasPrefix(".") { continue }
            // Filtered by name first, since the check below is a disk access per file.
            guard FuzzyMatcher.match(namePart, in: entry) != nil else { continue }
            var isDirectory: ObjCBool = false
            let full = (base as NSString).appendingPathComponent(entry)
            // fileExists follows symlinks, so links to directories count.
            fileManager.fileExists(atPath: full, isDirectory: &isDirectory)
            if directoriesOnly, !isDirectory.boolValue { continue }
            let text = isDirectory.boolValue ? "\(directoryPart)\(entry)/" : directoryPart + entry
            // A tilde only stays bare when it was typed. One from a file's name would
            // otherwise turn that file into a home directory.
            let escaped = directoryPart.hasPrefix("~") ? ShellQuoting.escape(path: text) : ShellQuoting.escape(text)
            // Shell quoting does not stop a program treating a leading dash as
            // an option. A relative path keeps this completion a file argument.
            let insertion = directoryPart.isEmpty && entry.hasPrefix("-") ? "./" + escaped : escaped
            items.append(Completion(text: text, kind: isDirectory.boolValue ? .directory : .file,
                                    appendsSpace: !isDirectory.boolValue, insertion: insertion))
        }
        return items
    }

    private func arguments(context: Context, directory: String, environment: [String: String]) -> [Completion] {
        guard let command = context.words.first else { return [] }
        let word = context.word
        switch command {
        case "cd", "pushd", "rmdir":
            return paths(for: word, directory: directory, environment: environment, directoriesOnly: true)
        case "git":
            return git(context: context, directory: directory)
        case "ssh", "scp", "sftp", "mosh":
            return sshHosts(environment: environment)
        case "npm", "yarn", "pnpm", "bun":
            if context.words.count == 1 {
                let verbs = ["install", "run", "test", "start", "build", "publish", "init", "add", "remove", "update", "exec"]
                return verbs.map { Completion(text: $0, kind: .subcommand) } + packageScripts(directory: directory)
            }
            if context.words.dropFirst().first == "run" { return packageScripts(directory: directory) }
            return []
        case "make", "gmake":
            return makeTargets(directory: directory)
        default:
            return []
        }
    }

    private static let shellBuiltins = [
        "alias", "bg", "bindkey", "break", "builtin", "cd", "command", "continue", "declare", "dirs", "disown",
        "echo", "eval", "exec", "exit", "export", "fc", "fg", "getopts", "hash", "history", "jobs", "kill", "let",
        "local", "popd", "print", "printf", "pushd", "pwd", "read", "readonly", "return", "set", "shift", "source",
        "test", "times", "trap", "type", "typeset", "ulimit", "umask", "unalias", "unset", "wait", "whence", "which",
    ]

    private static let gitSubcommands: [(String, String)] = [
        ("add", "Stage changes"), ("bisect", "Find a commit by binary search"), ("blame", "Show who changed each line"),
        ("branch", "List or change branches"), ("checkout", "Switch branches or restore files"),
        ("cherry-pick", "Apply a commit"), ("clean", "Remove untracked files"), ("clone", "Copy a repository"),
        ("commit", "Record changes"), ("config", "Get or set options"), ("diff", "Show changes"),
        ("fetch", "Download from a remote"), ("grep", "Search tracked files"), ("init", "Create a repository"),
        ("log", "Show history"), ("merge", "Join histories"), ("mv", "Move a file"), ("pull", "Fetch and merge"),
        ("push", "Upload to a remote"), ("rebase", "Reapply commits"), ("reflog", "Show reference history"),
        ("remote", "Manage remotes"), ("reset", "Move the branch head"), ("restore", "Restore files"),
        ("revert", "Undo a commit"), ("rm", "Remove a file"), ("show", "Show an object"),
        ("stash", "Set changes aside"), ("status", "Show the working tree"), ("switch", "Switch branches"),
        ("tag", "Manage tags"), ("worktree", "Manage worktrees"),
    ]

    private func git(context: Context, directory: String) -> [Completion] {
        if context.words.count == 1 {
            return Self.gitSubcommands.map { Completion(text: $0.0, kind: .subcommand, detail: $0.1) }
        }
        switch context.words[1] {
        case "checkout", "switch", "merge", "rebase", "branch", "cherry-pick", "reset", "log", "diff", "show":
            return Self.gitRefs(directory: directory)
        case "push", "pull", "fetch":
            if context.words.count == 2 { return Self.gitRemotes(directory: directory) }
            return Self.gitRefs(directory: directory)
        default:
            return []
        }
    }

    /// Reads refs from disk, which is far cheaper than starting git on each Tab.
    private static func gitRefs(directory: String) -> [Completion] {
        guard let git = GitInfo.commonDirectory(from: directory) else { return [] }
        var items: [Completion] = []

        func walk(_ url: URL, prefix: String, kind: Completion.Kind) {
            let manager = FileManager.default
            for entry in (try? manager.contentsOfDirectory(atPath: url.path)) ?? [] {
                let child = url.appendingPathComponent(entry)
                var isDirectory: ObjCBool = false
                manager.fileExists(atPath: child.path, isDirectory: &isDirectory)
                if isDirectory.boolValue {
                    walk(child, prefix: "\(prefix)\(entry)/", kind: kind)
                } else if entry != "HEAD" {
                    items.append(Completion(text: prefix + entry, kind: kind))
                }
            }
        }
        walk(git.appendingPathComponent("refs/heads"), prefix: "", kind: .branch)
        walk(git.appendingPathComponent("refs/tags"), prefix: "", kind: .tag)
        walk(git.appendingPathComponent("refs/remotes"), prefix: "", kind: .branch)

        // Packed refs hold whatever hasn't changed recently.
        if let packed = try? String(contentsOf: git.appendingPathComponent("packed-refs"), encoding: .utf8) {
            for line in packed.split(separator: "\n") where !line.hasPrefix("#") && !line.hasPrefix("^") {
                guard let reference = line.split(separator: " ").last else { continue }
                if reference.hasPrefix("refs/heads/") {
                    items.append(Completion(text: String(reference.dropFirst(11)), kind: .branch))
                } else if reference.hasPrefix("refs/tags/") {
                    items.append(Completion(text: String(reference.dropFirst(10)), kind: .tag))
                } else if reference.hasPrefix("refs/remotes/"), !reference.hasSuffix("/HEAD") {
                    items.append(Completion(text: String(reference.dropFirst(13)), kind: .branch))
                }
            }
        }
        return items
    }

    private static func gitRemotes(directory: String) -> [Completion] {
        guard let git = GitInfo.commonDirectory(from: directory) else { return [] }
        let remotes = (try? FileManager.default.contentsOfDirectory(
            atPath: git.appendingPathComponent("refs/remotes").path)) ?? []
        return remotes.map { Completion(text: $0, kind: .host) }
    }

    private func sshHosts(environment: [String: String]) -> [Completion] {
        let home = environment["HOME"] ?? NSHomeDirectory()
        var hosts = Set<String>()
        if let config = try? String(contentsOfFile: "\(home)/.ssh/config", encoding: .utf8) {
            for line in config.split(separator: "\n") {
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                guard parts.first?.lowercased() == "host" else { continue }
                for host in parts.dropFirst() where !host.contains("*") && !host.contains("?") {
                    hosts.insert(String(host))
                }
            }
        }
        if let known = try? String(contentsOfFile: "\(home)/.ssh/known_hosts", encoding: .utf8) {
            for line in known.split(separator: "\n") where !line.hasPrefix("|") && !line.hasPrefix("#") {
                guard let field = line.split(separator: " ").first else { continue }
                for host in field.split(separator: ",") { hosts.insert(String(host)) }
            }
        }
        return hosts.sorted().map { Completion(text: $0, kind: .host) }
    }

    private func packageScripts(directory: String) -> [Completion] {
        let url = URL(fileURLWithPath: directory).appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: url),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let scripts = object["scripts"] as? [String: Any] else { return [] }
        return scripts.keys.sorted().map {
            Completion(text: $0, kind: .script, detail: scripts[$0] as? String)
        }
    }

    private func makeTargets(directory: String) -> [Completion] {
        let url = URL(fileURLWithPath: directory).appendingPathComponent("Makefile")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var targets = Set<String>()
        for line in text.split(separator: "\n") {
            guard let first = line.first, !first.isWhitespace, first != "#", first != ".",
                  let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon]
            if name.contains("=") || name.contains("$") || name.contains("%") { continue }
            for target in name.split(separator: " ") { targets.insert(String(target)) }
        }
        return targets.sorted().map { Completion(text: $0, kind: .script) }
    }
}
