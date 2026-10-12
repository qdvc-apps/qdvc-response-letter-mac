import Foundation

public enum EditError: Error, Equatable, LocalizedError {
    case emptySelection
    case overlaps(String)
    case noSection
    case unknownComment
    case notAdjacent
    case splitPointAtEdge

    public var errorDescription: String? {
        switch self {
        case .emptySelection: return "Select some text first."
        case .overlaps(let id): return "The selection overlaps comment \(id). Comments can't overlap."
        case .noSection: return "Add a section (such as Reviewer 1) first."
        case .unknownComment: return "That comment no longer exists."
        case .notAdjacent: return "Only neighbouring comments in the same section can be merged."
        case .splitPointAtEdge: return "Put the insertion point inside the comment's text, where the second comment should begin."
        }
    }
}

/// A cross-reference that still needs a decision after a split.
public struct PendingReference: Identifiable, Equatable, Hashable {
    public var location: TextLocation
    /// Which pending cross-reference in that text (0-based).
    public var ordinal: Int
    public var candidates: [String]
    /// The paragraph it sits in, with the cross-reference shown as "[?]".
    public var context: String

    public var id: String { "\(location)#\(ordinal)" }
}

/// A comment whose display ID changed.
public struct Renumbering: Equatable, Hashable {
    public var key: String
    public var old: String
    public var new: String
}

public struct SplitResult: Equatable {
    public var firstKey: String
    public var secondKey: String
    /// Cross-references that pointed at the original comment.
    public var pending: [PendingReference]
    /// Comments that were related to the original; both parts are now
    /// related to them.
    public var relatedKeys: [String]
    public var renumbered: [Renumbering]
}

public struct MergeResult: Equatable {
    public var key: String
    public var renumbered: [Renumbering]
}

extension ResponseLetter {
    // MARK: - Sections

    public var nextReviewerNumber: Int {
        (sections.filter { $0.role == .reviewer }.compactMap(\.number).max() ?? 0) + 1
    }

    /// Adds a section, keeping sections that start in the decision letter in
    /// the letter's order. Returns its key.
    @discardableResult
    public mutating func addSection(role: SectionRole, number: Int? = nil, title: String? = nil,
                                    prefix: String? = nil, anchor: Int? = nil) -> String {
        let key = newKey("s")
        let section = LetterSection(key: key, role: role, number: number, title: title, prefix: prefix, anchor: anchor)
        if let anchor, let i = sections.firstIndex(where: { ($0.anchor ?? -1) > anchor }) {
            sections.insert(section, at: i)
        } else {
            sections.append(section)
        }
        return key
    }

    /// The section a comment starting at `offset` in the decision letter
    /// belongs to: the last one that starts before it.
    public func sectionKey(forOffset offset: Int) -> String? {
        sections.filter { ($0.anchor ?? Int.max) <= offset }
            .max { ($0.anchor ?? 0) < ($1.anchor ?? 0) }?.key
    }

    public mutating func updateSection(_ section: LetterSection) {
        guard let i = sectionIndex(key: section.key) else { return }
        sections[i] = section
    }

    /// Removes a section and its comments.
    public mutating func deleteSection(_ key: String) {
        guard let i = sectionIndex(key: key) else { return }
        for c in sections[i].commentKeys { _ = deleteComment(c) }
        sections.remove(at: i)
    }

    public mutating func moveSection(_ key: String, by delta: Int) {
        guard let i = sectionIndex(key: key) else { return }
        let j = i + delta
        guard sections.indices.contains(j) else { return }
        sections.swapAt(i, j)
    }

    // MARK: - Comments

    static func isSpace(_ u: UInt16) -> Bool {
        u == 0x20 || u == 0x0A || u == 0x0D || u == 0x09 || u == 0xA0 || u == 0x2028 || u == 0x2029
    }

    /// `range` without whitespace at either end.
    public func trimmed(_ range: SourceRange) -> SourceRange {
        let u = Array(decisionLetter.utf16)
        var a = max(0, min(range.location, u.count))
        var b = max(a, min(range.end, u.count))
        while a < b, Self.isSpace(u[a]) { a += 1 }
        while b > a, Self.isSpace(u[b - 1]) { b -= 1 }
        return SourceRange(location: a, length: b - a)
    }

