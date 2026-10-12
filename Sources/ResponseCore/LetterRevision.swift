import Foundation

// Editing the decision letter. Comments point into it by UTF-16 offset, so
// every edit is recorded (as an NSTextView reports it) and positions are
// carried through the edits. A comment whose marked text didn't change just
// moves; one whose text moved elsewhere (cut and paste, or a replaced
// letter) is found again by its wording; one that was edited or deleted is
// put to the user (docs/DESIGN.md §Editing the decision letter).

/// One edit: `length` characters at `location` (in the text as it was just
/// before this edit) replaced by `replacementLength` characters.
public struct LetterEdit: Equatable, Hashable, Sendable {
    public var location: Int
    public var length: Int
    public var replacementLength: Int

    public init(location: Int, length: Int, replacementLength: Int) {
        self.location = location
        self.length = length
        self.replacementLength = replacementLength
    }

    var delta: Int { replacementLength - length }
}

public enum Remap {
    /// Carries a range through edits. `touched` is true if any edit fell
    /// inside it. Text typed exactly at either end stays outside it.
    public static func map(_ r: SourceRange, through edits: [LetterEdit]) -> (range: SourceRange, touched: Bool) {
        var s = r.location
        var t = r.end
        var touched = false
        for e in edits {
            let a = e.location, end = e.location + e.length
            if t <= a {
                continue                                   // edit after the range
            } else if s >= end {
                s += e.delta                               // edit before the range
                t += e.delta
            } else if s >= a && t <= end && e.length > t - s {
                // The range sits inside a larger replaced span (such as
                // pasting over the whole letter): its text is gone.
                touched = true
                s = a
                t = a
            } else {
                touched = true                             // edit overlaps the range
                let newS = s < a ? s : a
                let newT = t > end ? t + e.delta : a + e.replacementLength
                s = newS
                t = max(newS, newT)
            }
        }
        return (SourceRange(location: max(0, s), length: max(0, t - s)), touched)
    }

    /// Carries a position (a section's start) through edits; text inserted
    /// exactly there goes before it, so a section stays with its heading.
    public static func map(offset: Int, through edits: [LetterEdit]) -> Int {
        var o = offset
        for e in edits {
            if o >= e.location + e.length {
                o += e.delta
            } else if o > e.location {
                o = e.location                             // inside deleted text
            }
        }
        return max(0, o)
    }
}

/// What happened to a comment's marked text.
public struct AnchorChange: Identifiable, Equatable {
    public enum Kind: Equatable {
        /// Its text changed in place.
        case edited
        /// Its text is gone.
        case removed
        /// Its text was found, unchanged, somewhere else.
        case relocated
    }

    public var key: String
    public var kind: Kind
    /// What was marked before.
    public var oldText: String
    /// What is marked now ("" when removed).
    public var newText: String
    public var newSource: [SourceRange]
    /// Whether the comment's own text was still exactly the marked text
    /// (if not, the user had tidied it up).
    public var commentMatchedOldText: Bool

    public var id: String { key }

    public init(key: String, kind: Kind, oldText: String, newText: String, newSource: [SourceRange],
                commentMatchedOldText: Bool) {
        self.key = key
        self.kind = kind
        self.oldText = oldText
        self.newText = newText
        self.newSource = newSource
        self.commentMatchedOldText = commentMatchedOldText
    }

    /// The choice offered first.
    public var defaultDecision: AnchorDecision {
        switch kind {
        case .edited: return commentMatchedOldText ? .useNewText : .keepCommentText
        case .removed: return .unmark
        case .relocated: return .useNewText
        }
    }
}

/// What to do with an edited or removed comment.
public enum AnchorDecision: String, CaseIterable, Equatable, Hashable {
    /// Mark the new text, and make it the comment's text.
    case useNewText
    /// Mark the new text, but keep the comment's text as it is.
    case keepCommentText
    /// Keep the comment, no longer marked in the letter.
    case unmark
    /// Delete the comment.
    case delete
}

/// The result of editing the decision letter, before it is applied.
public struct LetterRevision: Equatable {
    public var text: String
    /// Every comment's marked ranges in the new text (changed ones as
    /// proposed in `changes`).
    public var sources: [String: [SourceRange]]
    /// Section starts in the new text.
    public var anchors: [String: Int]
    public var changes: [AnchorChange]
    /// How many comments simply moved with the text.
    public var shifted: Int

    /// Changes the user must decide on (not those found again).
    public var needsAttention: [AnchorChange] { changes.filter { $0.kind != .relocated } }
    public var relocated: [AnchorChange] { changes.filter { $0.kind == .relocated } }
}

