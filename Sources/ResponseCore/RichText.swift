import Foundation

// Responses, the opening and the closing are stored as a small, Markdown-like
// markup (docs/FILE_FORMAT.md §Markup):
//
//   - every line is a paragraph;
//   - "> " starts a quoted paragraph (text quoted from the manuscript) and
//     "- " a bulleted one;
//   - "**" switches bold on or off, "*" italic, "***" both;
//   - {{var:KEY}} is a Variable and {{ref:KEY}} a Cross-reference to a
//     comment, by stable key; {{ref:KEY1|KEY2}} is a cross-reference still
//     waiting for a decision after a split;
//   - a backslash makes the next character literal (\*, \\, \{, and \> or
//     \- at the start of a line).

/// Bold and italic.
public struct InlineStyle: Equatable, Hashable {
    public var bold: Bool
    public var italic: Bool

    public init(bold: Bool = false, italic: Bool = false) {
        self.bold = bold
        self.italic = italic
    }

    public static let plain = InlineStyle()
}

/// A Variable or a Cross-reference.
public enum Token: Equatable, Hashable {
    case variable(String)
    /// One key: a cross-reference. Several: a cross-reference that was
    /// pointing at a comment that has since been split, waiting for the
    /// user to choose among the parts.
    case ref([String])

    public var isPending: Bool {
        if case .ref(let keys) = self { return keys.count != 1 }
        return false
    }

    public var markup: String {
        switch self {
        case .variable(let key): return "{{var:\(key)}}"
        case .ref(let keys): return "{{ref:\(keys.joined(separator: "|"))}}"
        }
    }

    /// Parses the inside of "{{…}}".
    static func parse(_ inner: Substring) -> Token? {
        func validKey(_ k: Substring) -> Bool {
            !k.isEmpty && k.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        }
        if inner.hasPrefix("var:") {
            let key = inner.dropFirst(4)
            return validKey(key) ? .variable(String(key)) : nil
        }
        if inner.hasPrefix("ref:") {
            let keys = inner.dropFirst(4).split(separator: "|", omittingEmptySubsequences: false)
            guard !keys.isEmpty, keys.allSatisfy(validKey) else { return nil }
            return .ref(keys.map(String.init))
        }
        return nil
    }
}

public enum Inline: Equatable {
    case text(String, InlineStyle)
    case token(Token, InlineStyle)

    public var style: InlineStyle {
        switch self {
        case .text(_, let s), .token(_, let s): return s
        }
    }
}

public enum BlockKind: String, CaseIterable, Equatable {
    case normal, quote, bullet
}

public struct RichParagraph: Equatable {
    public var block: BlockKind
    public var inlines: [Inline]

    public init(block: BlockKind = .normal, inlines: [Inline] = []) {
        self.block = block
        self.inlines = inlines
    }

    public var isEmpty: Bool {
        inlines.allSatisfy {
            if case .text(let t, _) = $0 { return t.isEmpty }
            return false
        }
    }
}

public struct RichText: Equatable {
    public var paragraphs: [RichParagraph]

    public init(paragraphs: [RichParagraph] = []) {
        self.paragraphs = paragraphs
    }

    public static let empty = RichText()

    /// Plain text as one normal paragraph per line.
    public init(plain: String) {
        paragraphs = plain.isEmpty ? [] : plain.components(separatedBy: "\n").map {
            RichParagraph(inlines: $0.isEmpty ? [] : [.text($0, .plain)])
        }
    }

    // MARK: Parsing

    public init(markup: String) {
        var text = markup.replacingOccurrences(of: "\r\n", with: "\n")
        while text.hasSuffix("\n") { text.removeLast() }
        paragraphs = text.isEmpty ? [] : text.components(separatedBy: "\n").map(Self.parseParagraph)
    }

