import Foundation
import Testing
@testable import RewarpCore

private let bel = "\u{07}"
private let st = "\u{1b}\\"

private func makeSession() -> PaneSession {
    PaneSession(cols: 80, rows: 24, cellWidth: 10, cellHeight: 20, theme: .dusk, workingDirectory: "/tmp")
}

private func feed(_ session: PaneSession, _ text: String) {
    Array(text.utf8).withUnsafeBytes { session.ingest($0) }
}

private func cmd(_ line: String, terminator: String = bel) -> String {
    "\u{1b}]133;C;cmdline_url=\(line.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)\(terminator)"
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
        feed(session, "\u{1b}]133;A\(bel)$ \u{1b}]133;B\(bel)")
        #expect(session.phase == .ready)
        feed(session, "ls\r\n\(cmd("ls"))file-a\r\nfile-b\r\n\u{1b}]133;D;0\(bel)\u{1b}]133;A\(bel)$ ")

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
        feed(session, "\(cmd("false"))\u{1b}]133;D;1\(bel)")
        #expect(session.blocks[0].exitCode == 1)
        #expect(session.blocks[0].didFail)
    }

    @Test("Each command gets its own grid, so clearing one spares the others")
    func clearIsContained() {
        let session = makeSession()
        feed(session, "\(cmd("one"))first\u{1b}]133;D;0\(bel)")
        feed(session, "\(cmd("clear"))\u{1b}[3J\u{1b}[H\u{1b}[2Jgone\u{1b}]133;D;0\(bel)")
        #expect(session.blocks.count == 2)
        #expect(session.blocks[0].terminal.plainText() == "first")
        #expect(session.blocks[1].terminal.plainText() == "gone")
    }

    @Test("A read split at any byte gives the same result")
    func splitAtEveryByte() {
        let stream = Array("\u{1b}]133;A\(bel)$ \u{1b}]133;B\(bel)\(cmd("ls"))one\r\ntwo\u{1b}]133;D;3\(bel)\u{1b}]133;A\(bel)$ ".utf8)
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
        feed(session, "\(cmd("ls", terminator: st))out\u{1b}]133;D;0\(st)after")
        #expect(session.blocks[0].terminal.plainText() == "out")
        #expect(session.shell.plainText() == "after")
    }

    @Test("A terminator split across reads leaves no stray backslash either")
    func stringTerminatorAcrossReads() {
        let session = makeSession()
        feed(session, "\(cmd("ls", terminator: st))out\u{1b}]133;D;0\u{1b}")
        feed(session, "\\after")
        #expect(session.blocks[0].terminal.plainText() == "out")
        #expect(session.shell.plainText() == "after")
    }

    @Test("A prompt without a command end still closes the running block")
    func promptClosesBlock() {
        let session = makeSession()
        feed(session, "\(cmd("sleep"))\u{1b}]133;A\(bel)$ ")
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
        feed(session, "\u{1b}]133;A\(bel)$ \u{1b}]133;B\(bel)")
        #expect(session.phase == .ready)
    }
}

@Suite("Command encoding")
struct EncodingTests {
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

    @Test("With a token, only the shell can end a block")
    func outputCannotEndItsOwnBlock() {
        let session = PaneSession(cols: 80, rows: 24, cellWidth: 10, cellHeight: 20, theme: .dusk, workingDirectory: "/")
        session.commandToken = "secret"
        feed(session, "\u{1b}]133;A\u{07}\u{1b}]133;B\u{07}\u{1b}]133;C;cmdline_url=real\u{07}before\r\n")
        #expect(session.phase == .running)

        feed(session, "\u{1b}]133;D;0\u{07}\u{1b}]133;A\u{07}\u{1b}]133;B\u{07}\u{1b}]133;C;cmdline_url=fake\u{07}")
        feed(session, "\u{1b}]7701;done=guess;0\u{07}\u{1b}]7701;path=/evil\u{07}still here\r\n")
        #expect(session.phase == .running)
        #expect(session.blocks.count == 1)
        #expect(session.shellPath == nil)
        #expect(session.blocks[0].outputText.contains("still here"))

        feed(session, "\u{1b}]7701;done=secret;3\u{07}")
        #expect(session.phase == .prompt)
        #expect(session.blocks[0].exitCode == 3)
    }

}