    /// The comment whose source contains `offset`.
    public func commentKey(atSourceOffset offset: Int) -> String? {
        for c in orderedComments where c.source.contains(where: { $0.location <= offset && offset < $0.end }) {
            return c.key
        }
        return nil
    }

    /// Marks text in the decision letter as a comment. Returns its key.
    @discardableResult
    public mutating func markComment(_ selection: SourceRange, inSection sectionKey: String) throws -> String {
        let range = trimmed(selection)
        guard range.length > 0 else { throw EditError.emptySelection }
        guard let si = sectionIndex(key: sectionKey) else { throw EditError.noSection }
        for c in orderedComments where c.source.contains(where: { $0.overlaps(range) }) {
            throw EditError.overlaps(displayID(c.key) ?? "?")
        }
        let key = newKey("c")
        comments[key] = Comment(key: key, text: sourceText(range), source: [range])
        // Keep source order within the section.
        let keys = sections[si].commentKeys
        let at = keys.firstIndex { k in
            (comments[k]?.source.first?.location ?? -1) > range.location
        } ?? keys.count
        sections[si].commentKeys.insert(key, at: at)
        return key
    }

    /// Adds a comment that isn't in the decision letter (typed or pasted).
    @discardableResult
    public mutating func addComment(inSection sectionKey: String, after: String? = nil, text: String = "") -> String? {
        guard let si = sectionIndex(key: sectionKey) else { return nil }
        let key = newKey("c")
        comments[key] = Comment(key: key, text: text)
        if let after, let i = sections[si].commentKeys.firstIndex(of: after) {
            sections[si].commentKeys.insert(key, at: i + 1)
        } else {
            sections[si].commentKeys.append(key)
        }
        return key
    }

    /// Cross-references pointing at `key`, anywhere.
    public func referenceCount(to key: String) -> Int {
        textLocations.reduce(0) { n, loc in
            n + RichText(markup: markup(at: loc)).tokens.filter {
                if case .ref(let keys) = $0.token { return keys.contains(key) }
                return false
            }.count
        }
    }

    /// Deletes a comment. Cross-references to it stay, flagged as broken
    /// (Diagnostics). Returns how many there are.
    @discardableResult
    public mutating func deleteComment(_ key: String) -> Int {
        let refs = referenceCount(to: key)
        for i in sections.indices { sections[i].commentKeys.removeAll { $0 == key } }
        for k in comments.keys where comments[k]?.related.contains(key) == true {
            comments[k]?.related.removeAll { $0 == key }
        }
        comments[key] = nil
        return refs
    }

    /// Moves a comment to `index` in a section (renumbering both).
    public mutating func moveComment(_ key: String, toSection sectionKey: String, at index: Int) {
        guard comments[key] != nil, let to = sectionIndex(key: sectionKey) else { return }
        var target = index
        if let from = sectionIndex(ofComment: key), let i = sections[from].commentKeys.firstIndex(of: key) {
            sections[from].commentKeys.remove(at: i)
            if from == to && i < target { target -= 1 }
        }
        target = max(0, min(target, sections[to].commentKeys.count))
        sections[to].commentKeys.insert(key, at: target)
    }

    /// Moves comments within a section, like a list drag (SwiftUI's onMove).
    public mutating func moveComments(inSection sectionKey: String, fromOffsets: IndexSet, toOffset: Int) {
        guard let si = sectionIndex(key: sectionKey) else { return }
        var keys = sections[si].commentKeys
        let moving = fromOffsets.sorted().filter { keys.indices.contains($0) }.map { keys[$0] }
        let before = fromOffsets.filter { $0 < toOffset }.count
        for i in fromOffsets.sorted(by: >) where keys.indices.contains(i) { keys.remove(at: i) }
        let at = max(0, min(toOffset - before, keys.count))
        keys.insert(contentsOf: moving, at: at)
        sections[si].commentKeys = keys
    }

    public func neighbour(of key: String, offset: Int) -> String? {
        guard let si = sectionIndex(ofComment: key),
              let i = sections[si].commentKeys.firstIndex(of: key) else { return nil }
        let j = i + offset
        return sections[si].commentKeys.indices.contains(j) ? sections[si].commentKeys[j] : nil
    }

