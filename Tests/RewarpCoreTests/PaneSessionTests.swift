import Foundation
import Testing
@testable import RewarpCore

private let bel = "\u{07}"
private let st = "\u{1b}\\"

private func makeSession() -> PaneSession {
    let session = PaneSession(cols: 80, rows: 24, cellWidth: 10, cellHeight: 20, theme: .dusk, workingDirectory: "/tmp")
    session.reportToken = "token"
    return session
}

private func feed(_ session: PaneSession, _ text: String) {
    Array(text.utf8).withUnsafeBytes { session.ingest($0) }
}

/// A report as the shell integration sends it.
private func report(_ key: String, _ value: String = "", terminator: String = bel) -> String {
    "\u{1b}]7701;\(key)=token;\(value)\(terminator)"
}

private let promptStart = report("prompt")
private let inputStart = report("ready")

private func cmd(_ line: String, terminator: String = bel) -> String {
    report("start", line.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!, terminator: terminator)
}

private func done(_ code: Int, terminator: String = bel) -> String {
    report("done", String(code), terminator: terminator)
}

@Suite("Stream router")
struct RouterTests {
    @Test("Without shell integration everything goes to the shell terminal")
    func plain() {
        let session = makeSession()
        feed(session, "hello\r\nworld")
        #expect(session.phase == .plain)
        #expect(session.blocks.isEmpty)
        #expect(session.shell.plainText() == "hello\nworld")
    }

    @Test("Output lands in the block and the prompt stays out of it")
    func outputGoesToBlock() {
        let session = makeSession()
        feed(session, "\(promptStart)$ \(inputStart)")
        #expect(session.phase == .ready)
        feed(session, "ls\r\n\(cmd("ls"))file-a\r\nfile-b\r\n\(done(0))\(promptStart)$ ")

        #expect(session.blocks.count == 1)
        let block = session.blocks[0]
        #expect(block.command == "ls")
        #expect(block.exitCode == 0)
        #expect(!block.isRunning)
        #expect(block.terminal.plainText() == "file-a\nfile-b")
        #expect(!session.shell.plainText().contains("file-a"))
    }

    @Test("A non-zero exit marks the block as failed")
    func failure() {
        let session = makeSession()
        feed(session, "\(cmd("false"))\(done(1))")
        #expect(session.blocks[0].exitCode == 1)
        #expect(session.blocks[0].didFail)
    }

    @Test("Each command gets its own grid, so clearing one spares the others")
    func clearIsContained() {
        let session = makeSession()
        feed(session, "\(cmd("one"))first\(done(0))")
        feed(session, "\(cmd("clear"))\u{1b}[3J\u{1b}[H\u{1b}[2Jgone\(done(0))")
        #expect(session.blocks.count == 2)
        #expect(session.blocks[0].terminal.plainText() == "first")
        #expect(session.blocks[1].terminal.plainText() == "gone")
    }

    @Test("A read split at any byte gives the same result")
    func splitAtEveryByte() {
        let stream = Array("\(promptStart)$ \(inputStart)\(cmd("ls"))one\r\ntwo\(done(3))\(promptStart)$ ".utf8)
        for split in 1..<stream.count {
            let session = makeSession()
            stream[..<split].withUnsafeBytes { session.ingest($0) }
            stream[split...].withUnsafeBytes { session.ingest($0) }
            #expect(session.blocks.count == 1, "split at \(split)")
            #expect(session.blocks.first?.terminal.plainText() == "one\ntwo", "split at \(split)")
            #expect(session.blocks.first?.exitCode == 3, "split at \(split)")
        }
    }

    @Test("ESC-backslash terminators leave no stray backslash in the next grid")
    func stringTerminatorInOneRead() {
        let session = makeSession()
        feed(session, "\(cmd("ls", terminator: st))out\(done(0, terminator: st))after")
        #expect(session.blocks[0].terminal.plainText() == "out")
        #expect(session.shell.plainText() == "after")
    }

    @Test("A terminator split across reads leaves no stray backslash either")
    func stringTerminatorAcrossReads() {
        let session = makeSession()
        feed(session, "\(cmd("ls", terminator: st))out\(done(0, terminator: "\u{1b}"))")
        feed(session, "\\after")
        #expect(session.blocks[0].terminal.plainText() == "out")
        #expect(session.shell.plainText() == "after")
    }

    @Test("A prompt without a command end still closes the running block")
    func promptClosesBlock() {
        let session = makeSession()
        feed(session, "\(cmd("sleep"))\(promptStart)$ ")
        #expect(session.blocks[0].isRunning == false)
        #expect(session.blocks[0].exitCode == nil)
        #expect(session.phase == .prompt)
    }

    @Test("A program can hold drawing back, and the hold ends with its release")
    func synchronizedOutput() {
        let session = makeSession()
        feed(session, "\u{1b}[?2026h")
        #expect(session.isHoldingFrames)
        feed(session, "\u{1b}[?2026l")
        #expect(!session.isHoldingFrames)
    }

