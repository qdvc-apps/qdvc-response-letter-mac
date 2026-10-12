import AppKit
import ResponseCore
import SwiftUI

// MARK: - New response letter

struct NewLetterSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var folder: URL?
    @State private var title = LetterSettings().title
    @State private var manuscript = ""
    @State private var decision = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Response Letter").font(.title2).fontWeight(.semibold)
            Form {
                TextField("Title", text: $title, prompt: Text("Response to the editors and reviewers"))
                TextField("Manuscript ID", text: $manuscript, prompt: Text("Optional, such as MISQ-2026-0123"))
            }
            HStack {
                Text("Decision letter").font(.headline)
                Spacer()
                Button("Paste from Clipboard") {
                    if let s = NSPasteboard.general.string(forType: .string) { decision = s }
                }
            }
            TextEditor(text: $decision)
                .font(.system(size: 12))
                .frame(minHeight: 280)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
                .overlay(alignment: .topLeading) {
                    if decision.isEmpty {
                        Text("Paste the decision letter here, as plain text.")
                            .foregroundStyle(.tertiary)
                            .padding(8)
                            .allowsHitTesting(false)
                    }
                }
            Text("The decision letter is kept exactly as pasted; you mark sections and comments in it next.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                if let folder {
                    Label(folder.lastPathComponent, systemImage: "folder").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(folder == nil ? "Create…" : "Create") {
                    if model.createLetter(in: folder, title: title, manuscript: manuscript, decisionLetter: decision) {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(decision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 640, height: 600)
    }
}

// MARK: - Letter settings

struct LetterSettingsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var settings = LetterSettings()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Letter Settings").font(.title2).fontWeight(.semibold)
            Form {
                Section("Letter") {
                    TextField("Title", text: $settings.title)
                    TextField("Manuscript ID", text: $settings.manuscript)
                }
                Section("Comment IDs") {
                    TextField("Between prefix and number", text: $settings.separator)
                    Stepper("Digits: \(settings.digits)", value: $settings.digits, in: 1...4)
                    LabeledContent("Example") {
                        Text(example).font(.system(.body, design: .monospaced))
                    }
                    Text("Each section's prefix (SE, AE, RE1…) is set in the section itself: right-click its heading in the sidebar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ExportFormatFields(settings: $settings)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    let s = settings
                    model.updateSettings { $0 = s }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520, height: 600)
        .onAppear { settings = model.letter.settings }
    }

    var example: String {
        ResponseLetter(settings: settings).formatID(prefix: "RE1", index: 2)
    }
}

struct ExportFormatFields: View {
    @Binding var settings: LetterSettings

    var body: some View {
        Section("Word document") {
            TextField("Font", text: $settings.fontName)
            Stepper(value: $settings.fontSize, in: 8...16, step: 0.5) {
                Text("Size: \(settings.fontSize, specifier: "%g") pt")
            }
            Picker("Quoted text", selection: $settings.quoteStyle) {
                ForEach(QuoteStyle.allCases, id: \.self) { Text($0.label).tag($0) }
            }
        }
    }
}

// MARK: - Section

struct SectionSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var draft: SectionDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(draft.key == nil ? "New Section" : "Edit Section").font(.title2).fontWeight(.semibold)
            Form {
                Picker("Who", selection: $draft.role) {
                    ForEach(SectionRole.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .onChange(of: draft.role) { _, role in resetNames(role) }
                if draft.role.isNumbered {
                    Stepper("Number: \(draft.number)", value: $draft.number, in: 1...20)
                        .onChange(of: draft.number) { _, _ in resetNames(draft.role) }
                }
                TextField("Title", text: $draft.title)
                TextField("ID prefix", text: $draft.prefix)
                LabeledContent("Export heading", value: "\(draft.title) comments")
                LabeledContent("First comment", value: model.letter.formatID(prefix: draft.prefix, index: 0))
                if draft.anchor != nil {
                    Text("Comments marked after this point in the decision letter go into this section.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(draft.key == nil ? "Add Section" : "Save") {
                    model.saveSection(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    func resetNames(_ role: SectionRole) {
        draft.title = role.defaultTitle(number: draft.number)
        draft.prefix = role.defaultPrefix(number: draft.number)
    }
}

// MARK: - After a split

/// Asks, for every cross-reference to the comment that was split, which part
/// it now means; and which parts the related comments relate to.
struct SplitResolutionSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let result: SplitResult
    @State private var relatedChoice: [String: Int] = [:]   // 0 first, 1 second, 2 both

    var body: some View {
        let ids = model.ids
        let a = ids[result.firstKey] ?? "?"
        let b = ids[result.secondKey] ?? "?"
        let pending = model.letter.pendingReferences().filter {
            $0.candidates.contains(result.firstKey) && $0.candidates.contains(result.secondKey)
        }
        VStack(alignment: .leading, spacing: 12) {
            Text("Split into \(a) and \(b)").font(.title2).fontWeight(.semibold)
            if !result.renumbered.isEmpty {
                Text(model.renumberingText("Later comments were renumbered, and cross-references to them follow automatically.",
                                           result.renumbered))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !pending.isEmpty {
                        Text("Cross-references to the original comment").font(.headline)
                        Text("Each of these pointed to \(a) before the split. Which part does it mean now?")
                            .font(.callout)
                        ForEach(pending) { p in
                            GroupBox {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(ResponseLetter.describe(p.location, ids: ids).capitalizingFirst)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    PendingChoice(pending: p, ids: ids)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    } else if !result.pending.isEmpty {
                        Label("All cross-references are resolved.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    let related = result.relatedKeys.filter { model.letter.comments[$0] != nil }
                    if !related.isEmpty {
                        Text("Related comments").font(.headline)
                        Text("These were related to \(a). Both parts are now related to them; untick what no longer applies.")
                            .font(.callout)
                        ForEach(related, id: \.self) { r in
                            HStack {
                                CommentID(text: ids[r] ?? "?")
                                Text(TextTools.excerpt(model.letter.comments[r]?.text ?? "", limit: 60))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Picker("", selection: Binding(
                                    get: { relatedChoice[r] ?? 2 },
                                    set: { relatedChoice[r] = $0 }
                                )) {
                                    Text(a).tag(0)
                                    Text(b).tag(1)
                                    Text("Both").tag(2)
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .frame(width: 210)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                if !pending.isEmpty {
                    Text("Undecided cross-references stay flagged in Issues and in the export.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(pending.isEmpty ? "Done" : "Decide Later") {
                    applyRelated()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 600, height: 520)
        .interactiveDismissDisabled()
    }

    func applyRelated() {
        let changes = relatedChoice.filter { $0.value != 2 }
        guard !changes.isEmpty else { return }
        let first = result.firstKey, second = result.secondKey
        model.perform("Related Comments") { letter in
            for (r, choice) in changes {
                letter.setRelated(first, r, choice == 0)
                letter.setRelated(second, r, choice == 1)
            }
        }
    }
}

extension String {
    var capitalizingFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - Export

struct ExportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var settings = LetterSettings()

    var body: some View {
        let blocking = model.blockingIssues
        let p = model.letter.progress()
        VStack(alignment: .leading, spacing: 12) {
            Text("Export Response Letter").font(.title2).fontWeight(.semibold)
            Text("An A4 Word document: the opening, a table of every comment and its response (ID, Editor/Reviewer Comments, Response) with a black band for each section, and the closing.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Form {
                Section("Progress") {
                    LabeledContent("Final", value: "\(p.count(.final)) of \(p.total)")
                    if p.count(.todo) > 0 {
                        Label("\(p.count(.todo)) comment(s) still to do", systemImage: "circle")
                            .foregroundStyle(.secondary)
                    }
                }
                if !blocking.isEmpty {
                    Section("Would show in the letter") {
                        ForEach(blocking.prefix(6)) { issue in
                            Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        if blocking.count > 6 { Text("…and \(blocking.count - 6) more.").foregroundStyle(.secondary) }
                        Button("Show Issues") {
                            dismiss()
                            model.selection = .issues
                        }
                    }
                }
                ExportFormatFields(settings: $settings)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Export…") {
                    let s = settings
                    if s != model.letter.settings { model.updateSettings { $0 = s } }
                    if model.exportResponseLetter() { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 540, height: 560)
        .onAppear { settings = model.letter.settings }
    }
}

// MARK: - New Variable

struct NewVariableSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var value: String
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Variable").font(.title2).fontWeight(.semibold)
            Text("One official version of a piece of text, used wherever you insert it. Change it in Variables and every use changes.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Form {
                TextField("Name", text: $name, prompt: Text("Such as “Page of Hypothesis 2”"))
                TextField("Value", text: $value, prompt: Text("Such as “p. 14”"), axis: .vertical)
                    .lineLimit(1...8)
            }
            .formStyle(.grouped)
            if model.variableTarget != nil {
                Text(value.isEmpty ? "It will be inserted at the insertion point." : "It will replace the selected text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Variable") {
                    let n = name.trimmingCharacters(in: .whitespaces)
                    model.createVariable(name: n.isEmpty ? TextTools.excerpt(value, limit: 30) : n, value: value)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty && value.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

// MARK: - App settings (⌘,)

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Editors") {
                Stepper(value: $model.editorFontSize, in: 10...22, step: 1) {
                    Text("Text size: \(Int(model.editorFontSize)) pt")
                }
            }
            Section("Decision letter") {
                Toggle("Highlight comments in their triage colour", isOn: $model.triageColoursInLetter)
                Text("Otherwise every marked comment is highlighted in the accent colour.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Text("Letter-specific settings, such as the comment numbering and the Word document's font, are in File › Letter Settings (⌥⌘L) and are saved with each response letter.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 340)
    }
}
