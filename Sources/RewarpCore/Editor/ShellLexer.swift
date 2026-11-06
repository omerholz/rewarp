import Foundation

/// A deliberately forgiving shell tokenizer. It runs on every keystroke against
/// text that is usually half typed, so it never fails, it just stops short.
public enum ShellLexer {
    public enum Kind: Equatable, Sendable {
        case command
        case argument
        case flag
        case string
        case variable
        case comment
        case controlOperator
        case redirect
        /// A quote that is still open at the end of the input.
        case unterminated
    }

    public struct Token: Equatable, Sendable {
        public var kind: Kind
        /// UTF-16 offsets, to match NSTextStorage and NSRange.
        public var range: Range<Int>
        public var text: String
    }

    public static func tokens(in source: String) -> [Token] {
        let chars = Array(source.utf16)
        var tokens: [Token] = []
        var index = 0
        var atCommand = true

        func emit(_ kind: Kind, _ start: Int, _ end: Int) {
            let text = String(decoding: chars[start..<end], as: UTF16.self)
            tokens.append(Token(kind: kind, range: start..<end, text: text))
        }
        func at(_ offset: Int) -> UInt16? {
            let position = index + offset
            return position < chars.count ? chars[position] : nil
        }
        func isSpace(_ c: UInt16) -> Bool { c == 0x20 || c == 0x09 }
        func isWordEnd(_ c: UInt16) -> Bool {
            isSpace(c) || c == 0x0A || c == cp("|") || c == cp("&") || c == cp(";")
                || c == cp("(") || c == cp(")") || c == cp("<") || c == cp(">")
        }

        while index < chars.count {
            let c = chars[index]

            if isSpace(c) {
                index += 1
                continue
            }
            if c == 0x0A {
                index += 1
                atCommand = true
                continue
            }
            if c == cp("#") {
                let start = index
                while index < chars.count, chars[index] != 0x0A { index += 1 }
                emit(.comment, start, index)
                continue
            }
            if c == cp("|") || c == cp("&") || c == cp(";") || c == cp("(") || c == cp(")") {
                let start = index
                index += 1
                if let next = at(0), next == c, c != cp("(") , c != cp(")") { index += 1 }
                emit(.controlOperator, start, index)
                if c != cp(")") { atCommand = true }
                continue
            }
            if c == cp(">") || c == cp("<") {
                let start = index
                index += 1
                if at(0) == c || at(0) == cp("&") { index += 1 }
                emit(.redirect, start, index)
                continue
            }
            if isDigit(c), at(1) == cp(">") {
                let start = index
                index += 2
                if at(0) == cp(">") || at(0) == cp("&") { index += 1 }
                emit(.redirect, start, index)
                continue
            }

            // A word. It can mix bare text, quotes and variables, so it's split
            // into pieces, and the bare pieces take their kind from the position.
            var pieceStart = index
            var wordIsAssignment = false
            let wordStart = index
            var isFirstPiece = true

            func bareKind() -> Kind {
                if isFirstPiece && chars[pieceStart] == cp("-") { return .flag }
                return atCommand && !wordIsAssignment ? .command : .argument
            }
            func flushBare() {
                if index > pieceStart {
                    emit(bareKind(), pieceStart, index)
                    isFirstPiece = false
                }
            }

            while index < chars.count, !isWordEnd(chars[index]) {
                let w = chars[index]
                if w == cp("\\") {
                    index = min(index + 2, chars.count)
                } else if w == cp("'") || w == cp("\"") {
                    flushBare()
                    let start = index
                    index += 1
                    var closed = false
                    while index < chars.count {
                        if chars[index] == cp("\\"), w == cp("\"") {
                            index = min(index + 2, chars.count)
                            continue
                        }
                        if chars[index] == w {
                            index += 1
                            closed = true
                            break
                        }
                        index += 1
                    }
                    emit(closed ? .string : .unterminated, start, index)
                    pieceStart = index
                    isFirstPiece = false
                } else if w == cp("$") {
                    flushBare()
                    let start = index
                    index += 1
                    if at(0) == cp("{") {
                        while index < chars.count, chars[index] != cp("}") { index += 1 }
                        index = min(index + 1, chars.count)
                    } else {
                        while let next = at(0), isName(next) { index += 1 }
                    }
                    emit(.variable, start, index)
                    pieceStart = index
                    isFirstPiece = false
                } else {
                    if w == cp("="), atCommand, isFirstPiece,
                       isAssignmentName(chars[wordStart..<index]) {
                        wordIsAssignment = true
                    }
                    index += 1
                }
            }
            flushBare()

            if !wordIsAssignment { atCommand = false }
        }
        return tokens
    }

    private static func cp(_ scalar: Unicode.Scalar) -> UInt16 { UInt16(scalar.value) }

    private static func isDigit(_ c: UInt16) -> Bool { c >= 0x30 && c <= 0x39 }

    private static func isName(_ c: UInt16) -> Bool {
        isDigit(c) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F
    }

    private static func isAssignmentName(_ name: ArraySlice<UInt16>) -> Bool {
        guard let first = name.first, !isDigit(first) else { return false }
        return name.allSatisfy(isName)
    }
}
