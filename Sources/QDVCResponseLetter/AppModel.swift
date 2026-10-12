import AppKit
import Observation
import ResponseCore
import SwiftUI
import UniformTypeIdentifiers

enum SidebarItem: Hashable {
    case overview
    case decisionLetter
    case triageEditor
    case responseEditor
    case openingClosing
    case variables
    case issues
    case traceability
}

/// A section being created or edited.
struct SectionDraft: Equatable {
    var key: String?
    var role: SectionRole
    var number: Int
    var title: String
    var prefix: String
    var anchor: Int?
}

enum SheetKind: Identifiable {
    case newLetter(URL?)
    case letterSettings
    case section(SectionDraft)
    case splitResolution(SplitResult)
    case exportLetter
    case newVariable(String)
    case letterRevision(LetterRevision)

    var id: String {
        switch self {
        case .newLetter: return "new"
        case .letterSettings: return "settings"
        case .section(let d): return "section-\(d.key ?? "new")"
        case .splitResolution(let r): return "split-\(r.secondKey)"
        case .exportLetter: return "export"
        case .newVariable: return "variable"
        case .letterRevision: return "letter-revision"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    private(set) var workspaceURL: URL?
    private(set) var letter = ResponseLetter()

    var selection: SidebarItem? = .overview {
        didSet { if oldValue != selection { flushSaves() } }
    }
    /// Selected rows in Overview and the Triage Editor (shared).
    var tableSelection: Set<String> = []
    /// The comment whose row in the Response Editor was last edited or
    /// clicked.
    var focusedCommentKey: String?
    /// The selected card in Traceability.
    var traceSelection: String?
    /// A comment for the Response Editor to scroll to.
    var scrollTarget: String?
    var scrollRevision = 0
    var searchText = ""
    var triageFilter: Set<Triage> = []
    var statusFilter: Set<Status> = []
    var collapsedSections: Set<String> = []
    var showInspector = true
    var sheet: SheetKind?
    var errorMessage: String?
    var notice: Notice?

    /// Insertion point in the comment text editor (UTF-16), for Split.
    var commentCursor: (key: String, offset: Int)?
    /// Selection in the decision letter (UTF-16).
    var letterSelection = NSRange(location: 0, length: 0)
    /// The section the next marked comment goes into.
    var letterSectionChoice: String?
    /// Editing the decision letter: the text so far, and every edit made
    /// to the saved letter to get there.
    var isEditingLetter = false
    var letterDraft = ""
    var letterEdits: [LetterEdit] = []
    /// A comment to scroll to in the decision letter.
    var revealInLetter: String?
    var revealRevision = 0

    var editorFontSize: Double {
        didSet { UserDefaults.standard.set(editorFontSize, forKey: Prefs.editorFontSize) }
    }
    var triageColoursInLetter: Bool {
        didSet { UserDefaults.standard.set(triageColoursInLetter, forKey: Prefs.triageColours) }
    }
    /// Show the welcome window at launch; otherwise reopen the last letter.
    var showWelcomeAtLaunch: Bool {
        didSet { UserDefaults.standard.set(showWelcomeAtLaunch, forKey: Prefs.showWelcome) }
    }
    /// Set when the user asks for the welcome window (Window menu), so it
    /// stays up even though a letter is open.
    @ObservationIgnored var welcomeRequested = false
    @ObservationIgnored private var didStartUp = false
    private(set) var recentWorkspaces: [URL] = []

    @ObservationIgnored weak var undoManager: UndoManager?
    /// The response editor last focused (for Insert Variable and friends).
    @ObservationIgnored weak var activeEditor: EditorTextView?
    /// The editor a new Variable from the selection goes into.
    @ObservationIgnored weak var variableTarget: EditorTextView?
    @ObservationIgnored private var dirty = Set<WorkspacePart>()
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var stamps: [String: FileStamp] = [:]

    enum Prefs {
        static let editorFontSize = "editorFontSize"
        static let triageColours = "triageColoursInLetter"
        static let recent = "recentWorkspaces"
        static let last = "lastWorkspace"
        static let showWelcome = "showWelcomeAtLaunch"
    }

    init() {
        let d = UserDefaults.standard
        editorFontSize = d.object(forKey: Prefs.editorFontSize) as? Double ?? 13
        triageColoursInLetter = d.object(forKey: Prefs.triageColours) as? Bool ?? true
        showWelcomeAtLaunch = d.object(forKey: Prefs.showWelcome) as? Bool ?? true
        recentWorkspaces = (d.stringArray(forKey: Prefs.recent) ?? []).map { URL(fileURLWithPath: $0) }
    }

    var isOpen: Bool { workspaceURL != nil }

    var windowTitle: String {
        guard let url = workspaceURL else { return "QDVC Response Letter" }
        return url.lastPathComponent
    }

    // MARK: - Opening and creating

    /// At launch: the welcome window offers the recent letters, unless
    /// the user has turned it off, in which case the last letter reopens.
    func startUp() {
        guard !didStartUp else { return }
        didStartUp = true
        guard !showWelcomeAtLaunch, workspaceURL == nil,
              let path = UserDefaults.standard.string(forKey: Prefs.last) else { return }
        let url = URL(fileURLWithPath: path)
        if Workspace.isWorkspace(url) { open(url) }
    }

    func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Open"
        panel.message = "Choose a response letter folder."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if Workspace.isWorkspace(url) {
            open(url)
        } else if Workspace.isEmptyFolder(url) {
            sheet = .newLetter(url)
        } else {
            errorMessage = "“\(url.lastPathComponent)” isn't a response letter folder (it has no letter.yml). Choose an empty folder to start a new response letter there."
        }
    }

    func open(_ url: URL) {
        flushSaves()
        do {
            let loaded = try Workspace.load(url)
            install(loaded.letter, at: url)
            if !loaded.repairedParts.isEmpty {
                dirty.formUnion(loaded.repairedParts)
                flushSaves()
            }
            if !loaded.notes.isEmpty { show(loaded.notes.joined(separator: " "), warning: true) }
        } catch {
            errorMessage = "Couldn't open “\(url.lastPathComponent)”. \(error.localizedDescription)"
        }
    }

    /// Asks where to create the folder (unless given), then creates it.
    func createLetter(in folder: URL?, title: String, manuscript: String, decisionLetter: String) -> Bool {
        var target = folder
        if target == nil {
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.prompt = "Create"
            panel.message = "Choose where to keep this response letter. It is a folder of plain files, easy to keep in Git."
            panel.nameFieldLabel = "Folder name:"
            let base = manuscript.isEmpty ? "Response letter" : "\(manuscript) response letter"
            panel.nameFieldStringValue = base.replacingOccurrences(of: "/", with: "-")
            guard panel.runModal() == .OK, let chosen = panel.url else { return false }
            if FileManager.default.fileExists(atPath: chosen.path), !Workspace.isEmptyFolder(chosen) {
                errorMessage = "“\(chosen.lastPathComponent)” already exists and isn't empty."
                return false
            }
            target = chosen
        }
        guard let url = target else { return false }
        do {
            var settings = LetterSettings()
            if !title.isEmpty { settings.title = title }
            settings.manuscript = manuscript
            let letter = try Workspace.create(at: url, decisionLetter: decisionLetter, settings: settings)
            flushSaves()
            install(letter, at: url)
            selection = .decisionLetter
            show("Next: select a heading such as “Reviewer 1” and choose New Section Here (⇧⌘K), then select each comment and choose Mark as Comment (⌘K).")
            return true
        } catch {
            errorMessage = "Couldn't create the response letter. \(error.localizedDescription)"
            return false
        }
    }

    private func install(_ letter: ResponseLetter, at url: URL) {
        self.letter = letter
        workspaceURL = url
        dirty = []
        undoManager?.removeAllActions()
        stamps = Workspace.stamps(url)
        collapsedSections = []
        tableSelection = []
        focusedCommentKey = nil
        traceSelection = nil
        isEditingLetter = false
        letterDraft = ""
        letterEdits = []
        selection = letter.sections.isEmpty ? .decisionLetter : .overview
        addRecent(url)
        UserDefaults.standard.set(url.path, forKey: Prefs.last)
    }

    func closeWorkspace() {
        flushSaves()
        isEditingLetter = false
        workspaceURL = nil
        letter = ResponseLetter()
        undoManager?.removeAllActions()
        UserDefaults.standard.removeObject(forKey: Prefs.last)
    }

    private func addRecent(_ url: URL) {
        var list = recentWorkspaces.filter { $0.standardizedFileURL != url.standardizedFileURL }
        list.insert(url, at: 0)
        recentWorkspaces = Array(list.prefix(10))
        UserDefaults.standard.set(recentWorkspaces.map(\.path), forKey: Prefs.recent)
    }

    func removeRecent(_ url: URL) {
        recentWorkspaces.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        UserDefaults.standard.set(recentWorkspaces.map(\.path), forKey: Prefs.recent)
    }

    func clearRecent() {
        recentWorkspaces = []
        UserDefaults.standard.removeObject(forKey: Prefs.recent)
    }

    func revealInFinder() {
        guard let url = workspaceURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Saving

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.flushSaves()
        }
    }

