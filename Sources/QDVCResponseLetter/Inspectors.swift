import AppKit
import ResponseCore
import SwiftUI

// MARK: - Format bar

/// Bold, italic, quote, bullets, and inserting Variables and
/// Cross-references, for the editor `editor()` returns (the focused
/// response in the Response Editor; a given editor elsewhere). Drops its
/// labels when there isn't room.
struct FormatBar: View {
    @Environment(AppModel.self) private var model
    var editor: () -> EditorTextView?
    var exclude: String?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            bar(labels: true)
            bar(labels: false)
        }
    }

    func bar(labels: Bool) -> some View {
        HStack(spacing: 2) {
            Button { editor()?.toggleTrait(.rlBold) } label: { Image(systemName: "bold") }
                .help("Bold (⌘B)")
            Button { editor()?.toggleTrait(.rlItalic) } label: { Image(systemName: "italic") }
                .help("Italic (⌘I)")
            Button { editor()?.toggleBlock(.quote) } label: { Image(systemName: "text.quote") }
                .help("Quoted text from the manuscript (⌘')")
            Button { editor()?.toggleBlock(.bullet) } label: { Image(systemName: "list.bullet") }
                .help("Bulleted list (⇧⌘7)")
            Divider().frame(height: 14).padding(.horizontal, 4)
            Menu {
                ForEach(model.letter.variables) { v in
                    Button("\(v.name) — \(TextTools.excerpt(v.value, limit: 40))") {
                        editor()?.insertToken(.variable(v.key))
                    }
                }
                if !model.letter.variables.isEmpty { Divider() }
                Button("New Variable from Selection…") { model.beginNewVariable(from: editor()) }
            } label: {
                if labels { Label("Variable", systemImage: "curlybraces") } else { Image(systemName: "curlybraces") }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            // A fixed width: a menu button otherwise takes the width of its
            // longest item, and these items are long excerpts.
            .frame(width: labels ? 92 : 40)
            .help("Insert a Variable: text with one official version, used in many places")
            Menu {
                CrossReferenceMenuItems(model: model, exclude: exclude) { k in
                    editor()?.insertToken(.ref([k]))
                }
            } label: {
                if labels {
                    Label("Cross-reference", systemImage: "arrow.turn.down.right")
                } else {
                    Image(systemName: "arrow.turn.down.right")
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .frame(width: labels ? 132 : 40)
            .help("Insert a cross-reference to another comment; it follows renumbering")
        }
        .buttonStyle(.borderless)
        .labelStyle(.titleAndIcon)
        .controlSize(.small)
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Inspector

struct InspectorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let key = model.selectedCommentKey, model.letter.comments[key] != nil {
            if model.selection == .triageEditor {
                TriageInspector(key: key)
            } else {
                CommentInspector(key: key)
            }
        } else if model.targetKeys.count > 1 {
            MultiInspector(keys: model.targetKeys)
        } else {
            LetterSummary()
        }
    }
}

/// Buttons to open a comment in the two editors.
struct OpenInEditors: View {
    @Environment(AppModel.self) private var model
    let key: String

    var body: some View {
        HStack {
            if model.selection != .triageEditor {
                Button("Triage") { model.openInTriage(key) }
                    .help("Show this comment in “Triage the comments”")
            }
            if model.selection != .responseEditor {
                Button("Respond") { model.openComment(key) }
                    .help("Show this comment in “Respond to the comments”")
            }
        }
    }
}

/// The comment's ID and section, with Open buttons.
struct InspectorHeader: View {
    @Environment(AppModel.self) private var model
    let key: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.id(key)).font(.system(.title3, design: .monospaced)).fontWeight(.semibold)
                    .textSelection(.enabled)
                Text(model.letter.section(ofComment: key)?.title ?? "").foregroundStyle(.secondary)
            }
            OpenInEditors(key: key).controlSize(.small)
        }
    }
}

struct CommentInspector: View {
    @Environment(AppModel.self) private var model
    let key: String

