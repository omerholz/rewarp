import Foundation
import Testing
@testable import RewarpCore

/// Runs a real zsh against the real integration scripts, with HOME pointed at a
/// throwaway directory so that nothing depends on this machine's dotfiles.
private final class Fixture {
    let home: URL
    let session: PaneSession

    init(zshrc: String = "", shellScript: String? = nil) throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("rewarp-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try zshrc.write(to: home.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)

        session = PaneSession(cols: 80, rows: 24, cellWidth: 10, cellHeight: 20, theme: .dusk,
                              workingDirectory: home.path)

        var shell = "/bin/zsh"
        if let shellScript {
            // Named zsh, so it's launched exactly as a real one would be.
            let script = home.appendingPathComponent("zsh")
            try "#!/bin/sh\n\(shellScript)\n".write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
            shell = script.path
        }

        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let environment = ["HOME": home.path, "PATH": "/usr/bin:/bin", "USER": "test"]
        let launch = ShellLaunch.login(
            workingDirectory: home.path, shell: shell, environment: environment,
            integrationDirectory: repo.appendingPathComponent("resources/shell-integration"))
        try session.start(launch: launch)
    }

    deinit {
        session.terminate()
        try? FileManager.default.removeItem(at: home)
    }

    /// Polls because the read thread moves state along while the test waits.
    func wait(_ what: String, timeout: Double = 8, until condition: (PaneSession) -> Bool) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            session.lock.lock()
            let met = condition(session)
            session.lock.unlock()
            if met { return }
            usleep(10_000)
        }
        Issue.record("timed out waiting for \(what), phase \(session.phase)")
        throw CancellationError()
    }

    func run(_ command: String, block index: Int) throws -> Block {
        try wait("the prompt") { $0.phase == .ready }
        session.submit(command: command)
        try wait("block \(index) to finish") { $0.blocks.count > index && !$0.blocks[index].isRunning }
        return session.blocks[index]
    }

    func text(of block: Block) -> String {
        session.lock.lock()
        defer { session.lock.unlock() }
        return block.terminal.plainText()
    }
}

@Suite("Token handoff")
struct TokenHandoffTests {
    @Test("The bundled helper can bootstrap once, but later commands cannot retrieve the token")
    func helperBootstrapIsSingleUse() throws {
        let helper = try #require(ShellLaunch.integrationHelper())
        let handoff = try #require(TokenHandoff())
        handoff.serve(token: "test-private-token", shell: getpid(), helperPath: helper.path)

        func request() throws -> (Int32, String) {
            let process = Process()
            process.executableURL = helper
            process.arguments = ["token", handoff.path]
            let output = Pipe()
            process.standardOutput = output
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        }
        // Being a child of the shell is insufficient: an ordinary program must
        // not consume the bootstrap that belongs to the bundled helper.
        let other = Process()
        other.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        other.arguments = ["-c", "import socket,sys; s=socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); sys.stdout.buffer.write(s.recv(128))", handoff.path]
        let otherOutput = Pipe()
        other.standardOutput = otherOutput
        try other.run()
        let denied = otherOutput.fileHandleForReading.readDataToEndOfFile()
        other.waitUntilExit()
        #expect(other.terminationStatus == 0)
        #expect(denied.isEmpty)
        let first = try request()
        #expect(first.0 == 0)
        #expect(first.1 == "test-private-token\n")
        let later = try request()
        #expect(later.0 != 0)
        #expect(later.1.isEmpty)
    }

    @Test("A helper is denied unless that bootstrap was explicitly enabled")
    func helperIsNotImplicitlyTrusted() throws {
        let helper = try #require(ShellLaunch.integrationHelper())
        let handoff = try #require(TokenHandoff())
        handoff.serve(token: "test-private-token", shell: getpid())
        let process = Process()
        process.executableURL = helper
        process.arguments = ["token", handoff.path]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus != 0)
        #expect(data.isEmpty)
    }

    @Test("A directory that can't hold the socket falls through to the next")
    func fallsThroughToADirectoryThatWorks() throws {
        // A shell that can't reach this has no blocks at all, so one bad TMPDIR can't be fatal.
        let usable = NSTemporaryDirectory()
        let tooLong = "/tmp/" + String(repeating: "x", count: 200)
        let handoff = try #require(TokenHandoff(directories: ["/no/such/directory", tooLong, usable]))
        #expect(handoff.path.hasPrefix(usable))
        #expect(FileManager.default.fileExists(atPath: handoff.path))
    }

    @Test("With nowhere to put the socket there's no handoff")
    func nowhereToGo() {
        #expect(TokenHandoff(directories: ["/no/such/directory"]) == nil)
    }
}