    func flushSaves() {
        saveTask?.cancel()
        saveTask = nil
        guard let url = workspaceURL, !dirty.isEmpty else { return }
        let parts = dirty
        dirty = []
        do {
            try Workspace.save(letter, parts: parts, to: url)
            stamps = Workspace.stamps(url)
        } catch {
            dirty.formUnion(parts)
            errorMessage = "Couldn't save. \(error.localizedDescription)"
        }
    }

    /// Re-reads the workspace if its files changed outside the app (a Git
    /// pull, another editor).
    func checkForOutsideChanges(force: Bool = false) {
        // Not while the letter is being edited: the edits are relative to it.
        guard let url = workspaceURL, !isEditingLetter else { return }
        flushSaves()
        let now = Workspace.stamps(url)
        guard force || now != stamps else { return }
        do {
            let loaded = try Workspace.load(url)
            letter = loaded.letter
            stamps = now
            undoManager?.removeAllActions()
            validateSelection()
            if !force { show("Reloaded changes made outside the app.") }
        } catch {
            stamps = now
            errorMessage = "Couldn't reload. \(error.localizedDescription)"
        }
    }

    // MARK: - Changing the letter

    /// Applies an undoable change. Errors are shown, and change nothing.
    @discardableResult
    func perform<T>(_ name: String, _ change: (inout ResponseLetter) throws -> T) -> T? {
        let before = letter
        var copy = letter
        do {
            let result = try change(&copy)
            commit(copy, from: before, undoName: name)
            return result
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Typing in an editor: saved, but undone in the editor itself rather
    /// than through Edit › Undo.
    func updateText(_ change: (inout ResponseLetter) -> Void) {
        let before = letter
        var copy = letter
        change(&copy)
        commit(copy, from: before, undoName: nil)
    }

    private func commit(_ new: ResponseLetter, from before: ResponseLetter, undoName: String?) {
        guard new != before else { return }
        letter = new
        dirty.formUnion(new.changedParts(since: before))
        scheduleSave()
        if let undoName { registerUndo(undoName, before: before, after: new) }
    }

    private func registerUndo(_ name: String, before: ResponseLetter, after: ResponseLetter) {
        guard let um = undoManager else { return }
        um.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                let now = target.letter
                var reverted = now
                reverted.revert(changesFrom: before, to: after)
                target.commit(reverted, from: now, undoName: nil)
                target.registerUndo(name, before: after, after: before)
                target.validateSelection()
            }
        }
        um.setActionName(name)
    }

