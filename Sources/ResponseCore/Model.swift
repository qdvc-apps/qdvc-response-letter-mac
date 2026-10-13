import Foundation

/// How hard a comment looks to address.
public enum Triage: String, CaseIterable, Equatable, Hashable, Comparable {
    case none, green, yellow, red

    public var label: String {
        switch self {
        case .none: return "Not triaged"
        case .green: return "Trivial"
        case .yellow: return "Clear solution"
        case .red: return "Needs discussion"
        }
    }

    var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    public static func < (a: Triage, b: Triage) -> Bool { a.rank < b.rank }
}

/// How far along the response to a comment is.
public enum Status: String, CaseIterable, Equatable, Hashable, Comparable {
    case todo, drafted, final

    public var label: String {
        switch self {
        case .todo: return "To do"
        case .drafted: return "Drafted"
        case .final: return "Final"
        }
    }

    var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    public static func < (a: Status, b: Status) -> Bool { a.rank < b.rank }

    public init?(lenient raw: String) {
        switch raw.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "") {
        case "todo", "": self = .todo
        case "drafted", "draft": self = .drafted
        case "final", "done": self = .final
        default: return nil
        }
    }
}

/// Who wrote a block of comments.
public enum SectionRole: String, CaseIterable, Equatable, Hashable {
    case seniorEditor = "senior-editor"
    case associateEditor = "associate-editor"
    case specialIssueEditor = "special-issue-editor"
    case departmentEditor = "department-editor"
    case trackChair = "track-chair"
    case reviewer
    case other

    public var label: String {
        switch self {
        case .seniorEditor: return "Senior Editor"
        case .associateEditor: return "Associate Editor"
        case .specialIssueEditor: return "Special Issue Editor"
        case .departmentEditor: return "Department Editor"
        case .trackChair: return "Track Chair"
        case .reviewer: return "Reviewer"
        case .other: return "Other"
        }
    }

    public var isNumbered: Bool { self == .reviewer }

    public func defaultTitle(number: Int?) -> String {
        if self == .reviewer { return "Reviewer \(number ?? 1)" }
        if self == .other { return "Comments" }
        return label
    }

    public func defaultPrefix(number: Int?) -> String {
        switch self {
        case .seniorEditor: return "SE"
        case .associateEditor: return "AE"
        case .specialIssueEditor: return "SIE"
        case .departmentEditor: return "DE"
        case .trackChair: return "TC"
        case .reviewer: return "RE\(number ?? 1)"
        case .other: return "C"
        }
    }
}

/// A run of text in the decision letter, in UTF-16 code units (the units of
/// NSString and NSTextView).
public struct SourceRange: Equatable, Hashable, Comparable {
    public var location: Int
    public var length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }

    public var end: Int { location + length }

    public func overlaps(_ other: SourceRange) -> Bool {
        location < other.end && other.location < end
    }

    public static func < (a: SourceRange, b: SourceRange) -> Bool {
        (a.location, a.length) < (b.location, b.length)
    }

    /// "120+340" in the files.
    public var text: String { "\(location)+\(length)" }

    public init?(text: String) {
        let parts = text.split(separator: "+")
        guard parts.count == 2,
              let loc = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let len = Int(parts[1].trimmingCharacters(in: .whitespaces)),
              loc >= 0, len >= 0 else { return nil }
        self.init(location: loc, length: len)
    }
}

public struct LetterSection: Identifiable, Equatable, Hashable {
    public var key: String
    public var role: SectionRole
    /// Reviewer number (reviewers only).
    public var number: Int?
    /// "Reviewer 1"; the export heading is "Reviewer 1 comments".
    public var title: String
    /// "RE1" gives RE1-01, RE1-02, …
    public var prefix: String
    /// Where the section starts in the decision letter (UTF-16 offset), so
    /// comments marked after it land in it.
    public var anchor: Int?
    /// The comments, in order: their position gives their number.
    public var commentKeys: [String]

    public var id: String { key }

    public init(key: String, role: SectionRole, number: Int? = nil, title: String? = nil,
                prefix: String? = nil, anchor: Int? = nil, commentKeys: [String] = []) {
        self.key = key
        self.role = role
        self.number = role.isNumbered ? (number ?? 1) : number
        self.title = title ?? role.defaultTitle(number: number)
        self.prefix = prefix ?? role.defaultPrefix(number: number)
        self.anchor = anchor
        self.commentKeys = commentKeys
    }

    public var heading: String { "\(title) comments" }
}