    // MARK: - Related

    public mutating func setRelated(_ a: String, _ b: String, _ related: Bool) {
        guard a != b, comments[a] != nil, comments[b] != nil else { return }
        if related {
            if comments[a]?.related.contains(b) == false { comments[a]?.related.append(b) }
            if comments[b]?.related.contains(a) == false { comments[b]?.related.append(a) }
        } else {
            comments[a]?.related.removeAll { $0 == b }
            comments[b]?.related.removeAll { $0 == a }
        }
    }

    // MARK: - Rewriting cross-references

    mutating func rewriteRefs(_ transform: ([String]) -> [String]?) {
        for loc in textLocations {
            let original = markup(at: loc)
            guard original.contains("{{ref:") else { continue }
            let rich = RichText(markup: original)
            let rewritten = rich.replacingTokens { token in
                guard case .ref(let keys) = token, let new = transform(keys) else { return nil }
                return [.token(.ref(new))]
            }
            if rewritten != rich { setMarkup(rewritten.markup, at: loc) }
        }
    }

    static func unique(_ keys: [String]) -> [String] {
        var seen = Set<String>()
        return keys.filter { seen.insert($0).inserted }
    }

    func renumbering(from before: [String: String]) -> [Renumbering] {
        let after = idMap()
        return orderedCommentKeys.compactMap { key in
            guard let old = before[key], let new = after[key], old != new else { return nil }
            return Renumbering(key: key, old: old, new: new)
        }
    }

    // MARK: - Split

