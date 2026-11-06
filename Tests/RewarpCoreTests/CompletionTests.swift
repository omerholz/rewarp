import Foundation
import Testing
@testable import RewarpCore

private final class Sandbox {
    let root: URL

    init(_ layout: [String]) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("rewarp-completion-\(UUID().uuidString)")
        for path in layout {
            let url = root.appendingPathComponent(path)
            if path.hasSuffix("/") {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try "".write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func complete(_ line: String, cursor: Int? = nil, environment: [String: String] = [:]) -> CompletionResult {
        let engine = CompletionEngine()
        return engine.complete(line: line, cursor: cursor ?? line.utf16.count, directory: root.path,
                               environment: environment)
    }
}

/// Asks a real shell what it reads a piece of command line as.
private func shellWords(_ line: String, shell: String) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: shell)
    process.arguments = shell.hasSuffix("zsh") ? ["-f", "-c", "printf '<%s>' \(line)"] : ["-c", "printf '<%s>' \(line)"]
    // If quoting ever fails, a hostile name like `a>b` really runs, and any file it
    // creates has to land somewhere disposable.
    process.currentDirectoryURL = FileManager.default.temporaryDirectory
    let output = Pipe()
    process.standardOutput = output
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
}

@Suite("Shell quoting")
struct ShellQuotingTests {
    static let hostile = [
        "$(touch /tmp/rewarp-pwned)", "`touch /tmp/rewarp-pwned`", "a;touch /tmp/rewarp-pwned", "a&&b", "a|b", "a>b",
        "a b", "it's", "say \"hi\"", "back\\slash", "$HOME", "${HOME}", "*", "?", "[a]", "{a,b}", "#hash", "~root",
        "=ls", "!bang", "a=b", "^up", "tab\there".replacingOccurrences(of: "\t", with: "-"), "日本語", "(x)",
    ]

    @Test("zsh reads every hostile name as one literal word", arguments: hostile)
    func zsh(_ name: String) throws {
        #expect(try shellWords(ShellQuoting.escape(name), shell: "/bin/zsh") == "<\(name)>")
    }

    @Test("bash reads every hostile name as one literal word", arguments: hostile)
    func bash(_ name: String) throws {
        #expect(try shellWords(ShellQuoting.escape(name), shell: "/bin/bash") == "<\(name)>")
    }

    @Test("A prefix of an escaped name is still valid on its own")
    func prefixStaysValid() throws {
        let prefix = String(ShellQuoting.escape("my file").dropLast(2))
        #expect(try shellWords(prefix, shell: "/bin/zsh") == "<my fi>")
    }

    @Test("A leading tilde stays bare in paths, and only there")
    func tilde() {
        #expect(ShellQuoting.escape(path: "~/a b") == "~/a\\ b")
        #expect(ShellQuoting.escape("~/a") == "\\~/a")
    }

    @Test("Control characters are detected")
    func controlCharacters() {
        #expect(ShellQuoting.containsControlCharacters("a\nb"))
        #expect(ShellQuoting.containsControlCharacters("a\u{1b}[2Jb"))
        #expect(ShellQuoting.containsControlCharacters("a\u{9b}b"))
        #expect(!ShellQuoting.containsControlCharacters("plain 日本語"))
    }
}