    static func parseParagraph(_ line: String) -> RichParagraph {
        var block = BlockKind.normal
        var body = Substring(line)
        if body == ">" {
            block = .quote
            body = ""
        } else if body.hasPrefix("> ") {
            block = .quote
            body = body.dropFirst(2)
        } else if body == "-" {
            block = .bullet
            body = ""
        } else if body.hasPrefix("- ") {
            block = .bullet
            body = body.dropFirst(2)
        }
        var inlines: [Inline] = []
        var style = InlineStyle.plain
        var buffer = ""
        func flush() {
            guard !buffer.isEmpty else { return }
            if case .text(let t, let s)? = inlines.last, s == style {
                inlines[inlines.count - 1] = .text(t + buffer, s)
            } else {
                inlines.append(.text(buffer, style))
            }
            buffer = ""
        }
        var idx = body.startIndex
        while idx < body.endIndex {
            let ch = body[idx]
            if ch == "\\" {
                let next = body.index(after: idx)
                if next < body.endIndex {
                    buffer.append(body[next])
                    idx = body.index(after: next)
                } else {
                    buffer.append(ch)
                    idx = next
                }
                continue
            }
            if ch == "*" {
                var run = 0
                while idx < body.endIndex, body[idx] == "*" {
                    run += 1
                    idx = body.index(after: idx)
                }
                flush()
                while run >= 3 {
                    style.bold.toggle()
                    style.italic.toggle()
                    run -= 3
                }
                if run == 2 { style.bold.toggle() }
                if run == 1 { style.italic.toggle() }
                continue
            }
            if ch == "{", body[idx...].hasPrefix("{{"),
               let close = body[idx...].range(of: "}}") {
                let inner = body[body.index(idx, offsetBy: 2)..<close.lowerBound]
                if let token = Token.parse(inner) {
                    flush()
                    inlines.append(.token(token, style))
                    idx = close.upperBound
                    continue
                }
            }
            buffer.append(ch)
            idx = body.index(after: idx)
        }
        flush()
        return RichParagraph(block: block, inlines: inlines)
    }

    // MARK: Writing

    public var markup: String {
        paragraphs.map(Self.serialize).joined(separator: "\n")
    }

    static func escape(_ s: String) -> String {
        var out = ""
        for ch in s {
            if ch == "\\" || ch == "*" || ch == "{" { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    static func serialize(_ p: RichParagraph) -> String {
        var out: String
        switch p.block {
        case .normal: out = ""
        case .quote: out = "> "
        case .bullet: out = "- "
        }
        var current = InlineStyle.plain
        func transition(to s: InlineStyle) {
            let b = current.bold != s.bold
            let i = current.italic != s.italic
            if b && i { out += "***" } else if b { out += "**" } else if i { out += "*" }
            current = s
        }
        var first = true
        for inline in p.inlines {
            switch inline {
            case .text(let t, let s):
                guard !t.isEmpty else { continue }
                transition(to: s)
                var e = escape(t)
                if first && p.block == .normal && current == .plain
                    && (e.hasPrefix(">") || e.hasPrefix("- ") || e == "-") {
                    e = "\\" + e
                }
                out += e
            case .token(let token, let s):
                transition(to: s)
                out += token.markup
            }
            first = false
        }
        transition(to: .plain)
        // A trailing "-" or ">" alone would read as an empty bullet or quote.
        if p.block == .normal && (out == "-" || out == ">") { out = "\\" + out }
        return out
    }

    // MARK: Queries and rewriting

    /// Every token, in order, with its paragraph index.
    public var tokens: [(paragraph: Int, token: Token)] {
        var result: [(Int, Token)] = []
        for (pi, p) in paragraphs.enumerated() {
            for inline in p.inlines {
                if case .token(let t, _) = inline { result.append((pi, t)) }
            }
        }
        return result
    }

    /// Replaces each token for which `transform` returns a value with the
    /// returned inlines (they inherit the token's style).
    public func replacingTokens(_ transform: (Token) -> [InlinePiece]?) -> RichText {
        var copy = self
        for pi in copy.paragraphs.indices {
            var out: [Inline] = []
            for inline in copy.paragraphs[pi].inlines {
                if case .token(let t, let style) = inline, let pieces = transform(t) {
                    for piece in pieces {
                        switch piece {
                        case .text(let s): out.append(.text(s, style))
                        case .token(let nt): out.append(.token(nt, style))
                        }
                    }
                } else {
                    out.append(inline)
                }
            }
            copy.paragraphs[pi].inlines = Self.coalesce(out)
        }
        return copy
    }

    static func coalesce(_ inlines: [Inline]) -> [Inline] {
        var out: [Inline] = []
        for inline in inlines {
            if case .text(let t, let s) = inline {
                if t.isEmpty { continue }
                if case .text(let pt, let ps)? = out.last, ps == s {
                    out[out.count - 1] = .text(pt + t, s)
                    continue
                }
            }
            out.append(inline)
        }
        return out
    }

    /// The text with tokens shown by `display`.
    public func plainText(_ display: (Token) -> String) -> String {
        paragraphs.map { p in
            var s = p.block == .bullet ? "• " : ""
            for inline in p.inlines {
                switch inline {
                case .text(let t, _): s += t
                case .token(let t, _): s += display(t)
                }
            }
            return s
        }.joined(separator: "\n")
    }
}

/// What a token may be replaced with.
public enum InlinePiece: Equatable {
    case text(String)
    case token(Token)
}

/// Word counting for responses and comments.
public enum TextStats {
    /// Words as a word processor counts them: runs of non-space characters
    /// with at least one letter or digit.
    public static func wordCount(_ s: String) -> Int {
        s.split(whereSeparator: { $0.isWhitespace })
            .filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }
            .count
    }
}
