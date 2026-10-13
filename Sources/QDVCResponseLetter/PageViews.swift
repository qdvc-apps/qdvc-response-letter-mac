import AppKit
import ResponseCore
import SwiftUI

// MARK: - Overview

struct OverviewRow: Identifiable {
    var id: String
    var displayID: String
    var section: String
    var triage: Triage
    var status: Status
    var comment: String
    var ideas: String
    var response: String
}

/// Every comment in one table, for triage: select rows and press ⌘1–⌘3 to
/// colour them, ⌥⌘1–⌥⌘3 to set their status; double-click to open.
struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var rows: [OverviewRow] {
        let ids = model.ids
        let letter = model.letter
        return letter.sections.flatMap { section in
            model.visibleKeys(in: section, ids: ids).compactMap { key -> OverviewRow? in
                guard let c = letter.comments[key] else { return nil }
                return OverviewRow(
                    id: key, displayID: ids[key] ?? "?", section: section.title, triage: c.triage, status: c.status,
                    comment: TextTools.excerpt(c.text, limit: 220),
                    ideas: c.ideas.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                        .map { "• " + letter.ideaText($0, ids: ids) }.joined(separator: "  "),
                    response: TextTools.excerpt(c.responseText.plainText { letter.tokenDisplay($0, ids: ids) }, limit: 220)
                )
            }
        }
    }

    var body: some View {
        @Bindable var model = model
        if model.letter.orderedCommentKeys.isEmpty {
            ContentUnavailableView {
                Label("No comments yet", systemImage: "text.badge.plus")
            } description: {
                Text("Mark the editors' and reviewers' comments in the decision letter first.")
            } actions: {
                Button("Open Decision Letter") { model.selection = .decisionLetter }
            }
        } else {
            Table(rows, selection: $model.tableSelection) {
                TableColumn("ID") { r in CommentID(text: r.displayID, size: model.textSize) }
                    .width(min: 56 * model.textScale, ideal: 76 * model.textScale, max: 120 * model.textScale)
                TableColumn("Triage") { r in
                    TriageDot(triage: r.triage, size: 10 * model.textScale).help(r.triage.label)
                }
                .width(52 * model.textScale)
                TableColumn("Status") { r in
                    HStack(spacing: 4) { StatusIcon(status: r.status); Text(r.status.label) }
                }
                .width(min: 70, ideal: 84, max: 100)
                TableColumn("Comment") { r in Text(r.comment).lineLimit(3).help(r.comment) }
                    .width(min: 160, ideal: 320)
                TableColumn("Ideas") { r in Text(r.ideas).lineLimit(3).foregroundStyle(.secondary) }
                    .width(min: 100, ideal: 200)
                TableColumn("Response") { r in Text(r.response).lineLimit(3) }
                    .width(min: 160, ideal: 320)
            }
            .contextMenu(forSelectionType: String.self) { keys in
                CommentContextMenu(keys: model.letter.orderedCommentKeys.filter { keys.contains($0) })
            } primaryAction: { keys in
                if let first = model.letter.orderedCommentKeys.first(where: { keys.contains($0) }) { model.openComment(first) }
            }
            .font(.system(size: model.textSize))
            .onDeleteCommand { model.deleteComments() }
        }
    }
}

// MARK: - Opening and closing

struct OpeningClosingView: View {
    @Environment(AppModel.self) private var model
    @State private var opening = EditorHandle()
    @State private var closing = EditorHandle()

    var body: some View {
        ReadableColumn {
            PaneStack(storageKey: "openingClosing", items: [
                .init(id: "opening", minHeight: 140, weight: 0.6, view: AnyView(
                Pane(title: "Before the table") {
                    FormatBar(editor: { opening.textView })
                } content: {
                    FillingScroll {
                    RichTextEditor(
                        markup: model.letter.opening, size: model.textSize,
                        tokenSignature: model.tokenSignature, look: { model.look($0) }, handle: opening,
                        placeholder: "Dear Professor …, thank you for the opportunity to revise our manuscript …",
                        onChange: { model.setOpening($0) }, onFocus: { model.setActiveEditor($0, at: .opening) },
                        onTokenDoubleClick: { model.openToken($0) }
                    )
                    }
                })),
                .init(id: "closing", minHeight: 110, weight: 0.4, view: AnyView(
                Pane(title: "After the table") {
                    FormatBar(editor: { closing.textView })
                } content: {
                    FillingScroll {
                    RichTextEditor(
                        markup: model.letter.closing, size: model.textSize,
                        tokenSignature: model.tokenSignature, look: { model.look($0) }, handle: closing,
                        placeholder: "Thank you again … Yours sincerely, …",
                        onChange: { model.setClosing($0) }, onFocus: { model.setActiveEditor($0, at: .closing) },
                        onTokenDoubleClick: { model.openToken($0) }
                    )
                    }
                })),
            ])
        }
    }
}

// MARK: - Variables