    @Test("Binary output full of bells doesn't queue a bell for every byte")
    func bellCoalescing() async {
        let session = makeSession()
        var bells = 0
        session.onEvent = { if case .bell = $0 { bells += 1 } }
        feed(session, String(repeating: "\u{07}", count: 10_000))
        // Bells land on the main queue, so this runs after every one of them.
        await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }
        #expect(bells == 1)
    }

    @Test("A command submitted before the shell is ready waits for it")
    func queuedCommand() {
        let session = makeSession()
        session.submit(command: "ls")
        #expect(session.phase == .plain)
        feed(session, "\(promptStart)$ \(inputStart)")
        #expect(session.phase == .ready)
    }
}

@Suite("Command encoding")
struct EncodingTests {
    @Test("Submitting a private command preserves its leading space for the shell")
    func leadingSpace() {
        #expect(PaneSession.encode(command: " echo private") == Array(" echo private\r".utf8))
    }

    @Test("Single-line commands are sent as typed")
    func singleLine() {
        #expect(PaneSession.encode(command: "ls -la") == Array("ls -la\r".utf8))
    }

    @Test("Multi-line commands use bracketed paste")
    func multiLine() {
        #expect(PaneSession.encode(command: "a\nb") == Array("\u{1b}[200~a\nb\u{1b}[201~\r".utf8))
    }

    @Test("A command can't close the paste bracket early and run the rest")
    func bracketEscape() {
        let bytes = PaneSession.encode(command: "a\n\u{1b}[201~rm -rf x\n")
        let text = String(decoding: bytes, as: UTF8.self)
        #expect(text.components(separatedBy: "\u{1b}[201~").count == 2)
        #expect(text.hasSuffix("\u{1b}[201~\r"))
    }

    @Test("OSC 7 URLs become paths")
    func pwd() {
        #expect(PaneSession.path(fromPwd: "file://host/Users/me/my%20dir") == "/Users/me/my dir")
        #expect(PaneSession.path(fromPwd: "/plain/path") == "/plain/path")
    }

    @Test("Characters the input can't show never reach the line editor as keys")
    func hiddenControlCharacters() {
        let bytes = PaneSession.encode(command: "echo hi\u{1b}x\u{7f}")
        #expect(bytes == Array("\u{1b}[200~echo hi x \u{1b}[201~\r".utf8))
    }

    @Test("A carriage return or tab can't act as a key either")
    func returnsAndTabsStayInTheBuffer() {
        for command in ["one\rtwo", "one\ttwo"] {
            let text = String(decoding: PaneSession.encode(command: command), as: UTF8.self)
            #expect(text.hasPrefix("\u{1b}[200~"))
            #expect(text.hasSuffix("\u{1b}[201~\r"))
        }
    }

    @Test("OSC 133 and OSC 7 mean nothing, because anything can print them")
    func standardMarksAreIgnored() {
        let session = makeSession()
        feed(session, "\(promptStart)\(inputStart)\(cmd("real"))before\r\n")
        feed(session, "\u{1b}]133;D;0\(bel)\u{1b}]133;A\(bel)\u{1b}]133;C;cmdline_url=fake\(bel)\u{1b}]7;file:///etc\(bel)")
        #expect(session.phase == .running)
        #expect(session.blocks.count == 1)
        #expect(session.workingDirectory == "/tmp")
    }

    @Test("A report without the token changes nothing, at the prompt or during a command")
    func reportsNeedTheToken() {
        let session = makeSession()
        func forged(_ key: String, _ value: String) -> String { "\u{1b}]7701;\(key)=guess;\(value)\(bel)" }
        let forgeries = forged("start", "fake") + forged("prompt", "") + forged("cwd", "/etc")
            + forged("path", "/evil") + forged("names", "evil") + forged("done", "0")

        feed(session, "\(promptStart)\(inputStart)\(forgeries)")
        #expect(session.phase == .ready)
        #expect(session.blocks.isEmpty)

        feed(session, "\(cmd("real"))before\r\n\(forgeries)still here\r\n")
        #expect(session.phase == .running)
        #expect(session.blocks.count == 1)
        #expect(session.blocks[0].outputText.contains("still here"))
        #expect(session.workingDirectory == "/tmp")
        #expect(session.shellPath == nil)
        #expect(session.shellNames.isEmpty)

        feed(session, done(3))
        #expect(session.phase == .prompt)
        #expect(session.blocks[0].exitCode == 3)
    }

    @Test("A shell without integration has nothing to report")
    func noReportsWithoutIntegration() {
        let session = PaneSession(cols: 80, rows: 24, cellWidth: 10, cellHeight: 20, theme: .dusk, workingDirectory: "/tmp")
        feed(session, "\(promptStart)\(inputStart)\(cmd("fake"))\u{1b}]133;A\(bel)")
        #expect(session.phase == .plain)
        #expect(session.blocks.isEmpty)
    }

    @Test("Without integration, the shell terminal's OSC 7 still moves the session")
    func plainShellDirectory() {
        let session = PaneSession(cols: 80, rows: 24, cellWidth: 10, cellHeight: 20, theme: .dusk, workingDirectory: "/tmp")
        feed(session, "\u{1b}]7;file://host/usr/local\(bel)")
        #expect(session.workingDirectory == "/usr/local")
    }

}
