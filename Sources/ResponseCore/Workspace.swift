import Foundation

/// One file (or group of files) of a workspace, for saving only what changed.
public enum WorkspacePart: Hashable {
    case settings
    case sections
    case variables
    case opening
    case closing
    /// A comment's file; deleted if the comment no longer exists.
    case comment(String)
}

public struct WorkspaceError: Error, LocalizedError, Equatable {
    public var file: String
    public var message: String

    public init(file: String, message: String) {
        self.file = file
        self.message = message
    }

    public var errorDescription: String? { "\(file): \(message)" }
}

/// A loaded workspace, with notes about anything that had to be repaired.
public struct LoadedWorkspace {
    public var letter: ResponseLetter
    public var notes: [String]
    /// Parts that were repaired on load and should be written back.
    public var repairedParts: Set<WorkspacePart>

    public init(letter: ResponseLetter, notes: [String], repairedParts: Set<WorkspacePart>) {
        self.letter = letter
        self.notes = notes
        self.repairedParts = repairedParts
    }
}

/// Modification date and size of a file, to notice outside changes (Git).
public struct FileStamp: Equatable {
    public var modified: Date
    public var size: Int

    public init(modified: Date, size: Int) {
        self.modified = modified
        self.size = size
    }
}

/// A response letter's workspace folder (docs/FILE_FORMAT.md):
///
///     letter.yml            title, manuscript, numbering and export settings
///     decision-letter.txt   the decision letter as pasted; never rewritten
///     sections.yml          the sections and the order of their comments
///     comments/<key>.yml    one file per comment
///     variables.yml         Variables
///     opening.md, closing.md  text before and after the table (markup)
public enum Workspace {
    public static let formatVersion = 1
    public static let letterFile = "letter.yml"
    public static let decisionFile = "decision-letter.txt"
    public static let sectionsFile = "sections.yml"
    public static let variablesFile = "variables.yml"
    public static let openingFile = "opening.md"
    public static let closingFile = "closing.md"
    public static let commentsFolder = "comments"