/// Text with one official version, used in many places: change it here and
/// it changes everywhere.
struct VariablesView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: Set<String> = []

    var body: some View {
        let uses = model.letter.variableUses()
        let ids = model.ids
        VStack(spacing: 0) {
            if model.letter.variables.isEmpty {
                ContentUnavailableView {
                    Label("No Variables yet", systemImage: "curlybraces")
                } description: {
                    Text("A Variable is a piece of text with one official version — a page number, a word count, a quotation from the revised manuscript — that you use in many responses. Change it here and it changes everywhere. Select text in a response and choose Variable › New Variable from Selection, or add one here.")
                        .frame(maxWidth: 480)
                } actions: {
                    Button("Add Variable") { if let k = model.addVariable() { selection = [k] } }
                }
            } else {
                Table(model.letter.variables, selection: $selection) {
                    TableColumn("Name") { v in
                        TextField("Name", text: Binding(get: { v.name }, set: { model.setVariable(v.key, name: $0) }))
                            .textFieldStyle(.plain)
                    }
                    .width(min: 120, ideal: 200)
                    TableColumn("Value (what the letter says)") { v in
                        TextField("Value", text: Binding(get: { v.value }, set: { model.setVariable(v.key, value: $0) }),
                                  axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(1...6)
                    }
                    .width(min: 200, ideal: 420)
                    TableColumn("Used in") { v in
                        let places = (uses[v.key] ?? []).map { place(of: $0, ids: ids) }
                        Text(places.isEmpty ? "Not used" : Array(Set(places)).sorted().joined(separator: ", "))
                            .foregroundStyle(places.isEmpty ? Color.orange : Color.secondary)
                            .lineLimit(2)
                    }
                    .width(min: 100, ideal: 220)
                }
                .onDeleteCommand { for k in selection { model.deleteVariable(k) } }
            }
            Divider()
            HStack {
                Button { if let k = model.addVariable() { selection = [k] } } label: { Image(systemName: "plus") }
                    .help("Add a Variable")
                Button { for k in selection { model.deleteVariable(k) } } label: { Image(systemName: "minus") }
                    .disabled(selection.isEmpty)
                    .help("Delete the selected Variables; their text stays where they are used")
                Spacer()
                Text("Double-click a Variable in a response to come here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }

    func place(of location: TextLocation, ids: [String: String]) -> String {
        switch location {
        case .opening: return "opening"
        case .closing: return "closing"
        case .response(let k): return ids[k] ?? "?"
        case .ideas(let k): return "ideas for \(ids[k] ?? "?")"
        }
    }
}

// MARK: - Issues

struct IssuesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let issues = model.issues
        let ids = model.ids
        if issues.isEmpty {
            ContentUnavailableView("No issues", systemImage: "checkmark.seal",
                                   description: Text("Cross-references, Variables and statuses all look consistent."))
        } else {
            List {
                let blocking = issues.filter(\.kind.isBlocking)
                let others = issues.filter { !$0.kind.isBlocking }
                if !blocking.isEmpty {
                    Section("Would show in the exported letter") {
                        ForEach(blocking) { IssueRow(issue: $0, ids: ids) }
                    }
                }
                if !others.isEmpty {
                    Section("Worth a look") {
                        ForEach(others) { IssueRow(issue: $0, ids: ids) }
                    }
                }
            }
        }
    }
}

struct IssueRow: View {
    @Environment(AppModel.self) private var model
    var issue: Issue
    var ids: [String: String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: issue.kind.isBlocking ? "exclamationmark.triangle.fill" : "info.circle")
                    .foregroundStyle(issue.kind.isBlocking ? Color.orange : Color.secondary)
                Text(issue.message)
                Spacer()
                if let key = issue.commentKey {
                    Button("Open \(ids[key] ?? "?")") { model.openComment(key) }
                } else if issue.variableKey != nil {
                    Button("Show Variables") { model.selection = .variables }
                } else if issue.location == .opening || issue.location == .closing {
                    Button("Show") { model.selection = .openingClosing }
                }
            }
            if let p = issue.pending {
                PendingChoice(pending: p, ids: ids)
                    .padding(.leading, 24)
            }
        }
        .padding(.vertical, 2)
    }
}

/// "…see our response to [?]" with a button per candidate, and Both.
struct PendingChoice: View {
    @Environment(AppModel.self) private var model
    var pending: PendingReference
    var ids: [String: String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pending.context)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .textSelection(.enabled)
            HStack {
                Text("[?] means")
                ForEach(pending.candidates, id: \.self) { k in
                    Button(ids[k] ?? "?") { model.resolve(pending, choosing: [k]) }
                        .help(TextTools.excerpt(model.letter.comments[k]?.text ?? "", limit: 200))
                }
                Button(pending.candidates.count == 2 ? "Both" : "All") { model.resolve(pending, choosing: pending.candidates) }
            }
            .controlSize(.small)
        }
    }
}