    var body: some View {
        let c = model.letter.comments[key]!
        Form {
            Section { InspectorHeader(key: key) }
            if model.selection != .responseEditor {
                Section {
                    TriageChooser(triage: c.triage) { model.setTriage($0, for: [key]) }
                    Picker("Status", selection: Binding(get: { c.status }, set: { model.setStatus($0, for: [key]) })) {
                        ForEach(Status.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                }
            }
            RelatedSection(key: key)
            SourceSection(key: key)
            IssuesSection(key: key)
            DetailsSection(key: key)
        }
        .formStyle(.grouped)
    }
}

/// The Triage Editor's inspector: the triage colour (with its shortcut),
/// the status, and related comments. The comment and the ideas are edited
/// in the table.
struct TriageInspector: View {
    @Environment(AppModel.self) private var model
    let key: String

    var body: some View {
        let c = model.letter.comments[key]!
        Form {
            Section { InspectorHeader(key: key) }
            Section("Triage") {
                ForEach(Triage.allCases, id: \.self) { t in
                    Button {
                        model.setTriage(t, for: [key])
                    } label: {
                        HStack {
                            TriageDot(triage: t, size: 12)
                            Text(t.label)
                            Spacer()
                            if c.triage == t { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            Text(t == .none ? "⌘0" : "⌘\(Triage.allCases.firstIndex(of: t) ?? 0)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Picker("Status", selection: Binding(get: { c.status }, set: { model.setStatus($0, for: [key]) })) {
                    ForEach(Status.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }
            RelatedSection(key: key)
        }
        .formStyle(.grouped)
    }
}

struct RelatedSection: View {
    @Environment(AppModel.self) private var model
    let key: String

    var body: some View {
        let c = model.letter.comments[key]!
        let ids = model.ids
        Section("Related comments") {
            if c.related.isEmpty {
                Text("None. Link comments that ask for the same thing, such as an editor summarising a reviewer.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(c.related, id: \.self) { r in
                if let other = model.letter.comments[r] {
                    HStack(alignment: .firstTextBaseline) {
                        TriageDot(triage: other.triage, size: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Button(ids[r] ?? "?") { model.reveal(r) }
                                .buttonStyle(.link)
                                .font(.system(.body, design: .monospaced))
                            Text(TextTools.excerpt(other.text, limit: 90))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Menu {
                            Button("Insert Cross-reference") { model.insertReference(r) }
                                .disabled(model.activeEditor == nil)
                            Button("Remove from Related") { model.setRelated(key, r, false) }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .frame(width: 28)
                    }
                }
            }
            Menu("Add Related Comment") {
                CrossReferenceMenuItems(model: model, exclude: key, excludeAlso: c.related) {
                    model.setRelated(key, $0, true)
                }
            }
            .frame(maxWidth: 220, alignment: .leading)
        }
    }
}

struct SourceSection: View {
    @Environment(AppModel.self) private var model
    let key: String

    var body: some View {
        Section("Decision letter") {
            if model.letter.comments[key]?.source.isEmpty ?? true {
                Text("Not marked in the decision letter.").foregroundStyle(.secondary)
            } else {
                Button("Show in Decision Letter") {
                    model.selection = .decisionLetter
                    model.revealInLetter = key
                    model.revealRevision += 1
                }
            }
        }
    }
}

struct IssuesSection: View {
    @Environment(AppModel.self) private var model
    let key: String

    var body: some View {
        let issues = model.issues(for: key)
        if !issues.isEmpty {
            Section("Issues") {
                ForEach(issues) { issue in
                    Label(issue.message, systemImage: issue.kind.isBlocking ? "exclamationmark.triangle.fill" : "info.circle")
                        .foregroundStyle(issue.kind.isBlocking ? Color.orange : Color.secondary)
                }
                Button("Show All Issues") { model.selection = .issues }
            }
        }
    }
}

struct DetailsSection: View {
    @Environment(AppModel.self) private var model
    let key: String

    var body: some View {
        let c = model.letter.comments[key]!
        let ids = model.ids
        Section("Details") {
            LabeledContent("Comment", value: "\(TextStats.wordCount(c.text)) words")
            LabeledContent("Response", value: "\(TextStats.wordCount(c.responseText.plainText { model.letter.tokenDisplay($0, ids: ids) })) words")
            LabeledContent("Key") {
                Text(key).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }
            .help("The comment's file is comments/\(key).yml; the key never changes, even when the comment is renumbered.")
        }
    }
}

struct MultiInspector: View {
    @Environment(AppModel.self) private var model
    let keys: [String]

    var body: some View {
        Form {
            Section("\(keys.count) comments selected") {
                TriageChooser(triage: .none) { model.setTriage($0, for: keys) }
                Picker("Status", selection: Binding<Status?>(get: { nil }, set: { if let s = $0 { model.setStatus(s, for: keys) } })) {
                    Text("—").tag(Status?.none)
                    ForEach(Status.allCases, id: \.self) { Text($0.label).tag(Status?.some($0)) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct LetterSummary: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let p = model.letter.progress()
        Form {
            if model.selection == .triageEditor || model.selection == .overview || model.selection == .traceability {
                Section {
                    Text(model.selection == .traceability
                         ? "Select a card to see its comment here; double-click to respond to it."
                         : "Select a comment to see it here.")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Progress") {
                LabeledContent("Comments", value: "\(p.total)")
                LabeledContent("Final", value: "\(p.count(.final))")
                LabeledContent("Drafted", value: "\(p.count(.drafted))")
                LabeledContent("To do", value: "\(p.count(.todo))")
            }
            Section("Triage") {
                ForEach(Triage.allCases, id: \.self) { t in
                    LabeledContent {
                        Text("\(p.count(t))")
                    } label: {
                        HStack { TriageDot(triage: t); Text(t.label) }
                    }
                }
            }
            Section("Letter") {
                LabeledContent("Title", value: model.letter.settings.title)
                if !model.letter.settings.manuscript.isEmpty {
                    LabeledContent("Manuscript", value: model.letter.settings.manuscript)
                }
                Button("Letter Settings…") { model.sheet = .letterSettings }
            }
        }
        .formStyle(.grouped)
    }
}