public struct Comment: Identifiable, Equatable, Hashable {
    public var key: String
    /// The editor's or reviewer's words, as marked in the decision letter
    /// (and possibly tidied up since).
    public var text: String
    /// Initial ideas for a response, one dot point each, each a line of
    /// markup (so they can hold Variables and Cross-references).
    public var ideas: [String]
    /// The response, in markup (RichText).
    public var response: String
    public var triage: Triage
    public var status: Status
    /// Keys of related comments (kept symmetric).
    public var related: [String]
    /// Where the comment came from in the decision letter.
    public var source: [SourceRange]

    public var id: String { key }

    public init(key: String, text: String = "", ideas: [String] = [], response: String = "",
                triage: Triage = .none, status: Status = .todo, related: [String] = [],
                source: [SourceRange] = []) {
        self.key = key
        self.text = text
        self.ideas = ideas
        self.response = response
        self.triage = triage
        self.status = status
        self.related = related
        self.source = source
    }

    public var responseText: RichText { RichText(markup: response) }
}

/// A piece of text with one official version, used in many places (a page
/// number, a sample size, a quotation): change it once, it changes
/// everywhere.
public struct Variable: Identifiable, Equatable, Hashable {
    public var key: String
    /// What it is ("Page of Hypothesis 2"); only shown in the app.
    public var name: String
    /// What it says ("p. 14"); printed wherever it is used.
    public var value: String

    public var id: String { key }

    public init(key: String, name: String, value: String) {
        self.key = key
        self.name = name
        self.value = value
    }
}

public enum QuoteStyle: String, CaseIterable, Equatable {
    case italic, blue, plain

    public var label: String {
        switch self {
        case .italic: return "Indented, italic"
        case .blue: return "Indented, blue"
        case .plain: return "Indented"
        }
    }
}

public struct LetterSettings: Equatable {
    public var title: String
    public var manuscript: String
    /// Between prefix and number: "RE1-01".
    public var separator: String
    /// Zero-padding of the number: 2 gives "01".
    public var digits: Int
    public var fontName: String
    public var fontSize: Double
    public var quoteStyle: QuoteStyle

    public init(title: String = "Response to the editors and reviewers", manuscript: String = "",
                separator: String = "-", digits: Int = 2, fontName: String = "Times New Roman",
                fontSize: Double = 11, quoteStyle: QuoteStyle = .italic) {
        self.title = title
        self.manuscript = manuscript
        self.separator = separator
        self.digits = digits
        self.fontName = fontName
        self.fontSize = fontSize
        self.quoteStyle = quoteStyle
    }
}

/// Where a piece of rich text lives.
public enum TextLocation: Hashable {
    case response(String)
    /// A comment's ideas, one line of markup per idea.
    case ideas(String)
    case opening
    case closing
}

/// The whole response letter: the value the app edits and the workspace
/// stores.
public struct ResponseLetter: Equatable {
    public var settings: LetterSettings
    /// The decision letter as pasted (line endings normalised to "\n").
    public var decisionLetter: String
    public var sections: [LetterSection]
    public var comments: [String: Comment]
    public var variables: [Variable]
    /// Markup before and after the table.
    public var opening: String
    public var closing: String

    public init(settings: LetterSettings = LetterSettings(), decisionLetter: String = "",
                sections: [LetterSection] = [], comments: [String: Comment] = [:],
                variables: [Variable] = [], opening: String = "", closing: String = "") {
        self.settings = settings
        self.decisionLetter = decisionLetter
        self.sections = sections
        self.comments = comments
        self.variables = variables
        self.opening = opening
        self.closing = closing
    }

    // MARK: Lookups

    /// Comments in letter order.
    public var orderedComments: [Comment] {
        sections.flatMap { $0.commentKeys.compactMap { comments[$0] } }
    }

    public var orderedCommentKeys: [String] { sections.flatMap(\.commentKeys) }

    public func sectionIndex(ofComment key: String) -> Int? {
        sections.firstIndex { $0.commentKeys.contains(key) }
    }

    public func section(ofComment key: String) -> LetterSection? {
        sectionIndex(ofComment: key).map { sections[$0] }
    }

    public func sectionIndex(key: String) -> Int? {
        sections.firstIndex { $0.key == key }
    }

    public func variable(_ key: String) -> Variable? {
        variables.first { $0.key == key }
    }

    // MARK: Numbering

    public func formatID(prefix: String, index: Int) -> String {
        let number = String(format: "%0\(max(1, min(settings.digits, 6)))d", index + 1)
        return prefix.isEmpty ? number : prefix + settings.separator + number
    }

    /// Display IDs ("RE1-03") by comment key, from each comment's position.
    public func idMap() -> [String: String] {
        var map: [String: String] = [:]
        for section in sections {
            for (i, key) in section.commentKeys.enumerated() {
                map[key] = formatID(prefix: section.prefix, index: i)
            }
        }
        return map
    }

