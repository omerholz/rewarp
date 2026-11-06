import CGhosttyVT
import Foundation
import Testing
@testable import RewarpCore

/// Small, reproducible mutation fuzzing. Each case uses a fresh terminal, and
/// exercises both the C API and the Swift stream router with identical bytes.
/// Run scripts/fuzz.sh for the longer, sanitizer-enabled campaign.
@Suite("Adversarial terminal streams", .serialized)
struct TerminalSecurityTests {
    private static let corpus: [[UInt8]] = [
        Array("hello\r\n日本語😀".utf8),
        [0, 0xFF, 0xC0, 0x80, 0xED, 0xA0, 0x80, 0xF4, 0x90, 0x80, 0x80],
        Array("\u{1b}[999999999999999999999999999999999999;0H".utf8),
        Array("\u{1b}]52;c;c2VjcmV0\u{07}\u{1b}]52;c;?\u{1b}\\".utf8),
        Array("\u{1b}]7701;start=forged;evil\u{07}\u{1b}]7701;cwd=forged;%2Fetc\u{1b}\\".utf8),
        Array("\u{1b}]133;A\u{07}\u{1b}]7;file://remote/etc\u{07}".utf8),
        Array("\u{1b}P$qm\u{1b}\\\u{1b}[?1049h\u{1b}[?1049l\u{1b}[?2026h\u{1b}[?2026l".utf8),
        Array("\u{1b}[5n\u{1b}[6n\u{1b}[c\u{1b}[>c\u{1b}[18t".utf8),
        Array("\u{1b}]2;unterminated title".utf8),
        Array("\u{1b}Punterminated DCS".utf8),
    ]

    private func makeSession() -> PaneSession {
        let session = PaneSession(cols: 40, rows: 12, cellWidth: 8, cellHeight: 16,
                                  theme: .dusk, workingDirectory: "/tmp")
        session.reportToken = "unavailable-to-output"
        return session
    }

    private func feed(_ session: PaneSession, _ bytes: [UInt8], chunkSize: Int) {
        var offset = 0
        while offset < bytes.count {
            let end = min(offset + chunkSize, bytes.count)
            bytes[offset..<end].withUnsafeBytes { session.ingest($0) }
            offset = end
        }
    }

    @Test("Clipboard OSC requests cannot change session authority")
    func clipboardRequests() {
        let session = makeSession()
        // Rewarp registers no clipboard read/write callback. A query or write
        // from output must not create commands, a directory change, or a title.
        feed(session, Array("\u{1b}]52;c;?\u{07}\u{1b}]52;c;c2VjcmV0\u{1b}\\".utf8), chunkSize: 1)
        #expect(session.phase == .plain)
        #expect(session.blocks.isEmpty)
        #expect(session.workingDirectory == "/tmp")
        #expect(session.shell.title.isEmpty)
    }

    @Test("Malformed streams behave identically across PTY read boundaries")
    func chunkBoundaries() {
        for seed in Self.corpus {
            let whole = makeSession()
            feed(whole, seed, chunkSize: max(1, seed.count))
            for size in [1, 2, 3, 7, 31] {
                let chunked = makeSession()
                feed(chunked, seed, chunkSize: size)
                #expect(chunked.shell.plainText() == whole.shell.plainText())
                #expect(chunked.phase == .plain)
                #expect(chunked.blocks.isEmpty)
                #expect(chunked.workingDirectory == "/tmp")
            }
        }
    }

    @Test("Resizing while a control string is incomplete preserves parser recovery")
    func resizeDuringOutput() {
        let session = makeSession()
        feed(session, Array("\u{1b}]2;title".utf8), chunkSize: 1)
        for width in [1, 80, 2, 132, 40] {
            session.resize(cols: width, rows: 12, cellWidth: 8, cellHeight: 16)
            feed(session, Array(" more".utf8), chunkSize: 2)
        }
        feed(session, Array("\u{1b}\\\u{1b}[2J\u{1b}[Hsurvived".utf8), chunkSize: 1)
        #expect(session.shell.plainText() == "survived")
        #expect(session.blocks.isEmpty)
    }

    @Test("Terminal query floods finish and leave the router usable")
    func queryFlood() {
        let session = makeSession()
        let queries = String(repeating: "\u{1b}[5n\u{1b}[6n\u{1b}[c", count: 4096)
        feed(session, Array(queries.utf8), chunkSize: 127)
        feed(session, Array("\u{1b}[2J\u{1b}[Hsurvived".utf8), chunkSize: 1)
        #expect(session.shell.plainText() == "survived")
        #expect(session.phase == .plain)
    }

    @Test("Seeded mutations cannot forge shell reports or corrupt terminal state")
    func mutations() {
        let requested = ProcessInfo.processInfo.environment["REWARP_FUZZ_CASES"] ?? "128"
        guard let count = Int(requested), (1...100_000).contains(count) else {
            Issue.record("REWARP_FUZZ_CASES must be an integer from 1 to 100000")
            return
        }
        var random = StreamRandom(state: 0x524557415250)
        for iteration in 0..<count {
            var bytes = Self.corpus[iteration % Self.corpus.count]
            for _ in 0..<8 {
                let index = Int(random.next() % UInt64(bytes.count + 1))
                let byte = UInt8(truncatingIfNeeded: random.next())
                switch random.next() % 3 {
                case 0: bytes.insert(byte, at: index)
                case 1: if index < bytes.count { bytes[index] = byte }
                default: if index < bytes.count { bytes.remove(at: index) }
                }
            }
            let direct = VTTerminal(cols: 40, rows: 12)
            bytes.withUnsafeBufferPointer {
                ghostty_terminal_vt_write(direct.handle, $0.baseAddress, $0.count)
            }
            let routed = makeSession()
            feed(routed, bytes, chunkSize: Int(random.next() % 31) + 1)
            #expect(routed.shell.plainText() == direct.plainText(), "mutation \(iteration), seed 0x524557415250")
            #expect(routed.phase == .plain)
            #expect(routed.blocks.isEmpty)
            #expect(routed.workingDirectory == "/tmp")
            #expect(routed.shell.cols == direct.cols)
            #expect(routed.shell.rows == direct.rows)
        }
    }

    @Test("An oversized unknown OSC cannot forge a command after parser recovery")
    func oversizedReport() {
        let session = makeSession()
        let stream = "\u{1b}]7701;start=forged;" + String(repeating: "x", count: 300_000)
            + "\u{1b}\\\u{1b}[2J\u{1b}[Hsurvived"
        feed(session, Array(stream.utf8), chunkSize: 4093)
        #expect(session.phase == .plain)
        #expect(session.blocks.isEmpty)
        #expect(session.shell.plainText() == "survived")
    }

    @Test("Pruning a one-row terminal preserves styled and hyperlinked cursor state")
    func oneRowScrollbackPruning() {
        // Regression shape from GHSA-qjfx-r533-6vx3: reflow a styled hyperlink
        // wider, then scroll until the cursor's original page has been pruned.
        let terminal = VTTerminal(cols: 3, rows: 1)
        terminal.setScrollbackLimit(lines: 0)
        terminal.write("\u{1b}[1m\u{1b}]8;;https://example.com\u{1b}\\" + String(repeating: "a", count: 103))
        terminal.resize(cols: 80, rows: 1, cellWidth: 8, cellHeight: 16)
        terminal.write(String(repeating: "\n", count: 4096) + "b")
        #expect(terminal.plainText().hasSuffix("b"))
        #expect(terminal.rows == 1)
        #expect(terminal.cols == 80)
    }
}

private struct StreamRandom {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
