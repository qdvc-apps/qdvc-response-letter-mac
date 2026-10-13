import Foundation

/// Something the user should look at before sending the letter.
public struct Issue: Identifiable, Equatable, Hashable {
    public enum Kind: String, Equatable, Hashable {
        case pendingReference
        case brokenReference
        case duplicateReference
        case selfReference
        case missingVariable
        case emptyVariable
        case unusedVariable
        case finalWithoutResponse
        case emptyComment

        /// Problems that would show in the exported letter.
        public var isBlocking: Bool {
            switch self {
            case .pendingReference, .brokenReference, .missingVariable, .emptyVariable: return true
            default: return false
            }
        }
    }

    public var kind: Kind
    public var location: TextLocation?
    /// The comment involved (for navigation).
    public var commentKey: String?
    public var variableKey: String?
    public var message: String
    /// Set for `.pendingReference`.
    public var pending: PendingReference?

    public init(kind: Kind, location: TextLocation? = nil, commentKey: String? = nil, variableKey: String? = nil,
                message: String, pending: PendingReference? = nil) {
        self.kind = kind
        self.location = location
        self.commentKey = commentKey
        self.variableKey = variableKey
        self.message = message
        self.pending = pending
    }

    public var id: String {
        "\(kind.rawValue)|\(String(describing: location))|\(commentKey ?? "")|\(variableKey ?? "")|\(pending?.id ?? "")|\(message)"
    }
}

extension ResponseLetter {
    public static func describe(_ location: TextLocation, ids: [String: String]) -> String {
        switch location {
        case .opening: return "the opening"
        case .closing: return "the closing"
        case .response(let key): return "the response to \(ids[key] ?? "?")"
        case .ideas(let key): return "the ideas for \(ids[key] ?? "?")"
        }
    }

    public func issues() -> [Issue] {
        let ids = idMap()
        var result: [Issue] = []
        var used = Set<String>()

        for p in pendingReferences() {
            let names = p.candidates.map { ids[$0] ?? "?" }.joined(separator: " or ")
            result.append(Issue(kind: .pendingReference, location: p.location, commentKey: commentKey(of: p.location),
                                message: "In \(Self.describe(p.location, ids: ids)), a cross-reference needs a decision: \(names)?",
                                pending: p))
        }

        for loc in textLocations {
            let m = markup(at: loc)
            guard m.contains("{{") else { continue }
            let rich = RichText(markup: m)
            let place = Self.describe(loc, ids: ids)
            for (pi, p) in rich.paragraphs.enumerated() {
                var seenRefs = Set<String>()
                for inline in p.inlines {
                    guard case .token(let token, _) = inline else { continue }
                    switch token {
                    case .variable(let key):
                        used.insert(key)
                        if variable(key) == nil {
                            result.append(Issue(kind: .missingVariable, location: loc, commentKey: commentKey(of: loc),
                                                variableKey: key,
                                                message: "In \(place), a Variable has been deleted (paragraph \(pi + 1))."))
                        }
                    case .ref(let keys):
                        for k in keys where ids[k] == nil {
                            result.append(Issue(kind: .brokenReference, location: loc, commentKey: commentKey(of: loc),
                                                message: "In \(place), a cross-reference points to a deleted comment (paragraph \(pi + 1))."))
                        }
                        guard keys.count == 1, let k = keys.first, ids[k] != nil else { continue }
                        if !seenRefs.insert(k).inserted {
                            result.append(Issue(kind: .duplicateReference, location: loc, commentKey: commentKey(of: loc),
                                                message: "In \(place), \(ids[k]!) is cross-referenced twice in one paragraph (paragraph \(pi + 1))."))
                        }
                        if case .response(let own) = loc, own == k {
                            result.append(Issue(kind: .selfReference, location: loc, commentKey: own,
                                                message: "The response to \(ids[k]!) cross-references itself."))
                        }
                    }
                }
            }
        }

        let uses = variableUses()
        for v in variables {
            if v.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, uses[v.key] != nil {
                result.append(Issue(kind: .emptyVariable, variableKey: v.key,
                                    message: "The Variable “\(v.name)” is used but has no value."))
            }
            if !used.contains(v.key) {
                result.append(Issue(kind: .unusedVariable, variableKey: v.key,
                                    message: "The Variable “\(v.name)” isn't used anywhere."))
            }
        }

        for c in orderedComments {
            let id = ids[c.key] ?? "?"
            if c.status == .final && RichText(markup: c.response).paragraphs.allSatisfy(\.isEmpty) {
                result.append(Issue(kind: .finalWithoutResponse, location: .response(c.key), commentKey: c.key,
                                    message: "\(id) is marked final but has no response."))
            }
            if c.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(Issue(kind: .emptyComment, commentKey: c.key, message: "\(id) has no comment text."))
            }
        }
        return result
    }

    func commentKey(of location: TextLocation) -> String? {
        switch location {
        case .response(let key), .ideas(let key): return key
        case .opening, .closing: return nil
        }
    }
}

// MARK: - Links between comments (Traceability)

/// A link between two comments: related (no direction), or a
/// cross-reference from the comment whose response mentions the other.
public struct CommentLink: Hashable {
    public enum Kind: Hashable {
        case related
        case reference
        /// A cross-reference still waiting for a decision after a split.
        case pendingReference
    }

    public var from: String
    public var to: String
    public var kind: Kind

    public init(from: String, to: String, kind: Kind) {
        self.from = from
        self.to = to
        self.kind = kind
    }
}

extension ResponseLetter {
    /// Every link between existing comments, without duplicates; related
    /// links are given once, from the earlier comment to the later.
    /// Cross-references count from a comment's response and its ideas.
    public func links() -> [CommentLink] {
        var position: [String: Int] = [:]
        for (i, k) in orderedCommentKeys.enumerated() { position[k] = i }
        var seen = Set<CommentLink>()
        var out: [CommentLink] = []
        func add(_ link: CommentLink) {
            if seen.insert(link).inserted { out.append(link) }
        }
        for key in orderedCommentKeys {
            guard let c = comments[key], let pk = position[key] else { continue }
            for r in c.related {
                guard let pr = position[r], r != key else { continue }
                add(pk < pr ? CommentLink(from: key, to: r, kind: .related) : CommentLink(from: r, to: key, kind: .related))
            }
            let markup = c.response + "\n" + c.ideas.joined(separator: "\n")
            guard markup.contains("{{ref:") else { continue }
            for (_, token) in RichText(markup: markup).tokens {
                guard case .ref(let keys) = token else { continue }
                for k in keys where k != key && position[k] != nil {
                    add(CommentLink(from: key, to: k, kind: keys.count == 1 ? .reference : .pendingReference))
                }
            }
        }
        return out
    }
}