@Suite("Hostile completion sources")
struct HostileCompletionTests {
    private func write(_ text: String, to path: String, in sandbox: Sandbox) throws {
        let url = sandbox.root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test("A completed filename is not interpreted as a program option", arguments: ["-n", "--help"])
    func leadingDashFile(_ name: String) throws {
        let sandbox = try Sandbox([name])
        let contents = "literal file argument\n"
        try write(contents, to: name, in: sandbox)
        let completion = try #require(sandbox.complete("cat \(name)").items.first { $0.text == name })
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-f", "-c", "cat \(completion.insertion)"]
        process.currentDirectoryURL = sandbox.root
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(String(decoding: data, as: UTF8.self) == contents)
    }

    @Test("A branch name can't run a command")
    func branch() throws {
        let sandbox = try Sandbox([".git/refs/heads/$(id)"])
        #expect(sandbox.complete("git checkout ").items.first?.insertion == "\\$\\(id\\)")
    }

    @Test("A packed ref can't run a command")
    func packedRef() throws {
        let sandbox = try Sandbox([".git/HEAD"])
        try write("abc refs/heads/`id`\n", to: ".git/packed-refs", in: sandbox)
        #expect(sandbox.complete("git checkout ").items.first?.insertion == "\\`id\\`")
    }

    @Test("A Makefile target can't run a command")
    func makeTarget() throws {
        let sandbox = try Sandbox([])
        try write("a;id:\n", to: "Makefile", in: sandbox)
        #expect(sandbox.complete("make ").items.first?.insertion == "a\\;id")
    }

    @Test("An npm script name can't run a command")
    func npmScript() throws {
        let sandbox = try Sandbox([])
        try write("{\"scripts\":{\"x; id\":\"y\"}}", to: "package.json", in: sandbox)
        #expect(sandbox.complete("npm run ").items.first?.insertion == "x\\;\\ id")
    }

    @Test("An ssh host can't run a command")
    func sshHost() throws {
        let sandbox = try Sandbox([])
        try write("Host $(id)\n", to: ".ssh/config", in: sandbox)
        let items = sandbox.complete("ssh ", environment: ["HOME": sandbox.root.path]).items
        #expect(items.first?.insertion == "\\$\\(id\\)")
    }

    @Test("A filename with a newline is never offered")
    func newlineInName() throws {
        let sandbox = try Sandbox(["safe.txt", "evil\nid"])
        #expect(sandbox.complete("cat ").items.map(\.text).contains("safe.txt"))
        #expect(!sandbox.complete("cat ").items.contains { $0.text.contains("evil") })
    }

    @Test("A filename with escape sequences is never offered")
    func escapeInName() throws {
        let sandbox = try Sandbox(["evil\u{1b}[2J"])
        #expect(!sandbox.complete("cat ").items.contains { $0.text.contains("evil") })
    }

    @Test("A variable with an odd name is never offered, since it stays unquoted")
    func oddVariable() throws {
        let sandbox = try Sandbox([])
        let items = sandbox.complete("echo $", environment: ["GOOD": "1", "BA(D": "1"]).items.map(\.insertion)
        #expect(items == ["$GOOD"])
    }

    @Test("A shared prefix is filled in escaped")
    func commonPrefixEscaped() throws {
        let sandbox = try Sandbox(["a;b-one", "a;b-two"])
        #expect(sandbox.complete("cat a").commonPrefix == "a\\;b-")
    }
}

@Suite("Fuzzy matching")
struct FuzzyMatcherTests {
    @Test("Letters must appear in order")
    func subsequence() {
        #expect(FuzzyMatcher.match("gst", in: "git status") != nil)
        #expect(FuzzyMatcher.match("tsg", in: "git status") == nil)
    }

    @Test("Case doesn't matter")
    func caseInsensitive() {
        #expect(FuzzyMatcher.match("GIT", in: "git") != nil)
    }

    @Test("A prefix beats a scattered match")
    func prefixWins() throws {
        let prefix = try #require(FuzzyMatcher.match("che", in: "checkout"))
        let scattered = try #require(FuzzyMatcher.match("che", in: "cherry-pick-the-other"))
        let inside = try #require(FuzzyMatcher.match("che", in: "archive"))
        #expect(prefix.score > inside.score)
        #expect(scattered.score > inside.score)
    }

    @Test("Positions are reported for highlighting")
    func positions() {
        #expect(FuzzyMatcher.match("ab", in: "xaxb")?.positions == [1, 3])
    }

    @Test("An empty query matches everything")
    func empty() {
        #expect(FuzzyMatcher.match("", in: "anything")?.score == 0)
    }
}

@Suite("Completion context")
struct CompletionContextTests {
    @Test("The first word is in command position")
    func commandPosition() {
        let context = CompletionEngine.context(line: "gi", cursor: 2)
        #expect(context.isCommandPosition)
        #expect(context.word == "gi")
        #expect(context.range == 0..<2)
    }

    @Test("After a space the word is an argument")
    func argument() {
        let context = CompletionEngine.context(line: "git ", cursor: 4)
        #expect(!context.isCommandPosition)
        #expect(context.words == ["git"])
        #expect(context.word == "")
    }

    @Test("A new command starts after && and pipes")
    func afterOperators() {
        #expect(CompletionEngine.context(line: "ls && gi", cursor: 8).isCommandPosition)
        #expect(CompletionEngine.context(line: "ls | gr", cursor: 7).isCommandPosition)
    }

    @Test("Environment prefixes don't count as the command")
    func environmentPrefix() {
        #expect(CompletionEngine.context(line: "FOO=1 gi", cursor: 8).isCommandPosition)
    }

    @Test("The cursor decides, not the end of the line")
    func midLine() {
        let context = CompletionEngine.context(line: "git che main", cursor: 7)
        #expect(context.word == "che")
        #expect(context.range == 4..<7)
    }