    private func validateSelection() {
        tableSelection = tableSelection.filter { letter.comments[$0] != nil }
        if let k = focusedCommentKey, letter.comments[k] == nil { focusedCommentKey = nil }
        if let k = traceSelection, letter.comments[k] == nil { traceSelection = nil }
    }

    func show(_ text: String, warning: Bool = false) {
        notice = Notice(text: text, isWarning: warning)
        noticeTask?.cancel()
        noticeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(warning ? 14 : 8))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    // MARK: - Lookups

    var ids: [String: String] { letter.idMap() }

    func id(_ key: String) -> String { letter.displayID(key) ?? "?" }

    var isFiltering: Bool { !searchText.isEmpty || !triageFilter.isEmpty || !statusFilter.isEmpty }

    func matches(_ c: Comment, ids: [String: String]) -> Bool {
        if !triageFilter.isEmpty && !triageFilter.contains(c.triage) { return false }
        if !statusFilter.isEmpty && !statusFilter.contains(c.status) { return false }
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        if (ids[c.key] ?? "").localizedCaseInsensitiveContains(q) { return true }
        if c.text.localizedCaseInsensitiveContains(q) { return true }
        if c.ideas.contains(where: { $0.localizedCaseInsensitiveContains(q) }) { return true }
        let response = c.responseText.plainText { self.letter.tokenDisplay($0, ids: ids) }
        return response.localizedCaseInsensitiveContains(q)
    }