    /// Splits a comment in two at a UTF-16 offset into its text. The first
    /// part keeps the response, ideas, status and triage; the second gets
    /// the same triage and related comments and starts "to do".
    /// Cross-references to the comment become pending, to be resolved with
    /// `resolvePending`.
    public mutating func splitComment(_ key: String, atUTF16 offset: Int) throws -> SplitResult {
        guard var first = comments[key], let si = sectionIndex(ofComment: key),
              let position = sections[si].commentKeys.firstIndex(of: key) else {
            throw EditError.unknownComment
        }
        let before = idMap()
        let u = first.text.utf16
        guard offset > 0, offset < u.count,
              let cut = String.Index(u.index(u.startIndex, offsetBy: offset), within: first.text) else {
            throw EditError.splitPointAtEdge
        }
        let head = String(first.text[..<cut]).trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = String(first.text[cut...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !head.isEmpty, !tail.isEmpty else { throw EditError.splitPointAtEdge }

        let (sourceA, sourceB) = splitSource(of: first, atUTF16: offset)
        let secondKey = newKey("c")
        let second = Comment(key: secondKey, text: tail, triage: first.triage, status: .todo,
                             related: first.related, source: sourceB)
        first.text = head
        first.source = sourceA
        comments[key] = first
        comments[secondKey] = second
        sections[si].commentKeys.insert(secondKey, at: position + 1)
        for r in first.related where comments[r] != nil {
            if comments[r]?.related.contains(secondKey) == false { comments[r]?.related.append(secondKey) }
        }
        rewriteRefs { keys in
            guard let i = keys.firstIndex(of: key) else { return nil }
            var new = keys
            new.insert(secondKey, at: i + 1)
            return Self.unique(new)
        }
        let pending = pendingReferences().filter { $0.candidates.contains(key) && $0.candidates.contains(secondKey) }
        return SplitResult(firstKey: key, secondKey: secondKey, pending: pending,
                           relatedKeys: first.related, renumbered: renumbering(from: before))
    }

    /// Splits the source ranges when the comment's text is still exactly the
    /// marked text; otherwise the first part keeps them all.
    func splitSource(of c: Comment, atUTF16 offset: Int) -> ([SourceRange], [SourceRange]) {
        let separator = "\n\n".utf16.count
        let joined = c.source.map(sourceText).joined(separator: "\n\n")
        guard !c.source.isEmpty, joined == c.text else { return (c.source, []) }
        var a: [SourceRange] = []
        var b: [SourceRange] = []
        var walked = 0
        for r in c.source {
            if walked + r.length <= offset {
                a.append(r)
            } else if walked >= offset {
                b.append(r)
            } else {
                let local = offset - walked
                a.append(trimmed(SourceRange(location: r.location, length: local)))
                b.append(trimmed(SourceRange(location: r.location + local, length: r.length - local)))
            }
            walked += r.length + separator
        }
        return (a.filter { $0.length > 0 }, b.filter { $0.length > 0 })
    }

    // MARK: - Merge

    /// Merges a comment with the next one in its section. Cross-references
    /// and related links to the second now point at the first.
    public mutating func mergeComment(_ key: String, withNext next: String) throws -> MergeResult {
        guard var a = comments[key], let b = comments[next] else { throw EditError.unknownComment }
        guard neighbour(of: key, offset: 1) == next else { throw EditError.notAdjacent }
        let before = idMap()
        a.text = [a.text, b.text].filter { !$0.isEmpty }.joined(separator: "\n\n")
        a.ideas += b.ideas
        a.response = [a.response, b.response].filter { !$0.isEmpty }.joined(separator: "\n")
        a.triage = max(a.triage, b.triage)
        a.status = min(a.status, b.status)
        a.related = Self.unique(a.related + b.related).filter { $0 != key && $0 != next }
        a.source = (a.source + b.source).sorted()
        comments[key] = a
        for i in sections.indices { sections[i].commentKeys.removeAll { $0 == next } }
        comments[next] = nil
        for k in comments.keys where comments[k]?.related.contains(next) == true {
            var related = comments[k]!.related.map { $0 == next ? key : $0 }
            related = Self.unique(related).filter { $0 != k }
            comments[k]?.related = related
        }
        rewriteRefs { keys in
            guard keys.contains(next) else { return nil }
            return Self.unique(keys.map { $0 == next ? key : $0 })
        }
        return MergeResult(key: key, renumbered: renumbering(from: before))
    }

    // MARK: - Pending cross-references

    public func pendingReferences() -> [PendingReference] {
        var result: [PendingReference] = []
        for loc in textLocations {
            let m = markup(at: loc)
            guard m.contains("|") else { continue }
            let rich = RichText(markup: m)
            var ordinal = 0
            for p in rich.paragraphs {
                for inline in p.inlines {
                    guard case .token(let t, _) = inline, t.isPending, case .ref(let keys) = t else { continue }
                    var marked = false
                    let context = RichText(paragraphs: [p]).plainText { tok in
                        if tok == t && !marked {
                            marked = true
                            return "[?]"
                        }
                        return self.tokenDisplay(tok)
                    }
                    result.append(PendingReference(location: loc, ordinal: ordinal, candidates: keys, context: context))
                    ordinal += 1
                }
            }
        }
        return result
    }

    /// Resolves a pending cross-reference to one or more of its candidates
    /// ("RE1-05 and RE1-06" when more than one).
    @discardableResult
    public mutating func resolvePending(_ ref: PendingReference, choosing keys: [String]) -> Bool {
        let chosen = keys.filter { ref.candidates.contains($0) }
        guard !chosen.isEmpty else { return false }
        let rich = RichText(markup: markup(at: ref.location))
        var ordinal = 0
        var done = false
        let rewritten = rich.replacingTokens { token in
            guard token.isPending, !done else { return nil }
            defer { ordinal += 1 }
            guard ordinal == ref.ordinal else { return nil }
            done = true
            var pieces: [InlinePiece] = []
            for (i, k) in chosen.enumerated() {
                if i > 0 { pieces.append(.text(i == chosen.count - 1 ? " and " : ", ")) }
                pieces.append(.token(.ref([k])))
            }
            return pieces
        }
        guard done else { return false }
        setMarkup(rewritten.markup, at: ref.location)
        return true
    }

    // MARK: - Variables

    @discardableResult
    public mutating func addVariable(name: String, value: String) -> String {
        let key = newKey("v")
        variables.append(Variable(key: key, name: name, value: value))
        return key
    }

    public mutating func updateVariable(_ variable: Variable) {
        guard let i = variables.firstIndex(where: { $0.key == variable.key }) else { return }
        variables[i] = variable
    }

    /// Deletes a Variable; wherever it was used, its value stays as plain
    /// text.
    public mutating func deleteVariable(_ key: String) {
        let value = variable(key)?.value ?? ""
        for loc in textLocations {
            let original = markup(at: loc)
            guard original.contains("{{var:\(key)}}") else { continue }
            let rewritten = RichText(markup: original).replacingTokens { token in
                token == .variable(key) ? [.text(value)] : nil
            }
            setMarkup(rewritten.markup, at: loc)
        }
        variables.removeAll { $0.key == key }
    }

    /// Where each Variable is used.
    public func variableUses() -> [String: [TextLocation]] {
        var uses: [String: [TextLocation]] = [:]
        for loc in textLocations {
            let m = markup(at: loc)
            guard m.contains("{{var:") else { continue }
            for (_, token) in RichText(markup: m).tokens {
                if case .variable(let key) = token { uses[key, default: []].append(loc) }
            }
        }
        return uses
    }

    // MARK: - Display

    /// How a token reads: a Variable's value, a comment's ID.
    public func tokenDisplay(_ token: Token, ids: [String: String]? = nil) -> String {
        switch token {
        case .variable(let key):
            return variable(key)?.value ?? "[missing variable]"
        case .ref(let keys):
            let map = ids ?? idMap()
            let names = keys.map { map[$0] ?? "[deleted comment]" }
            return keys.count == 1 ? names[0] : names.joined(separator: "/") + " [?]"
        }
    }
}

// MARK: - Undo

extension ResponseLetter {
    /// Undoes one change (from `before` to `after`) in the current letter,
    /// touching only what that change touched: whole sections, variables,
    /// settings, opening or closing, and for comments field by field. Typing
    /// done since in another field of the same comment is kept.
    public mutating func revert(changesFrom before: ResponseLetter, to after: ResponseLetter) {
        if before.settings != after.settings { settings = before.settings }
        if before.sections != after.sections { sections = before.sections }
        if before.variables != after.variables { variables = before.variables }
        if before.opening != after.opening { opening = before.opening }
        if before.closing != after.closing { closing = before.closing }
        for key in Set(before.comments.keys).union(after.comments.keys) {
            let b = before.comments[key]
            let a = after.comments[key]
            guard b != a else { continue }
            guard let b else { comments[key] = nil; continue }
            guard let a, var c = comments[key] else { comments[key] = b; continue }
            if b.text != a.text { c.text = b.text }
            if b.ideas != a.ideas { c.ideas = b.ideas }
            if b.response != a.response { c.response = b.response }
            if b.triage != a.triage { c.triage = b.triage }
            if b.status != a.status { c.status = b.status }
            if b.related != a.related { c.related = b.related }
            if b.source != a.source { c.source = b.source }
            comments[key] = c
        }
    }
}

// MARK: - Text tidying

public enum TextTools {
    /// Joins hard-wrapped lines into paragraphs: a single line break becomes
    /// a space; blank lines, and lines that start like a list item, keep
    /// their breaks.
    public static func unwrap(_ s: String) -> String {
        let lines = s.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var out: [String] = []
        var current: String?
        func startsItem(_ line: String) -> Bool {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("- ") || t.hasPrefix("• ") || t.hasPrefix("* ") || t.hasPrefix("–") { return true }
            let digits = t.prefix(while: { $0.isNumber })
            if !digits.isEmpty, let next = t.dropFirst(digits.count).first, next == "." || next == ")" { return true }
            if t.hasPrefix("("), let close = t.firstIndex(of: ")"), t.distance(from: t.startIndex, to: close) <= 4 {
                return true
            }
            return false
        }
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                if let c = current { out.append(c); current = nil }
                out.append("")
                continue
            }
            if let c = current, !startsItem(line) {
                current = c + " " + line
            } else {
                if let c = current { out.append(c) }
                current = line
            }
        }
        if let c = current { out.append(c) }
        // Collapse runs of blank lines.
        var result: [String] = []
        for line in out where !(line.isEmpty && (result.last?.isEmpty ?? true)) {
            result.append(line)
        }
        while result.last?.isEmpty == true { result.removeLast() }
        return result.joined(separator: "\n")
    }

    /// The first line (or `limit` characters) of `s`, for lists.
    public static func excerpt(_ s: String, limit: Int = 120) -> String {
        let flat = s.split(whereSeparator: { $0.isNewline }).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        if flat.count <= limit { return flat }
        return String(flat.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