    @Test("A quote only closes the kind that opened it")
    func mixedQuotes() {
        #expect(CompletionEngine.context(line: "echo \"it's a", cursor: 12).range == 5..<12)
    }

    @Test("Escaped spaces stay inside a word")
    func escapedSpace() {
        #expect(CompletionEngine.context(line: "cat my\\ fi", cursor: 10).word == "my fi")
    }
}

@Suite("Completion sources")
struct CompletionSourceTests {
    @Test("Files and directories complete, with directories left open")
    func paths() throws {
        let sandbox = try Sandbox(["notes.txt", "src/"])
        let items = sandbox.complete("cat ").items
        #expect(items.contains { $0.text == "notes.txt" && $0.kind == .file && $0.appendsSpace })
        #expect(items.contains { $0.text == "src/" && $0.kind == .directory && !$0.appendsSpace })
    }

    @Test("cd only offers directories")
    func cdDirectories() throws {
        let sandbox = try Sandbox(["notes.txt", "src/"])
        let items = sandbox.complete("cd ").items
        #expect(items.contains { $0.text == "src/" })
        #expect(!items.contains { $0.text == "notes.txt" })
    }

    @Test("Dotfiles appear once a dot is typed")
    func dotfiles() throws {
        let sandbox = try Sandbox([".env", "visible"])
        #expect(!sandbox.complete("cat ").items.contains { $0.text == ".env" })
        #expect(sandbox.complete("cat .").items.contains { $0.text == ".env" })
    }

    @Test(". and .. are offered")
    func dotEntries() throws {
        let sandbox = try Sandbox(["a"])
        let items = sandbox.complete("cd ").items
        #expect(items.contains { $0.text == "./" })
        #expect(items.contains { $0.text == "../" })
    }

    @Test("Nested paths keep their prefix")
    func nested() throws {
        let sandbox = try Sandbox(["src/main.swift"])
        #expect(sandbox.complete("cat src/ma").items.map(\.text) == ["src/main.swift"])
    }

    @Test("Names with spaces show as they are and insert escaped")
    func escaping() throws {
        let sandbox = try Sandbox(["my file.txt"])
        let item = sandbox.complete("cat my").items.first
        #expect(item?.text == "my file.txt")
        #expect(item?.insertion == "my\\ file.txt")
    }

    @Test("Typing an escaped name still finds it")
    func typedEscape() throws {
        let sandbox = try Sandbox(["my file.txt"])
        #expect(sandbox.complete("cat my\\ fi").items.first?.insertion == "my\\ file.txt")
    }

    @Test("Non-ASCII names aren't escaped")
    func nonASCII() throws {
        let sandbox = try Sandbox(["日本語.txt"])
        #expect(sandbox.complete("cat 日").items.first?.insertion == "日本語.txt")
    }

    @Test("~ expands when reading the directory")
    func tilde() throws {
        let sandbox = try Sandbox(["projects/"])
        let items = sandbox.complete("cd ~/pro", environment: ["HOME": sandbox.root.path]).items
        #expect(items.first?.text == "~/projects/")
        #expect(items.first?.insertion == "~/projects/")
    }

    @Test("Symlinks to directories count as directories")
    func symlink() throws {
        let sandbox = try Sandbox(["real/"])
        try FileManager.default.createSymbolicLink(atPath: sandbox.root.appendingPathComponent("link").path,
                                                   withDestinationPath: sandbox.root.appendingPathComponent("real").path)
        #expect(sandbox.complete("cd l").items.first?.text == "link/")
    }

    @Test("Commands come from PATH")
    func commands() throws {
        let sandbox = try Sandbox(["bin/rewarp-tool"])
        let result = sandbox.complete("rewarp-t", environment: ["PATH": sandbox.root.appendingPathComponent("bin").path])
        #expect(result.items.first?.text == "rewarp-tool")
    }

    @Test("Variables complete after a dollar sign")
    func variables() throws {
        let sandbox = try Sandbox([])
        let result = sandbox.complete("echo $HO", environment: ["HOME": "/x", "OTHER": "1"])
        #expect(result.items.map(\.text) == ["$HOME"])
    }

    @Test("Git subcommands come with descriptions")
    func gitSubcommands() throws {
        let sandbox = try Sandbox([])
        let item = sandbox.complete("git chec").items.first
        #expect(item?.text == "checkout")
        #expect(item?.detail != nil)
    }

    @Test("Git branches come from refs, loose and packed")
    func gitBranches() throws {
        let sandbox = try Sandbox([".git/refs/heads/feature/login", ".git/refs/tags/v1"])
        try "abc refs/heads/packed-branch\n".write(
            to: sandbox.root.appendingPathComponent(".git/packed-refs"), atomically: true, encoding: .utf8)
        let items = sandbox.complete("git checkout ").items.map(\.text)
        #expect(items.contains("feature/login"))
        #expect(items.contains("packed-branch"))
        #expect(items.contains("v1"))
    }