@Suite("zsh integration", .serialized)
struct ZshIntegrationTests {
    @Test("A command printing prompt markers stays one block")
    func printedMarkers() throws {
        let fixture = try Fixture()
        let block = try fixture.run(
            #"printf '\e]133;D;0\a\e]133;A\a\e]133;B\a\e]133;C;cmdline_url=fake\a'; sleep 0.2; echo after; false"#,
            block: 0)
        #expect(fixture.session.blocks.count == 1)
        #expect(fixture.text(of: block) == "after")
        #expect(block.exitCode == 1)
    }

    @Test("A background job can't fake a command or move the session at the prompt")
    func backgroundJobAtThePrompt() throws {
        let fixture = try Fixture()
        _ = try fixture.run(
            #"(sleep 0.2; printf '\e]133;A\a\e]133;C;cmdline_url=fake\a\e]7;file:///etc\a') &"#, block: 0)
        try fixture.wait("the prompt") { $0.phase == .ready }
        let directory = fixture.session.currentDirectory
        usleep(500_000)
        try fixture.wait("the prompt") { $0.phase == .ready }
        #expect(fixture.session.blocks.count == 1)
        #expect(fixture.session.currentDirectory == directory)
    }

    @Test("The working directory follows cd, through a space and a quote")
    func directoryReport() throws {
        let fixture = try Fixture()
        let name = "it's a dir"
        try FileManager.default.createDirectory(at: fixture.home.appendingPathComponent(name),
                                                 withIntermediateDirectories: true)
        _ = try fixture.run(#"cd "it's a dir""#, block: 0)
        try fixture.wait("the report") { $0.workingDirectory.hasSuffix("/" + name) }
    }

    @Test("Commands can't see the token that proves a report came from the shell")
    func tokenStaysInTheShell() throws {
        let fixture = try Fixture()
        let block = try fixture.run("env | grep -c REWARP", block: 0)
        #expect(fixture.text(of: block) == "0")
    }

    @Test("exec zsh gets back to blocks")
    func execZsh() throws {
        let fixture = try Fixture(zshrc: "export FROM_ZSHRC=yes")
        let replaced = try fixture.run("exec zsh", block: 0)
        #expect(replaced.command == "exec zsh")
        let block = try fixture.run("echo $FROM_ZSHRC", block: 1)
        #expect(fixture.text(of: block) == "yes")
        #expect(block.exitCode == 0)
    }

    @Test("exec by full path gets back to blocks, as with exec $SHELL")
    func execByPath() throws {
        let fixture = try Fixture()
        _ = try fixture.run("exec /bin/zsh", block: 0)
        let block = try fixture.run("echo after", block: 1)
        #expect(fixture.text(of: block) == "after")
    }

    @Test("omz reload gets back to blocks every time, and stays a login shell")
    func omzReload() throws {
        // What oh-my-zsh runs. A pane's shell takes the login branch.
        let fixture = try Fixture(zshrc: #"""
            reload() {
              local zsh="$ZSH_ARGZERO"
              [[ "${zsh#-}" != /* ]] && (( $+commands[zsh] )) && zsh="zsh"
              [[ "$zsh" = -* || -o login ]] && exec -l "${zsh#-}" || exec "$zsh"
            }
            """#)
        _ = try fixture.run("reload", block: 0)
        _ = try fixture.run("reload", block: 1)
        let block = try fixture.run("[[ -o login ]] && echo login", block: 2)
        #expect(fixture.text(of: block) == "login")
    }

    @Test("Commands in the replacement shell can't see the token either")
    func tokenStaysInTheReplacementShell() throws {
        let fixture = try Fixture()
        _ = try fixture.run("exec zsh", block: 0)
        let block = try fixture.run("env | grep -c -E 'REWARP|ZDOTDIR'", block: 1)
        #expect(fixture.text(of: block) == "0")
    }

    @Test("A program started with exec doesn't inherit the token")
    func execHandsOverNoToken() throws {
        let fixture = try Fixture()
        // In a subshell, because the pane's shell would be gone otherwise.
        let block = try fixture.run("(exec env) | grep -c TOKEN", block: 0)
        #expect(fixture.text(of: block) == "0")
    }

    @Test("A command that asks for the token gets nothing")
    func commandsCantAskForTheToken() throws {
        let fixture = try Fixture()
        try fixture.wait("the prompt") { $0.phase == .ready }
        let path = try #require(fixture.session.tokenHandoff?.path)
        let block = try fixture.run(
            #"zsh -fc 'zmodload zsh/net/socket; zsocket "\#(path)" && read -t 2 -u $REPLY reply; print -r -- "[$reply]"'"#,
            block: 0)
        #expect(fixture.text(of: block) == "[]")
    }

    @Test("The token is nowhere in what the shell is started with")
    func launchCarriesNoToken() throws {
        // The value, not a name, so that this holds whatever carries it. A command can
        // read a shell's starting environment through `ps -E`, on any zsh that isn't
        // hardened as /bin/zsh is, so it's never there to be read.
        let fixture = try Fixture(shellScript: #"env > "$HOME/started.tmp"; mv "$HOME/started.tmp" "$HOME/started""#)
        let started = fixture.home.appendingPathComponent("started")
        try fixture.wait("the shell to start") { _ in FileManager.default.fileExists(atPath: started.path) }

        let environment = try String(contentsOf: started, encoding: .utf8)
        let token = try #require(fixture.session.reportToken)
        #expect(environment.contains("REWARP_SOCKET="))
        #expect(!environment.contains(token))
    }

    @Test("exec zsh finds the same startup files it would without Rewarp")
    func execKeepsTheUsersZdotdir() throws {
        let fixture = try Fixture(zshrc: "FROM=home")
        let config = fixture.home.appendingPathComponent("config")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        try "FROM=config".write(to: config.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)

        _ = try fixture.run("export ZDOTDIR=$HOME/config; exec zsh", block: 0)
        let exported = try fixture.run("echo $FROM:${ZDOTDIR:t}", block: 1)
        #expect(fixture.text(of: exported) == "config:config")

        // A ZDOTDIR that isn't exported never reaches a new shell.
        _ = try fixture.run("typeset +x ZDOTDIR; exec zsh", block: 2)
        let private_ = try fixture.run("echo $FROM:${ZDOTDIR:t}", block: 3)
        #expect(fixture.text(of: private_) == "home:")
    }

    @Test("exec can still change the shell's own file descriptors")
    func execRedirection() throws {
        let fixture = try Fixture()
        _ = try fixture.run("exec 3>&1", block: 0)
        let block = try fixture.run(#"echo kept >&3; echo "${ZDOTDIR:-unset}""#, block: 1)
        #expect(fixture.text(of: block) == "kept\nunset")
    }

    @Test("A shell that exec starts in a subshell stays a plain nested shell")
    func execInASubshell() throws {
        let fixture = try Fixture()
        // Not the pane's own process, so it mustn't be given the token.
        let block = try fixture.run(#"(exec zsh -ic 'echo "[$_rewarp_token]"')"#, block: 0)
        #expect(fixture.text(of: block) == "[]")
    }

    @Test("Commands submitted before the prompt all run, in order")
    func heldCommands() throws {
        let fixture = try Fixture()
        fixture.session.submit(command: "echo first")
        fixture.session.submit(command: "echo second")
        try fixture.wait("both blocks") { $0.blocks.count == 2 && !$0.blocks[1].isRunning }
        #expect(fixture.session.blocks.map(\.command) == ["echo first", "echo second"])
    }

    @Test("A command becomes a block holding its command, output and exit code")
    func basicBlock() throws {
        let fixture = try Fixture()
        let block = try fixture.run("echo hello-from-block", block: 0)
        #expect(block.command == "echo hello-from-block")
        #expect(block.exitCode == 0)
        #expect(fixture.text(of: block) == "hello-from-block")
    }

    @Test("A failing command reports its exit code")
    func exitCode() throws {
        let fixture = try Fixture()
        let block = try fixture.run("(exit 42)", block: 0)
        #expect(block.exitCode == 42)
        #expect(block.didFail)
    }

    @Test("Consecutive commands get separate blocks")
    func sequence() throws {
        let fixture = try Fixture()
        let first = try fixture.run("echo one", block: 0)
        let second = try fixture.run("echo two", block: 1)
        #expect(fixture.text(of: first) == "one")
        #expect(fixture.text(of: second) == "two")
    }

    @Test("Commands with spaces, quotes and non-ASCII text survive the round trip")
    func encoding() throws {
        let fixture = try Fixture()
        let command = "echo 'héllo wörld' \"$HOME\" | cat # 日本語 100%"
        let block = try fixture.run(command, block: 0)
        #expect(block.command == command)
    }

    @Test("Multi-line commands run as one block")
    func multiLine() throws {
        let fixture = try Fixture()
        let block = try fixture.run("for i in 1 2; do\n  echo line-$i\ndone", block: 0)
        #expect(fixture.text(of: block) == "line-1\nline-2")
    }

    @Test("The working directory follows cd")
    func workingDirectory() throws {
        let fixture = try Fixture()
        _ = try fixture.run("cd /usr/bin", block: 0)
        try fixture.wait("the new directory") { $0.workingDirectory == "/usr/bin" }
    }

    @Test("A prompt theme that rewrites PS1 on every prompt doesn't stop blocks")
    func promptTheme() throws {
        let fixture = try Fixture(zshrc: """
            theme_precmd() { PS1="$(print -n themed)> " }
            precmd_functions+=(theme_precmd)
            """)
        let first = try fixture.run("echo a", block: 0)
        let second = try fixture.run("echo b", block: 1)
        #expect(fixture.text(of: first) == "a")
        #expect(fixture.text(of: second) == "b")
    }

    @Test("A .zshrc that defines its own line-init widget doesn't stop blocks")
    func userLineInitWidget() throws {
        let fixture = try Fixture(zshrc: """
            my_line_init() { export LINE_INIT_RAN=yes }
            zle -N zle-line-init my_line_init
            """)
        let block = try fixture.run("echo $LINE_INIT_RAN", block: 0)
        #expect(fixture.text(of: block) == "yes")
    }

    @Test("A prompt that runs the whole line edit inside zle-line-init doesn't stop blocks")
    func recursiveEditPrompt() throws {
        // The shape of oh-my-posh's widget, which only returns once the line is done.
        let fixture = try Fixture(zshrc: """
            my_line_init() {
              [[ $CONTEXT == start ]] || return 0
              zle .recursive-edit
              local -i ret=$?
              (( ret )) && zle .send-break || zle .accept-line
              return ret
            }
            zle -N zle-line-init my_line_init
            """)
        let first = try fixture.run("echo a", block: 0)
        let second = try fixture.run("echo b", block: 1)
        #expect(fixture.text(of: first) == "a")
        #expect(fixture.text(of: second) == "b")
    }

    @Test("Something replacing the widget after startup doesn't stop blocks")
    func widgetReplacedLater() throws {
        let fixture = try Fixture()
        _ = try fixture.run("late() { :; }; zle -N zle-line-init late 2>/dev/null; true", block: 0)
        let block = try fixture.run("echo still-working", block: 1)
        #expect(fixture.text(of: block) == "still-working")
    }

    @Test("Output without a trailing newline is kept")
    func noTrailingNewline() throws {
        let fixture = try Fixture()
        let block = try fixture.run("printf partial", block: 0)
        #expect(fixture.text(of: block) == "partial")
    }

    @Test("The user's ZDOTDIR and .zshrc still apply")
    func userConfigLoads() throws {
        let fixture = try Fixture(zshrc: "export FROM_ZSHRC=yes")
        let block = try fixture.run("echo $FROM_ZSHRC:${ZDOTDIR:-unset}", block: 0)
        #expect(fixture.text(of: block) == "yes:unset")
    }

    @Test("Full-screen programs enter the alternate screen inside their block")
    func alternateScreen() throws {
        let fixture = try Fixture()
        try fixture.wait("the prompt") { $0.phase == .ready }
        fixture.session.submit(command: "printf '\\033[?1049h'; sleep 0.4; printf '\\033[?1049l'")
        try fixture.wait("the alternate screen") {
            $0.blocks.first?.terminal.isAlternateScreen == true
        }
        try fixture.wait("the command to finish") { $0.blocks.first?.isRunning == false }
    }
}

@Suite("Session lifetime", .serialized)
struct SessionLifetimeTests {
    /// Closing a pane drops its session while the shell may still be printing, and
    /// the read thread must cope. A failure here takes down the whole test process.
    @Test("A session can go away while its process is still printing")
    func droppedWhilePrinting() throws {
        let launch = PTYProcess.Launch(
            path: "/bin/sh", argv: ["sh", "-c", "while :; do echo output; done"],
            environment: ["PATH": "/usr/bin:/bin"], workingDirectory: "/tmp")
        for _ in 0..<40 {
            var session: PaneSession? = PaneSession(
                cols: 80, rows: 24, cellWidth: 10, cellHeight: 20, theme: .dusk, workingDirectory: "/tmp")
            try session?.start(launch: launch)
            usleep(2_000)
            session?.terminate()
            session = nil
            usleep(1_000)
        }
        usleep(100_000)
    }

    @Test("Dropping a session without terminating it ends its process")
    func droppingEndsTheProcess() throws {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("rewarp-alive-\(UUID().uuidString)")
        let launch = PTYProcess.Launch(
            path: "/bin/sh", argv: ["sh", "-c", "while :; do touch '\(marker.path)'; sleep 0.05; done"],
            environment: ["PATH": "/usr/bin:/bin"], workingDirectory: "/tmp")
        var session: PaneSession? = PaneSession(
            cols: 80, rows: 24, cellWidth: 10, cellHeight: 20, theme: .dusk, workingDirectory: "/tmp")
        try session?.start(launch: launch)
        usleep(200_000)
        #expect(FileManager.default.fileExists(atPath: marker.path))

        session = nil
        usleep(200_000)
        try? FileManager.default.removeItem(at: marker)
        usleep(300_000)
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }
}
