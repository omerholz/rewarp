import Foundation
import Testing
@testable import RewarpCore

/// Runs a real zsh against the real integration scripts, with HOME pointed at a
/// throwaway directory so that nothing depends on this machine's dotfiles.
private final class Fixture {
    let home: URL
    let session: PaneSession

    init(zshrc: String = "") throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("rewarp-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try zshrc.write(to: home.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)

        session = PaneSession(cols: 80, rows: 24, cellWidth: 10, cellHeight: 20, theme: .dusk,
                              workingDirectory: home.path)

        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let environment = ["HOME": home.path, "PATH": "/usr/bin:/bin", "USER": "test"]
        let launch = ShellLaunch.login(
            workingDirectory: home.path, shell: "/bin/zsh", environment: environment,
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

    @Test("Commands can't see the token that proves a report came from the shell")
    func tokenStaysInTheShell() throws {
        let fixture = try Fixture()
        let block = try fixture.run("env | grep -c REWARP", block: 0)
        #expect(fixture.text(of: block) == "0")
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