extension ResponseLetter {
    static func trimmed(_ range: SourceRange, in text: String) -> SourceRange {
        let u = Array(text.utf16)
        var a = max(0, min(range.location, u.count))
        var b = max(a, min(range.end, u.count))
        while a < b, isSpace(u[a]) { a += 1 }
        while b > a, isSpace(u[b - 1]) { b -= 1 }
        return SourceRange(location: a, length: b - a)
    }

    /// Every place `needle` occurs in `haystack`, as UTF-16 ranges.
    static func occurrences(of needle: String, in haystack: String) -> [SourceRange] {
        guard !needle.isEmpty else { return [] }
        let h = haystack as NSString
        var result: [SourceRange] = []
        var from = 0
        while from < h.length {
            let r = h.range(of: needle, options: [.literal], range: NSRange(location: from, length: h.length - from))
            if r.location == NSNotFound { break }
            result.append(SourceRange(location: r.location, length: r.length))
            from = r.location + max(1, r.length)
        }
        return result
    }

    /// Works out what editing the decision letter into `newText` (through
    /// `edits`) does to the marked comments and section starts.
    public func revision(newText raw: String, edits: [LetterEdit]) -> LetterRevision {
        let newText = raw.replacingOccurrences(of: "\r\n", with: "\n")
        var sources: [String: [SourceRange]] = [:]
        var changes: [AnchorChange] = []
        var shifted = 0
        for c in orderedComments where !c.source.isEmpty {
            var mapped: [SourceRange] = []
            var oldPieces: [String] = []
            var changedPieces: [Int] = []
            for (i, r) in c.source.enumerated() {
                let (m, touched) = Remap.map(r, through: edits)
                let t = Self.trimmed(m, in: newText)
                let old = sourceText(r)
                oldPieces.append(old)
                mapped.append(t)
                if touched && Self.substring(newText, t) != old { changedPieces.append(i) }
            }
            let oldText = oldPieces.joined(separator: "\n\n")
            let matched = c.text == oldText
            guard !changedPieces.isEmpty else {
                sources[c.key] = mapped
                if mapped != c.source { shifted += 1 }
                continue
            }
            // Look for each changed piece's old wording, once, in the new text.
            var relocated = mapped
            var allFound = true
            for i in changedPieces {
                let found = Self.occurrences(of: oldPieces[i], in: newText)
                if found.count == 1 { relocated[i] = found[0] } else { allFound = false }
            }
            if allFound {
                changes.append(AnchorChange(key: c.key, kind: .relocated, oldText: oldText, newText: oldText,
                                            newSource: relocated, commentMatchedOldText: matched))
                sources[c.key] = relocated
                continue
            }
            let remaining = mapped.filter { $0.length > 0 }
            let newPieces = remaining.map { Self.substring(newText, $0) }
            let kind: AnchorChange.Kind = remaining.isEmpty ? .removed : .edited
            changes.append(AnchorChange(key: c.key, kind: kind, oldText: oldText,
                                        newText: newPieces.joined(separator: "\n\n"),
                                        newSource: remaining, commentMatchedOldText: matched))
            sources[c.key] = remaining
        }
        var anchors: [String: Int] = [:]
        for s in sections {
            if let a = s.anchor { anchors[s.key] = min(Remap.map(offset: a, through: edits), newText.utf16.count) }
        }
        return LetterRevision(text: newText, sources: sources, anchors: anchors, changes: changes, shifted: shifted)
    }

    /// Applies an edit of the decision letter. `decisions` covers edited and
    /// removed comments; anything not decided takes the default.
    public mutating func apply(_ revision: LetterRevision, decisions: [String: AnchorDecision] = [:]) {
        decisionLetter = revision.text
        for i in sections.indices {
            if sections[i].anchor != nil, let a = revision.anchors[sections[i].key] { sections[i].anchor = a }
        }
        for (key, source) in revision.sources where comments[key] != nil {
            comments[key]?.source = source
        }
        for change in revision.changes where comments[change.key] != nil {
            switch change.kind == .relocated ? .useNewText : (decisions[change.key] ?? change.defaultDecision) {
            case .useNewText:
                comments[change.key]?.source = change.newSource
                if change.kind == .edited { comments[change.key]?.text = change.newText }
            case .keepCommentText:
                comments[change.key]?.source = change.newSource
            case .unmark:
                comments[change.key]?.source = []
            case .delete:
                deleteComment(change.key)
            }
        }
    }
}
