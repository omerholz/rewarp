import Foundation
import Testing
@testable import RewarpCore

private func kinds(_ text: String) -> [(ShellLexer.Kind, String)] {
    ShellLexer.tokens(in: text).map { ($0.kind, $0.text) }
}

@Suite("Shell lexer")
struct ShellLexerTests {
    @Test("The first word is the command, then arguments and flags")
    func words() {
        let tokens = kinds("git commit -m hello")
        #expect(tokens.map(\.0) == [.command, .argument, .flag, .argument])
        #expect(tokens.map(\.1) == ["git", "commit", "-m", "hello"])
    }

    @Test("Each side of a pipe or list has its own command")
    func pipelines() {
        #expect(kinds("a | b && c; d").map(\.0) == [
            .command, .controlOperator, .command, .controlOperator, .command, .controlOperator, .command,
        ])
    }

    @Test("Quotes and variables are split out of a word")
    func strings() {
        #expect(kinds("echo \"hi\" 'there' $HOME ${PATH}").map(\.0) == [
            .command, .string, .string, .variable, .variable,
        ])
    }

    @Test("An open quote at the end is reported, not lost")
    func unterminated() {
        #expect(kinds("echo 'oops").map(\.0) == [.command, .unterminated])
    }

    @Test("Environment assignments stay in front of the command")
    func assignment() {
        #expect(kinds("FOO=bar BAZ=1 make").map(\.0) == [.argument, .argument, .command])
    }

    @Test("Redirects and comments")
    func redirects() {
        #expect(kinds("ls > out 2>&1 # note").map(\.0) == [.command, .redirect, .argument, .redirect, .argument, .comment])
    }

    @Test("Ranges are UTF-16 offsets, so they line up with the text view")
    func utf16Ranges() {
        let tokens = ShellLexer.tokens(in: "echo 😀 ok")
        #expect(tokens.map(\.range) == [0..<4, 5..<7, 8..<10])
    }

    @Test("Half-typed input never crashes", arguments: ["", " ", "\\", "'", "\"\\", "${", "$", "|", "&&&", "a=", "2>", "#"])
    func halfTyped(_ input: String) {
        _ = ShellLexer.tokens(in: input)
    }
}

@Suite("Command history")
struct CommandHistoryTests {
    @Test("Leading-space submissions never reach suggestions or history search")
    func privateSubmissions() {
        let history = CommandHistory(entries: ["echo public"])
        for command in [" echo secret", "  export TOKEN=private", " \necho private"] {
            history.add(command)
        }
        #expect(history.entries == ["echo public"])
        #expect(history.suggestion(for: "echo s") == nil)
        #expect(history.matching(prefix: "", limit: 20) == ["echo public"])
        history.add("echo ordinary  \n")
        #expect(history.entries.last == "echo ordinary")
    }

    @Test("A repeated command moves to the most recent position")
    func dedupes() {
        let history = CommandHistory(entries: ["a", "b", "a"])
        #expect(history.entries == ["b", "a"])
        history.add("b")
        #expect(history.entries == ["a", "b"])
    }

    @Test("The suggestion is the newest command extending the prefix")
    func suggestion() {
        let history = CommandHistory(entries: ["git status", "git stash", "ls"])
        #expect(history.suggestion(for: "git st") == "git stash")
        #expect(history.suggestion(for: "git stash") == nil)
        #expect(history.suggestion(for: "") == nil)
    }

    @Test("Prefix matches run newest first, however old the match is")
    func prefixMatches() {
        let old = (0..<500).map { "filler \($0)" }
        let history = CommandHistory(entries: ["git status", "git stash"] + old)
        #expect(history.matching(prefix: "git", limit: 50) == ["git stash", "git status"])
    }
}

@Suite("History files")
struct HistoryFileTests {
    @Test("Plain and extended zsh lines")
    func zshFormats() {
        let data = Data(": 1699999999:0;git status\nls -la\n".utf8)
        #expect(ShellHistoryFile.parseZsh(data) == ["git status", "ls -la"])
    }

    @Test("A zsh multi-line command stays one entry")
    func zshMultiLine() {
        let data = Data(": 1699999999:0;for i in 1 2; do\\\n  echo $i\\\ndone\n".utf8)
        #expect(ShellHistoryFile.parseZsh(data) == ["for i in 1 2; do\n  echo $i\ndone"])
    }

    @Test("Metafied bytes decode back to UTF-8")
    func zshMetafied() {
        // "ベ" is E3 83 99. Its last two bytes fall in zsh's token range, so each
        // is stored as the marker 0x83 followed by the byte XOR 0x20.
        let data = Data([0x65, 0x63, 0x68, 0x6F, 0x20, 0xE3, 0x83, 0xA3, 0x83, 0xB9, 0x0A])
        #expect(ShellHistoryFile.parseZsh(data) == ["echo ベ"])
    }

    @Test("Bash timestamps are skipped")
    func bash() {
        #expect(ShellHistoryFile.parseBash(Data("#1699999999\nls\ngit status\n".utf8)) == ["ls", "git status"])
    }

    @Test("fish entries and their escapes")
    func fish() {
        let data = Data("- cmd: echo a\\nb\n  when: 1699999999\n- cmd: ls\n  when: 1\n".utf8)
        #expect(ShellHistoryFile.parseFish(data) == ["echo a\nb", "ls"])
    }
}