    public func displayID(_ key: String) -> String? {
        for section in sections {
            if let i = section.commentKeys.firstIndex(of: key) {
                return formatID(prefix: section.prefix, index: i)
            }
        }
        return nil
    }

    // MARK: Rich text locations

    public var textLocations: [TextLocation] {
        [.opening] + orderedCommentKeys.flatMap { [TextLocation.ideas($0), .response($0)] } + [.closing]
    }

    public func markup(at location: TextLocation) -> String {
        switch location {
        case .opening: return opening
        case .closing: return closing
        case .response(let key): return comments[key]?.response ?? ""
        case .ideas(let key): return comments[key]?.ideas.joined(separator: "\n") ?? ""
        }
    }

    public mutating func setMarkup(_ markup: String, at location: TextLocation) {
        switch location {
        case .opening: opening = markup
        case .closing: closing = markup
        case .response(let key): comments[key]?.response = markup
        case .ideas(let key): comments[key]?.ideas = Self.ideaLines(markup, keepEmpty: true)
        }
    }

    /// Ideas from markup: one idea per line, without quote or bullet marks
    /// (ideas are always bullets). `keepEmpty` keeps empty lines, as while
    /// typing (Return starts the next idea); otherwise trailing ones go.
    public static func ideaLines(_ markup: String, keepEmpty: Bool = false) -> [String] {
        var lines = markup.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n").map { line -> String in
            guard !line.isEmpty else { return "" }
            var p = RichText(markup: line).paragraphs.first ?? RichParagraph()
            p.block = .normal
            return RichText(paragraphs: [p]).markup
        }
        if !keepEmpty {
            while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
        }
        return lines
    }

    /// An idea as plain text, with its Variables and Cross-references shown.
    public func ideaText(_ idea: String, ids: [String: String]? = nil) -> String {
        RichText(markup: idea).plainText { self.tokenDisplay($0, ids: ids) }
    }

    // MARK: Decision letter text

    /// The decision letter text in `range` (clamped).
    public func sourceText(_ range: SourceRange) -> String {
        Self.substring(decisionLetter, range)
    }

    static func substring(_ s: String, _ range: SourceRange) -> String {
        let u = s.utf16
        let start = max(0, min(range.location, u.count))
        let end = max(start, min(range.end, u.count))
        guard let a = String.Index(u.index(u.startIndex, offsetBy: start), within: s),
              let b = String.Index(u.index(u.startIndex, offsetBy: end), within: s) else {
            let ns = s as NSString
            return ns.substring(with: NSRange(location: start, length: end - start))
        }
        return String(s[a..<b])
    }

    // MARK: Progress

    public struct Progress: Equatable {
        public var total = 0
        public var byStatus: [Status: Int] = [:]
        public var byTriage: [Triage: Int] = [:]
        /// Triaged, and with at least one idea written down.
        public var triagedWithIdeas = 0

        public var triaged: Int { total - count(.none) }

        public init() {}

        public func count(_ s: Status) -> Int { byStatus[s] ?? 0 }
        public func count(_ t: Triage) -> Int { byTriage[t] ?? 0 }

        public var fractionFinal: Double { total == 0 ? 0 : Double(count(.final)) / Double(total) }
        /// Drafted counts half.
        public var fractionDone: Double {
            total == 0 ? 0 : (Double(count(.final)) + 0.5 * Double(count(.drafted))) / Double(total)
        }
    }

    public func progress(keys: [String]? = nil) -> Progress {
        var p = Progress()
        for key in keys ?? orderedCommentKeys {
            guard let c = comments[key] else { continue }
            p.total += 1
            p.byStatus[c.status, default: 0] += 1
            p.byTriage[c.triage, default: 0] += 1
            if c.triage != .none, c.ideas.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                p.triagedWithIdeas += 1
            }
        }
        return p
    }
}

// MARK: - Keys

public enum Keys {
    /// A new stable key ("c-1a2b3c4d") not in `taken`.
    public static func make(_ prefix: String, avoiding taken: (String) -> Bool) -> String {
        while true {
            let key = prefix + "-" + String(format: "%08x", UInt32.random(in: 0...UInt32.max))
            if !taken(key) { return key }
        }
    }
}

extension ResponseLetter {
    public func isKeyTaken(_ key: String) -> Bool {
        comments[key] != nil || sections.contains { $0.key == key } || variables.contains { $0.key == key }
    }

    public func newKey(_ prefix: String) -> String {
        Keys.make(prefix, avoiding: isKeyTaken)
    }
}