    func visibleKeys(in section: LetterSection, ids: [String: String]) -> [String] {
        guard isFiltering else { return section.commentKeys }
        return section.commentKeys.filter { key in letter.comments[key].map { matches($0, ids: ids) } ?? false }
    }

    /// The one comment the current page is about: the selected row
    /// (Overview, Triage Editor), the row being edited (Response Editor) or
    /// the selected card (Traceability).
    var selectedCommentKey: String? {
        switch selection {
        case .overview?, .triageEditor?: return tableSelection.count == 1 ? tableSelection.first : nil
        case .responseEditor?: return focusedCommentKey
        case .traceability?: return traceSelection
        default: return nil
        }
    }

    /// The comments that menu commands act on, in letter order.
    var targetKeys: [String] {
        switch selection {
        case .overview?, .triageEditor?: return letter.orderedCommentKeys.filter { tableSelection.contains($0) }
        default: return selectedCommentKey.map { [$0] } ?? []
        }
    }

    /// Opens a comment in the Response Editor, scrolled to its row.
    func openComment(_ key: String) {
        guard letter.comments[key] != nil else { return }
        selection = .responseEditor
        focusedCommentKey = key
        scrollTarget = key
        scrollRevision += 1
    }

    /// Selects a comment in the Triage Editor.
    func openInTriage(_ key: String) {
        guard letter.comments[key] != nil else { return }
        selection = .triageEditor
        tableSelection = [key]
    }

    /// Shows a comment on the current page if it lists comments, otherwise
    /// in the Response Editor.
    func reveal(_ key: String) {
        switch selection {
        case .overview?, .triageEditor?: tableSelection = [key]
        case .traceability?: traceSelection = key
        case .responseEditor?:
            focusedCommentKey = key
            scrollTarget = key
            scrollRevision += 1
        default: openComment(key)
        }
    }

    /// Called when an editor in a Response Editor row gets the focus.
    func focusRow(_ key: String) {
        guard focusedCommentKey != key else { return }
        // Not during a view update: focus can change while SwiftUI is
        // laying out.
        DispatchQueue.main.async { [weak self] in self?.focusedCommentKey = key }
    }

    func step(_ offset: Int) {
        let keys = letter.orderedCommentKeys
        guard !keys.isEmpty else { return }
        var next = offset > 0 ? keys[0] : keys[keys.count - 1]
        if let current = selectedCommentKey, let i = keys.firstIndex(of: current) {
            let j = i + offset
            guard keys.indices.contains(j) else { return }
            next = keys[j]
        }
        reveal(next)
    }

    var issues: [Issue] { letter.issues() }

    var blockingIssues: [Issue] { issues.filter(\.kind.isBlocking) }

    func issues(for key: String) -> [Issue] { issues.filter { $0.commentKey == key } }

    /// What a pill says, and how it looks.
    func look(_ token: Token) -> TokenLook {
        switch token {
        case .variable(let key):
            guard let v = letter.variable(key) else {
                return TokenLook(text: "deleted Variable", state: .broken, help: "This Variable has been deleted.")
            }
            let empty = v.value.trimmingCharacters(in: .whitespaces).isEmpty
            return TokenLook(text: empty ? v.name : v.value, state: empty ? .broken : .variable,
                             help: "Variable “\(v.name)”. Double-click to edit it in Variables.")
        case .ref(let keys):
            let map = ids
            if keys.count == 1 {
                guard let id = map[keys[0]] else {
                    return TokenLook(text: "deleted comment", state: .broken,
                                     help: "This cross-reference points to a comment that has been deleted.")
                }
                return TokenLook(text: id, state: .reference, help: "Cross-reference to \(id). Double-click to open it.")
            }
            let names = keys.map { map[$0] ?? "?" }
            return TokenLook(text: names.joined(separator: " / ") + " ?", state: .pending,
                             help: "This cross-reference pointed to a comment that was split. Choose which part it means in Issues.")
        }
    }

