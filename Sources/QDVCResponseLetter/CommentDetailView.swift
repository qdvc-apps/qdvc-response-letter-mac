import AppKit
import ResponseCore
import SwiftUI

struct CommentDetailView: View {
    @Environment(AppModel.self) private var model
    let key: String
    @State private var responseHandle = EditorHandle()

    var body: some View {
        if let c = model.letter.comments[key] {
            let id = model.id(key)
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(id).font(.system(.title2, design: .monospaced)).fontWeight(.semibold)
                        .textSelection(.enabled)
                    Text(model.letter.section(ofComment: key)?.title ?? "")
                        .foregroundStyle(.secondary)
                    Spacer()
                    TriageChooser(triage: c.triage) { model.setTriage($0, for: [key]) }
                    Picker("Status", selection: Binding(
                        get: { c.status },
                        set: { model.setStatus($0, for: [key]) }
                    )) {
                        ForEach(Status.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                Divider()
                PaneStack(storageKey: "comment", items: [
                    .init(id: "comment", minHeight: 90, weight: 0.27, view: AnyView(
                    Pane(title: "Editor/Reviewer comment") {
                        Button("Join Wrapped Lines") { model.unwrapCommentText(key) }
                            .help("Turn hard-wrapped lines into paragraphs")
                        Button("Split Here") { model.splitAtCursor() }
                            .disabled(!model.canSplit)
                            .help("Split this comment in two at the insertion point (⌥⌘D)")
                        Button("Merge with Next") { model.mergeWithNext(key) }
                            .disabled(!model.canMergeWithNext(key))
                            .help("Join the next comment onto this one (⌥⌘J)")
                    } content: {
                        PlainTextEditor(
                            text: c.text,
                            size: CGFloat(model.editorFontSize),
                            placeholder: "The editor's or reviewer's words",
                            onChange: { model.setCommentText(key, $0) },
                            onSelectionChange: { range in
                                model.commentCursor = range.length == 0 ? (key, range.location) : nil
                            }
                        )
                    }
                    .controlSize(.small))),
                    .init(id: "ideas", minHeight: 70, weight: 0.18, view: AnyView(
                    Pane(title: "Ideas") {
                        Text("One dot point per line").font(.caption).foregroundStyle(.secondary)
                    } content: {
                        PlainTextEditor(
                            text: c.ideas.joined(separator: "\n"),
                            size: CGFloat(model.editorFontSize),
                            bulleted: true,
                            placeholder: "Initial ideas for the response",
                            onChange: { model.setIdeas(key, $0) }
                        )
                    })),
                    .init(id: "response", minHeight: 160, weight: 0.55, view: AnyView(
                    Pane(title: "Response") {
                        FormatBar(handle: responseHandle, exclude: key)
                        Text("\(TextStats.wordCount(c.responseText.plainText { model.letter.tokenDisplay($0) })) words")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } content: {
                        RichTextEditor(
                            markup: c.response,
                            size: CGFloat(model.editorFontSize),
                            tokenSignature: model.tokenSignature,
                            look: { model.look($0) },
                            handle: responseHandle,
                            placeholder: "Your response",
                            onChange: { model.setResponse(key, $0) },
                            onFocus: { model.activeEditor = $0 },
                            onTokenDoubleClick: { model.openToken($0) }
                        )
                    })),
                ])
            }
        }
    }
}

/// Bold, italic, quote, bullets, and inserting Variables and
/// Cross-references, for the editor in `handle`.
struct FormatBar: View {
    @Environment(AppModel.self) private var model
    var handle: EditorHandle
    var exclude: String?

    var body: some View {
        HStack(spacing: 2) {
            Button { handle.textView?.toggleTrait(.rlBold) } label: { Image(systemName: "bold") }
                .help("Bold (⌘B)")
            Button { handle.textView?.toggleTrait(.rlItalic) } label: { Image(systemName: "italic") }
                .help("Italic (⌘I)")
            Button { handle.textView?.toggleBlock(.quote) } label: { Image(systemName: "text.quote") }
                .help("Quoted text from the manuscript (⌘')")
            Button { handle.textView?.toggleBlock(.bullet) } label: { Image(systemName: "list.bullet") }
                .help("Bulleted list (⇧⌘7)")
            Divider().frame(height: 14).padding(.horizontal, 4)
            Menu {
                ForEach(model.letter.variables) { v in
                    Button("\(v.name) — \(TextTools.excerpt(v.value, limit: 40))") {
                        handle.textView?.insertToken(.variable(v.key))
                    }
                }
                if !model.letter.variables.isEmpty { Divider() }
                Button("New Variable from Selection…") { model.beginNewVariable(from: handle.textView) }
            } label: {
                Label("Variable", systemImage: "curlybraces")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            // A fixed width: a menu button otherwise takes the width of its
            // longest item, and these items are long excerpts.
            .frame(width: 92)
            .help("Insert a Variable: text with one official version, used in many places")
            Menu {
                CrossReferenceMenuItems(model: model, exclude: exclude) { k in
                    handle.textView?.insertToken(.ref([k]))
                }
            } label: {
                Label("Cross-reference", systemImage: "arrow.turn.down.right")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .frame(width: 132)
            .help("Insert a cross-reference to another comment; it follows renumbering")
        }
        .buttonStyle(.borderless)
        .labelStyle(.titleAndIcon)
        .controlSize(.small)
    }
}

// MARK: - Inspector

struct InspectorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let key = model.selectedCommentKey, model.letter.comments[key] != nil {
            CommentInspector(key: key)
        } else if model.selection == .overview, model.overviewSelection.count > 1 {
            MultiInspector(keys: model.targetKeys)
        } else {
            LetterSummary()
        }
    }
}

struct CommentInspector: View {
    @Environment(AppModel.self) private var model
    let key: String

    var body: some View {
        let c = model.letter.comments[key]!
        let ids = model.ids
        Form {
            if model.selection == .overview {
                Section {
                    HStack {
                        CommentID(text: ids[key] ?? "?")
                        Spacer()
                        Button("Open") { model.openComment(key) }
                    }
                    TriageChooser(triage: c.triage) { model.setTriage($0, for: [key]) }
                    Picker("Status", selection: Binding(get: { c.status }, set: { model.setStatus($0, for: [key]) })) {
                        ForEach(Status.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                }
            }
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
                                Button(ids[r] ?? "?") { model.openComment(r) }
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
            Section("Decision letter") {
                if c.source.isEmpty {
                    Text("Not marked in the decision letter.").foregroundStyle(.secondary)
                } else {
                    Button("Show in Decision Letter") {
                        model.selection = .decisionLetter
                        model.revealInLetter = key
                        model.revealRevision += 1
                    }
                }
            }
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
            Section("Details") {
                LabeledContent("Comment", value: "\(TextStats.wordCount(c.text)) words")
                LabeledContent("Response", value: "\(TextStats.wordCount(c.responseText.plainText { model.letter.tokenDisplay($0, ids: ids) })) words")
                LabeledContent("Key") {
                    Text(key).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
                .help("The comment's file is comments/\(key).yml; the key never changes, even when the comment is renumbered.")
            }
        }
        .formStyle(.grouped)
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