    public static func isWorkspace(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(letterFile).path)
    }

    /// The title and manuscript ID of a workspace, read cheaply for lists of
    /// recent letters; nil if the folder isn't a readable workspace.
    public static func summary(_ url: URL) -> (title: String, manuscript: String)? {
        guard let node = try? readYAML(url, letterFile, required: true) else { return nil }
        let s = decodeSettings(node)
        return (s.title, s.manuscript)
    }

    /// True if the folder has nothing in it but hidden files.
    public static func isEmptyFolder(_ url: URL) -> Bool {
        let items = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return items.allSatisfy { $0.hasPrefix(".") }
    }

    static func normalise(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    /// Starts a workspace in `url` (created if needed).
    public static func create(at url: URL, decisionLetter: String, settings: LetterSettings) throws -> ResponseLetter {
        let fm = FileManager.default
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        try fm.createDirectory(at: url.appendingPathComponent(commentsFolder), withIntermediateDirectories: true)
        let letter = ResponseLetter(settings: settings, decisionLetter: normalise(decisionLetter))
        try write(Data(letter.decisionLetter.utf8), to: url.appendingPathComponent(decisionFile))
        try save(letter, parts: [.settings, .sections, .variables, .opening, .closing], to: url)
        return letter
    }

    // MARK: - Loading

    public static func load(_ url: URL) throws -> LoadedWorkspace {
        var notes: [String] = []
        var repaired = Set<WorkspacePart>()

        let settingsNode = try readYAML(url, letterFile, required: true)
        if let format = settingsNode["format"]?.int, format > formatVersion {
            throw WorkspaceError(file: letterFile,
                                 message: "written by a newer version of the app (format \(format)); update the app to open it")
        }
        let settings = decodeSettings(settingsNode)

        let decision = try readText(url, decisionFile) ?? ""
        let sectionsNode = try readYAML(url, sectionsFile, required: false)
        var sections = try decodeSections(sectionsNode)
        let variables = try decodeVariables(try readYAML(url, variablesFile, required: false))
        let opening = try readText(url, openingFile).map(trimFinalNewline) ?? ""
        let closing = try readText(url, closingFile).map(trimFinalNewline) ?? ""

        var comments: [String: Comment] = [:]
        let folder = url.appendingPathComponent(commentsFolder)
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasSuffix(".yml") && !$0.hasPrefix(".") }.sorted()
        for file in files {
            let key = String(file.dropLast(4))
            let node = try readYAML(folder, file, required: true, display: "\(commentsFolder)/\(file)")
            comments[key] = decodeComment(key: key, node)
        }

        // Comments listed but missing, and comment files not listed.
        var listed = Set<String>()
        for i in sections.indices {
            let before = sections[i].commentKeys
            sections[i].commentKeys = before.filter { comments[$0] != nil && listed.insert($0).inserted }
            if sections[i].commentKeys.count != before.count {
                notes.append("\(sectionsFile) listed comments in \(sections[i].title) that have no file (or appear twice); they were dropped.")
                repaired.insert(.sections)
            }
        }
        let orphans = comments.keys.filter { !listed.contains($0) }.sorted()
        if !orphans.isEmpty {
            let taken = Set(sections.map(\.key))
            let key = Keys.make("s") { taken.contains($0) }
            sections.append(LetterSection(key: key, role: .other, title: "Unassigned", prefix: "U", commentKeys: orphans))
            notes.append("\(orphans.count) comment file(s) weren't listed in \(sectionsFile); they are in a new section, Unassigned.")
            repaired.insert(.sections)
        }

        let letter = ResponseLetter(settings: settings, decisionLetter: decision, sections: sections, comments: comments,
                                    variables: variables, opening: opening, closing: closing)
        return LoadedWorkspace(letter: letter, notes: notes, repairedParts: repaired)
    }

    static func trimFinalNewline(_ s: String) -> String {
        var t = normalise(s)
        if t.hasSuffix("\n") { t.removeLast() }
        return t
    }

    static func readText(_ folder: URL, _ name: String) throws -> String? {
        let url = folder.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            guard let s = String(data: data, encoding: .utf8) else {
                throw WorkspaceError(file: name, message: "is not UTF-8 text")
            }
            return normalise(s)
        } catch let e as WorkspaceError {
            throw e
        } catch {
            throw WorkspaceError(file: name, message: error.localizedDescription)
        }
    }

    static func readYAML(_ folder: URL, _ name: String, required: Bool, display: String? = nil) throws -> YAMLNode {
        guard let text = try readText(folder, name) else {
            if required { throw WorkspaceError(file: display ?? name, message: "is missing") }
            return .null
        }
        do {
            return try YAML.parse(text)
        } catch let e as YAMLError {
            throw WorkspaceError(file: display ?? name, message: e.description)
        }
    }

    // MARK: - Saving

    /// Writes the given parts. A comment part whose comment no longer
    /// exists deletes its file.
    public static func save(_ letter: ResponseLetter, parts: Set<WorkspacePart>, to url: URL) throws {
        for part in parts {
            switch part {
            case .settings:
                try writeYAML(encodeSettings(letter.settings), to: url.appendingPathComponent(letterFile))
            case .sections:
                try writeYAML(encodeSections(letter.sections), to: url.appendingPathComponent(sectionsFile))
            case .variables:
                try writeYAML(encodeVariables(letter.variables), to: url.appendingPathComponent(variablesFile))
            case .opening:
                try write(Data((letter.opening.isEmpty ? "" : letter.opening + "\n").utf8),
                          to: url.appendingPathComponent(openingFile))
            case .closing:
                try write(Data((letter.closing.isEmpty ? "" : letter.closing + "\n").utf8),
                          to: url.appendingPathComponent(closingFile))
            case .comment(let key):
                let folder = url.appendingPathComponent(commentsFolder)
                let file = folder.appendingPathComponent(key + ".yml")
                if let c = letter.comments[key] {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try writeYAML(encodeComment(c), to: file)
                } else if FileManager.default.fileExists(atPath: file.path) {
                    try FileManager.default.removeItem(at: file)
                }
            }
        }
    }

    public static func allParts(of letter: ResponseLetter) -> Set<WorkspacePart> {
        var parts: Set<WorkspacePart> = [.settings, .sections, .variables, .opening, .closing]
        for key in letter.comments.keys { parts.insert(.comment(key)) }
        return parts
    }

    /// Long texts and lists are always written one line per line or item,
    /// so files read well and diffs stay small.
    static let blockKeys: Set<String> = ["text", "response", "ideas", "comments"]

    static func writeYAML(_ node: YAMLNode, to url: URL) throws {
        try write(Data(YAML.emit(node, blockKeys: blockKeys).utf8), to: url)
    }

    static func write(_ data: Data, to url: URL) throws {
        // Skip identical content, so Git and file watchers see no change.
        if let existing = try? Data(contentsOf: url), existing == data { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw WorkspaceError(file: url.lastPathComponent, message: error.localizedDescription)
        }
    }

    // MARK: - Change detection

    public static func stamps(_ url: URL) -> [String: FileStamp] {
        var result: [String: FileStamp] = [:]
        let fm = FileManager.default
        var names = [letterFile, decisionFile, sectionsFile, variablesFile, openingFile, closingFile]
        let folder = url.appendingPathComponent(commentsFolder)
        names += ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".yml") }
            .map { "\(commentsFolder)/\($0)" }
        for name in names {
            let path = url.appendingPathComponent(name).path
            guard let attrs = try? fm.attributesOfItem(atPath: path) else { continue }
            let date = attrs[.modificationDate] as? Date ?? .distantPast
            let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
            result[name] = FileStamp(modified: date, size: size)
        }
        return result
    }

    // MARK: - Encoding

    static func numberText(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(d)
    }

    static func encodeSettings(_ s: LetterSettings) -> YAMLNode {
        .map([
            ("format", .num(formatVersion)),
            ("app", .str("QDVC Response Letter")),
            ("title", .str(s.title)),
            ("manuscript", .str(s.manuscript)),
            ("numbering", .map([("separator", .str(s.separator)), ("digits", .num(s.digits))])),
            ("export", .map([
                ("font", .str(s.fontName)),
                ("size", .str(numberText(s.fontSize))),
                ("quotes", .str(s.quoteStyle.rawValue)),
            ])),
        ])
    }

    static func decodeSettings(_ n: YAMLNode) -> LetterSettings {
        var s = LetterSettings()
        if let v = n["title"]?.string { s.title = v }
        if let v = n["manuscript"]?.string { s.manuscript = v }
        if let num = n["numbering"] {
            if let v = num["separator"] { s.separator = v.string ?? "" }
            if let v = num["digits"]?.int { s.digits = max(1, min(v, 6)) }
        }
        if let ex = n["export"] {
            if let v = ex["font"]?.string, !v.isEmpty { s.fontName = v }
            if let v = ex["size"]?.double, v >= 6, v <= 36 { s.fontSize = v }
            if let v = ex["quotes"]?.string, let q = QuoteStyle(rawValue: v) { s.quoteStyle = q }
        }
        return s
    }

    static func encodeSections(_ sections: [LetterSection]) -> YAMLNode {
        .map([("sections", .sequence(sections.map { s in
            var pairs: [(String, YAMLNode)] = [("key", .str(s.key)), ("role", .str(s.role.rawValue))]
            if let n = s.number { pairs.append(("number", .num(n))) }
            pairs.append(("title", .str(s.title)))
            pairs.append(("prefix", .str(s.prefix)))
            if let a = s.anchor { pairs.append(("anchor", .num(a))) }
            pairs.append(("comments", .list(s.commentKeys)))
            return .map(pairs)
        }))])
    }

    static func decodeSections(_ n: YAMLNode) throws -> [LetterSection] {
        var seen = Set<String>()
        return try (n["sections"]?.items ?? []).enumerated().map { i, item in
            guard let key = item["key"]?.string, !key.isEmpty, seen.insert(key).inserted else {
                throw WorkspaceError(file: sectionsFile, message: "section \(i + 1) has no key, or a key used twice")
            }
            let role = item["role"]?.string.flatMap(SectionRole.init(rawValue:)) ?? .other
            return LetterSection(key: key, role: role, number: item["number"]?.int, title: item["title"]?.string,
                           prefix: item["prefix"]?.string, anchor: item["anchor"]?.int,
                           commentKeys: item["comments"]?.strings ?? [])
        }
    }

    static func encodeVariables(_ variables: [Variable]) -> YAMLNode {
        .map([("variables", .sequence(variables.map { v in
            .map([("key", .str(v.key)), ("name", .str(v.name)), ("value", .str(v.value))])
        }))])
    }

    static func decodeVariables(_ n: YAMLNode) throws -> [Variable] {
        var seen = Set<String>()
        return try (n["variables"]?.items ?? []).enumerated().map { i, item in
            guard let key = item["key"]?.string, !key.isEmpty, seen.insert(key).inserted else {
                throw WorkspaceError(file: variablesFile, message: "variable \(i + 1) has no key, or a key used twice")
            }
            return Variable(key: key, name: item["name"]?.string ?? key, value: item["value"]?.string ?? "")
        }
    }

    static func encodeComment(_ c: Comment) -> YAMLNode {
        .map([
            ("triage", .str(c.triage.rawValue)),
            ("status", .str(c.status.rawValue)),
            ("source", .list(c.source.map(\.text))),
            ("related", .list(c.related)),
            ("text", .str(c.text)),
            ("ideas", .list(c.ideas)),
            ("response", .str(c.response)),
        ])
    }

    static func decodeComment(key: String, _ n: YAMLNode) -> Comment {
        var text = n["text"]?.string ?? ""
        if text.hasSuffix("\n") { text.removeLast() }
        var response = n["response"]?.string ?? ""
        while response.hasSuffix("\n") { response.removeLast() }
        return Comment(
            key: key,
            text: normalise(text),
            ideas: n["ideas"]?.strings ?? [],
            response: normalise(response),
            triage: n["triage"]?.string.flatMap(Triage.init(rawValue:)) ?? .none,
            status: n["status"]?.string.flatMap(Status.init(lenient:)) ?? .todo,
            related: n["related"]?.strings ?? [],
            source: (n["source"]?.strings ?? []).compactMap(SourceRange.init(text:))
        )
    }
}

extension ResponseLetter {
    /// The parts that differ from `old`.
    public func changedParts(since old: ResponseLetter) -> Set<WorkspacePart> {
        var parts = Set<WorkspacePart>()
        if settings != old.settings { parts.insert(.settings) }
        if sections != old.sections { parts.insert(.sections) }
        if variables != old.variables { parts.insert(.variables) }
        if opening != old.opening { parts.insert(.opening) }
        if closing != old.closing { parts.insert(.closing) }
        for key in Set(comments.keys).union(old.comments.keys) where comments[key] != old.comments[key] {
            parts.insert(.comment(key))
        }
        return parts
    }
}