    @Test("A worktree's refs come from its main repository")
    func worktreeRefs() throws {
        let sandbox = try Sandbox([
            "main/.git/refs/heads/shared-branch", "main/.git/worktrees/wt/commondir", "wt/notes.txt",
        ])
        let git = sandbox.root.appendingPathComponent("main/.git")
        try "../..\n".write(to: git.appendingPathComponent("worktrees/wt/commondir"), atomically: true, encoding: .utf8)
        try "gitdir: \(git.path)/worktrees/wt\n".write(
            to: sandbox.root.appendingPathComponent("wt/.git"), atomically: true, encoding: .utf8)
        let result = CompletionEngine().complete(
            line: "git checkout sh", cursor: 15, directory: sandbox.root.appendingPathComponent("wt").path,
            environment: [:])
        #expect(result.items.map(\.text) == ["shared-branch"])
    }

    @Test("ssh hosts come from config and known_hosts")
    func sshHosts() throws {
        let sandbox = try Sandbox([".ssh/config"])
        try "Host prod staging\nHost *\n".write(
            to: sandbox.root.appendingPathComponent(".ssh/config"), atomically: true, encoding: .utf8)
        try "example.com,1.2.3.4 ssh-ed25519 AAAA\n".write(
            to: sandbox.root.appendingPathComponent(".ssh/known_hosts"), atomically: true, encoding: .utf8)
        let items = sandbox.complete("ssh ", environment: ["HOME": sandbox.root.path]).items.map(\.text)
        #expect(items.contains("prod"))
        #expect(items.contains("example.com"))
        #expect(!items.contains("*"))
    }

    @Test("npm scripts come from package.json")
    func npmScripts() throws {
        let sandbox = try Sandbox([])
        try FileManager.default.createDirectory(at: sandbox.root, withIntermediateDirectories: true)
        try "{\"scripts\":{\"dev\":\"vite\"}}".write(
            to: sandbox.root.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        let item = sandbox.complete("npm run ").items.first
        #expect(item?.text == "dev")
        #expect(item?.detail == "vite")
    }

    @Test("make targets come from the Makefile")
    func makeTargets() throws {
        let sandbox = try Sandbox([])
        try FileManager.default.createDirectory(at: sandbox.root, withIntermediateDirectories: true)
        try "CC=gcc\nbuild: deps\n\techo\n.PHONY: build\ntest:\n".write(
            to: sandbox.root.appendingPathComponent("Makefile"), atomically: true, encoding: .utf8)
        #expect(sandbox.complete("make ").items.map(\.text) == ["build", "test"])
    }

    @Test("The shared start of every match is reported")
    func commonPrefix() throws {
        let sandbox = try Sandbox(["report-a.txt", "report-b.txt"])
        #expect(sandbox.complete("cat rep").commonPrefix == "report-")
    }

    @Test("Fuzzy matches give way when something starts with what was typed")
    func prefixBeatsFuzzy() throws {
        let sandbox = try Sandbox([])
        #expect(sandbox.complete("git chec").items.map(\.text) == ["checkout"])
    }

    @Test("Fuzzy matches are used when nothing starts with what was typed")
    func fuzzyFallback() throws {
        let sandbox = try Sandbox(["my-report.txt"])
        #expect(sandbox.complete("cat mrep").items.map(\.text) == ["my-report.txt"])
    }

    @Test("Paths are the fallback when a command has no source")
    func pathFallback() throws {
        let sandbox = try Sandbox(["notes.txt"])
        #expect(sandbox.complete("some-unknown-tool no").items.first?.text == "notes.txt")
    }

    @Test("Filling in a shared prefix never stops on a lone backslash")
    func sharedPrefixStopsBeforeEscape() throws {
        let sandbox = try Sandbox(["one two", "one&two"])
        #expect(sandbox.complete("cat on").commonPrefix == "one")
    }


    @Test("A tilde from a file's name is quoted, and one that was typed stays bare")
    func tildeOnlyExpandsWhenTyped() throws {
        let sandbox = try Sandbox(["~root/", "home/notes.txt"])
        #expect(sandbox.complete("cat ~ro").items.first?.insertion == "\\~root/")
        let home = sandbox.root.appendingPathComponent("home").path
        #expect(sandbox.complete("cat ~/no", environment: ["HOME": home]).items.first?.insertion == "~/notes.txt")
    }

}