    /// Changes when anything a pill shows changes.
    var tokenSignature: Int {
        var h = Hasher()
        h.combine(letter.variables)
        for s in letter.sections {
            h.combine(s.prefix)
            h.combine(s.commentKeys)
        }
        h.combine(letter.settings.separator)
        h.combine(letter.settings.digits)
        return h.finalize()
    }

    func openToken(_ token: Token) {
        switch token {
        case .variable: selection = .variables
        case .ref(let keys): if let k = keys.first, keys.count == 1 { openComment(k) } else { selection = .issues }
        }
    }

    // MARK: - Text from the editors

    func setCommentText(_ key: String, _ text: String) {
        updateText { $0.comments[key]?.text = text }
    }

    func setIdeas(_ key: String, _ text: String) {
        let ideas = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        // Keep a trailing empty line while typing; it is dropped on reload.
        updateText { $0.comments[key]?.ideas = ideas.last == "" ? Array(ideas.dropLast()) : ideas }
    }

    func setResponse(_ key: String, _ markup: String) {
        updateText { letter in
            letter.comments[key]?.response = markup
            // Writing a response moves a comment along from "to do".
            if letter.comments[key]?.status == .todo, !markup.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                letter.comments[key]?.status = .drafted
            }
        }
    }

    func setOpening(_ markup: String) { updateText { $0.opening = markup } }
    func setClosing(_ markup: String) { updateText { $0.closing = markup } }

    func setVariable(_ key: String, name: String? = nil, value: String? = nil) {
        updateText { letter in
            guard var v = letter.variable(key) else { return }
            if let name { v.name = name }
            if let value { v.value = value }
            letter.updateVariable(v)
        }
    }

    func updateSettings(_ change: (inout LetterSettings) -> Void) {
        perform("Change Letter Settings") { change(&$0.settings) }
    }

    // MARK: - Triage and status

    func setTriage(_ t: Triage, for keys: [String]? = nil) {
        let keys = keys ?? targetKeys
        guard !keys.isEmpty else { return }
        perform("Set Triage") { letter in for k in keys { letter.comments[k]?.triage = t } }
    }

    func setStatus(_ s: Status, for keys: [String]? = nil) {
        let keys = keys ?? targetKeys
        guard !keys.isEmpty else { return }
        perform("Set Status") { letter in for k in keys { letter.comments[k]?.status = s } }
    }

    // MARK: - Sections

    func newSectionDraft(anchor: Int?, hint: String) -> SectionDraft {
        let h = hint.lowercased()
        var role = SectionRole.reviewer
        let table: [(String, SectionRole)] = [
            ("senior editor", .seniorEditor), ("associate editor", .associateEditor),
            ("special issue", .specialIssueEditor), ("department editor", .departmentEditor),
            ("track chair", .trackChair), ("editor", .seniorEditor), ("reviewer", .reviewer),
            ("referee", .reviewer),
        ]
        if let match = table.first(where: { h.contains($0.0) }) { role = match.1 }
        var number = letter.nextReviewerNumber
        if role == .reviewer, let n = hint.split(whereSeparator: { !$0.isNumber }).compactMap({ Int($0) }).first {
            number = n
        }
        return SectionDraft(key: nil, role: role, number: number, title: role.defaultTitle(number: number),
                            prefix: role.defaultPrefix(number: number), anchor: anchor)
    }

    func editSection(_ key: String) {
        guard let s = letter.sections.first(where: { $0.key == key }) else { return }
        sheet = .section(SectionDraft(key: s.key, role: s.role, number: s.number ?? 1, title: s.title,
                                      prefix: s.prefix, anchor: s.anchor))
    }

    func saveSection(_ d: SectionDraft) {
        if let key = d.key, var s = letter.sections.first(where: { $0.key == key }) {
            s.role = d.role
            s.number = d.role.isNumbered ? d.number : nil
            s.title = d.title
            s.prefix = d.prefix
            perform("Edit Section") { $0.updateSection(s) }
        } else {
            let key = perform("New Section") {
                $0.addSection(role: d.role, number: d.role.isNumbered ? d.number : nil, title: d.title,
                              prefix: d.prefix, anchor: d.anchor)
            }
            if let key { letterSectionChoice = key }
        }
    }

    func deleteSection(_ key: String) {
        guard let s = letter.sections.first(where: { $0.key == key }) else { return }
        if !s.commentKeys.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Delete “\(s.title)” and its \(s.commentKeys.count) comment(s)?"
            alert.informativeText = "Their responses are deleted too. You can undo this."
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            alert.buttons[0].hasDestructiveAction = true
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        perform("Delete Section") { $0.deleteSection(key) }
        validateSelection()
    }

    func moveSection(_ key: String, by delta: Int) {
        perform("Move Section") { $0.moveSection(key, by: delta) }
    }

    // MARK: - Comments

    /// The section a selection in the decision letter would go into.
    func inferredSection(for range: NSRange) -> String? {
        letter.sectionKey(forOffset: range.location) ?? letter.sections.last?.key
    }

    func markComment() {
        let range = letterSelection
        guard range.length > 0 else { return }
        guard let section = letterSectionChoice.flatMap({ k in letter.sections.first { $0.key == k }?.key })
            ?? inferredSection(for: range) else {
            errorMessage = EditError.noSection.localizedDescription
            return
        }
        let key = perform("Mark as Comment") {
            try $0.markComment(SourceRange(location: range.location, length: range.length), inSection: section)
        }
        if let key {
            letterSelection = NSRange(location: NSMaxRange(range), length: 0)
            show("Marked \(id(key)).")
        }
    }

    func newComment() {
        let after = selectedCommentKey
        let section = after.flatMap { letter.section(ofComment: $0)?.key } ?? letter.sections.last?.key
        guard let section else {
            errorMessage = EditError.noSection.localizedDescription
            return
        }
        if let key = perform("New Comment", { $0.addComment(inSection: section, after: after) }), let key {
            reveal(key)
        }
    }

    func newComment(inSection section: String) {
        if let key = perform("New Comment", { $0.addComment(inSection: section) }), let key { reveal(key) }
    }

    func deleteComments(_ keys: [String]? = nil) {
        let keys = keys ?? targetKeys
        guard !keys.isEmpty else { return }
        let refs = keys.reduce(0) { $0 + letter.referenceCount(to: $1) }
        let withResponses = keys.filter { !(letter.comments[$0]?.response.isEmpty ?? true) }.count
        if refs > 0 || withResponses > 0 {
            let alert = NSAlert()
            alert.messageText = keys.count == 1 ? "Delete \(id(keys[0]))?" : "Delete \(keys.count) comments?"
            var info: [String] = []
            if withResponses > 0 { info.append("Responses will be deleted.") }
            if refs > 0 { info.append("\(refs) cross-reference(s) point here; they will be flagged in Issues.") }
            alert.informativeText = (info + ["You can undo this."]).joined(separator: " ")
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            alert.buttons[0].hasDestructiveAction = true
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let before = ids
        let next = keys.last.flatMap { letter.neighbour(of: $0, offset: 1) }
        perform(keys.count == 1 ? "Delete Comment" : "Delete Comments") { letter in
            for k in keys { letter.deleteComment(k) }
        }
        tableSelection.subtract(keys)
        if let k = focusedCommentKey, keys.contains(k) { focusedCommentKey = next }
        if let k = traceSelection, keys.contains(k) { traceSelection = nil }
        reportRenumbering(from: before)
    }

    func moveComment(_ key: String, by delta: Int) {
        guard let si = letter.sectionIndex(ofComment: key),
              let i = letter.sections[si].commentKeys.firstIndex(of: key) else { return }
        let j = i + delta
        guard letter.sections[si].commentKeys.indices.contains(j) else { return }
        let before = ids
        let section = letter.sections[si].key
        perform("Move Comment") { $0.moveComment(key, toSection: section, at: delta > 0 ? j + 1 : j) }
        reportRenumbering(from: before)
    }

    func moveComment(_ key: String, toSection section: String) {
        guard let s = letter.sections.first(where: { $0.key == section }) else { return }
        let before = ids
        perform("Move Comment") { $0.moveComment(key, toSection: section, at: s.commentKeys.count) }
        reportRenumbering(from: before)
    }

    func moveComments(inSection section: String, from: IndexSet, to: Int) {
        let before = ids
        perform("Move Comment") { $0.moveComments(inSection: section, fromOffsets: from, toOffset: to) }
        reportRenumbering(from: before)
    }

    var canSplit: Bool {
        guard let key = selectedCommentKey, let cursor = commentCursor, cursor.key == key,
              let text = letter.comments[key]?.text else { return false }
        return cursor.offset > 0 && cursor.offset < text.utf16.count
    }

    func splitAtCursor() {
        guard let key = selectedCommentKey else { return }
        guard let cursor = commentCursor, cursor.key == key else {
            errorMessage = EditError.splitPointAtEdge.localizedDescription
            return
        }
        guard let result = perform("Split Comment", { try $0.splitComment(key, atUTF16: cursor.offset) }) else { return }
        commentCursor = nil
        let a = id(result.firstKey), b = id(result.secondKey)
        if !result.pending.isEmpty || !result.relatedKeys.isEmpty {
            sheet = .splitResolution(result)
        } else {
            show(renumberingText("Split into \(a) and \(b).", result.renumbered))
        }
    }

    func canMergeWithNext(_ key: String?) -> Bool {
        guard let key else { return false }
        return letter.neighbour(of: key, offset: 1) != nil
    }

    func mergeWithNext(_ key: String? = nil) {
        guard let key = key ?? selectedCommentKey, let next = letter.neighbour(of: key, offset: 1) else { return }
        let a = id(key), b = id(next)
        guard let result = perform("Merge Comments", { try $0.mergeComment(key, withNext: next) }) else { return }
        reveal(result.key)
        show(renumberingText("Merged \(b) into \(a). Cross-references to \(b) now point to \(a).", result.renumbered))
    }

    func renumberingText(_ lead: String, _ changes: [Renumbering]) -> String {
        guard !changes.isEmpty else { return lead }
        let list = changes.prefix(6).map { "\($0.old) → \($0.new)" }.joined(separator: ", ")
        return lead + " Renumbered: " + list + (changes.count > 6 ? " and \(changes.count - 6) more." : ".")
    }

    private func reportRenumbering(from before: [String: String]) {
        let after = ids
        let changes = letter.orderedCommentKeys.compactMap { k -> Renumbering? in
            guard let o = before[k], let n = after[k], o != n else { return nil }
            return Renumbering(key: k, old: o, new: n)
        }
        if !changes.isEmpty { show(renumberingText("Comments were renumbered; cross-references follow automatically.", changes)) }
    }

    func unwrapCommentText(_ key: String) {
        perform("Join Wrapped Lines") { letter in
            if let t = letter.comments[key]?.text { letter.comments[key]?.text = TextTools.unwrap(t) }
        }
    }

    // MARK: - Related comments and cross-references

    func setRelated(_ a: String, _ b: String, _ on: Bool) {
        perform(on ? "Add Related Comment" : "Remove Related Comment") { $0.setRelated(a, b, on) }
    }

    func resolve(_ ref: PendingReference, choosing keys: [String]) {
        perform("Resolve Cross-reference") { $0.resolvePending(ref, choosing: keys) }
    }

    func insertReference(_ key: String) {
        guard let editor = activeEditor else {
            NSSound.beep()
            return
        }
        editor.insertToken(.ref([key]))
    }

    // MARK: - Variables

    func insertVariable(_ key: String) {
        guard let editor = activeEditor else {
            NSSound.beep()
            return
        }
        editor.insertToken(.variable(key))
    }

    /// New Variable, from the selected text of the active editor if any.
    func beginNewVariable(from editor: EditorTextView? = nil) {
        let editor = editor ?? activeEditor
        variableTarget = editor
        sheet = .newVariable(editor?.selectedPlainText ?? "")
    }

    func createVariable(name: String, value: String) {
        let key = perform("New Variable") { $0.addVariable(name: name, value: value) }
        if let key, let editor = variableTarget, editor.window != nil {
            editor.insertToken(.variable(key))
        }
        variableTarget = nil
    }

    func addVariable() -> String? {
        perform("New Variable") { $0.addVariable(name: "New Variable", value: "") }
    }

    func deleteVariable(_ key: String) {
        guard let v = letter.variable(key) else { return }
        let uses = letter.variableUses()[key]?.count ?? 0
        if uses > 0 {
            let alert = NSAlert()
            alert.messageText = "Delete the Variable “\(v.name)”?"
            alert.informativeText = "It is used \(uses) time(s). Its text (“\(v.value)”) stays where it is used, as ordinary text. You can undo this."
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        perform("Delete Variable") { $0.deleteVariable(key) }
    }

    // MARK: - Editing the decision letter

    func beginEditingLetter() {
        guard isOpen, !isEditingLetter else { return }
        flushSaves()
        letterDraft = letter.decisionLetter
        letterEdits = []
        letterSelection = NSRange(location: 0, length: 0)
        isEditingLetter = true
        selection = .decisionLetter
    }

    func recordLetterEdits(_ edits: [LetterEdit], text: String) {
        letterEdits.append(contentsOf: edits)
        letterDraft = text
    }

    func cancelEditingLetter() {
        if letterDraft != letter.decisionLetter {
            let alert = NSAlert()
            alert.messageText = "Discard your changes to the decision letter?"
            alert.addButton(withTitle: "Discard")
            alert.addButton(withTitle: "Keep Editing")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        isEditingLetter = false
        letterDraft = ""
        letterEdits = []
    }

    /// Works out what the edits do to the marked comments; applies them at
    /// once if no comment's text was changed or deleted, otherwise asks.
    func finishEditingLetter() {
        guard isEditingLetter else { return }
        guard letterDraft != letter.decisionLetter else {
            isEditingLetter = false
            letterEdits = []
            return
        }
        let revision = letter.revision(newText: letterDraft, edits: letterEdits)
        if revision.needsAttention.isEmpty {
            applyLetterRevision(revision, decisions: [:])
        } else {
            sheet = .letterRevision(revision)
        }
    }

    func applyLetterRevision(_ revision: LetterRevision, decisions: [String: AnchorDecision]) {
        let before = ids
        let deleted = revision.needsAttention.filter { (decisions[$0.key] ?? $0.defaultDecision) == .delete }.count
        perform("Edit Decision Letter") { $0.apply(revision, decisions: decisions) }
        isEditingLetter = false
        letterDraft = ""
        letterEdits = []
        letterSelection = NSRange(location: 0, length: 0)
        validateSelection()
        var parts = ["Decision letter updated."]
        if revision.shifted > 0 { parts.append("\(revision.shifted) comment(s) moved with the text.") }
        if !revision.relocated.isEmpty { parts.append("\(revision.relocated.count) found again where their text now is.") }
        let decided = revision.needsAttention.count - deleted
        if decided > 0 { parts.append("\(decided) updated as you chose.") }
        if deleted > 0 { parts.append("\(deleted) deleted.") }
        show(renumberingText(parts.joined(separator: " "), letter.orderedCommentKeys.compactMap { k in
            guard let o = before[k], let n = ids[k], o != n else { return nil }
            return Renumbering(key: k, old: o, new: n)
        }))
    }

    // MARK: - Export

    private func savePanel(name: String, type: UTType) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = name
        if let url = workspaceURL { panel.directoryURL = url.deletingLastPathComponent() }
        return panel.runModal() == .OK ? panel.url : nil
    }

    private var exportBaseName: String {
        let m = letter.settings.manuscript.trimmingCharacters(in: .whitespaces)
        return (m.isEmpty ? (workspaceURL?.lastPathComponent ?? "Response letter") : m).replacingOccurrences(of: "/", with: "-")
    }

    private var docxType: UTType { UTType(filenameExtension: "docx") ?? .data }

    func exportResponseLetter() -> Bool {
        flushSaves()
        guard let url = savePanel(name: "\(exportBaseName) - Response letter.docx", type: docxType) else { return false }
        return write(DocxExport.responseLetter(letter), to: url)
    }

    func exportDiscussion() {
        flushSaves()
        guard let url = savePanel(name: "\(exportBaseName) - For co-authors.docx", type: docxType) else { return }
        _ = write(DocxExport.discussion(letter), to: url)
    }

    func exportCSV() {
        flushSaves()
        guard let url = savePanel(name: "\(exportBaseName) - Comments.csv", type: .commaSeparatedText) else { return }
        _ = write(Data(CSV.comments(letter).utf8), to: url)
    }

    private func write(_ data: Data, to url: URL) -> Bool {
        do {
            try data.write(to: url, options: .atomic)
            show("Exported “\(url.lastPathComponent)”.")
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return true
        } catch {
            errorMessage = "Couldn't export. \(error.localizedDescription)"
            return false
        }
    }
}
