import AppKit
import ResponseCore
import SwiftUI

// The Triage Editor and the Response Editor are one table, laid out like the
// exported letter: black section bands, then one row per comment with every
// cell shown in full and edited in place, and clear borders. They differ only
// in their columns (TableLayout).

enum ColumnKind: Hashable {
    case id, triageDot, triageLabelled, status, comment, ideas, response

    var title: String {
        switch self {
        case .id: return "ID"
        case .triageDot, .triageLabelled: return "Triage"
        case .status: return "Status"
        case .comment: return "Editor/Reviewer Comments"
        case .ideas: return "Ideas"
        case .response: return "Response"
        }
    }
}

struct TableLayout: Equatable {
    struct Column: Equatable {
        var kind: ColumnKind
        var width: CGFloat
    }

    var columns: [Column]

    /// Where section headings start: the first text column, as in the
    /// exported letter.
    var textStart: CGFloat {
        var x: CGFloat = 0
        for c in columns {
            if c.kind == .comment { return x }
            x += c.width
        }
        return 0
    }

    /// ID, triage, status, comment, ideas, response.
    static func response(total: CGFloat, scale: CGFloat, showTriage: Bool, showStatus: Bool, showIdeas: Bool) -> TableLayout {
        var columns = [Column(kind: .id, width: 76 * scale)]
        if showTriage { columns.append(Column(kind: .triageDot, width: 58 * scale)) }
        if showStatus { columns.append(Column(kind: .status, width: 100 * scale)) }
        let rest = max(240, total - columns.reduce(0) { $0 + $1.width })
        let comment = floor(rest * (showIdeas ? 0.34 : 0.42))
        let ideas = showIdeas ? floor(rest * 0.20) : 0
        columns.append(Column(kind: .comment, width: comment))
        if showIdeas { columns.append(Column(kind: .ideas, width: ideas)) }
        columns.append(Column(kind: .response, width: rest - comment - ideas))
        return TableLayout(columns: columns)
    }

    /// ID, comment, triage (with its label), ideas.
    static func triage(total: CGFloat, scale: CGFloat) -> TableLayout {
        let id: CGFloat = 76 * scale
        let triage: CGFloat = 170 * scale
        let rest = max(240, total - id - triage)
        let comment = floor(rest * 0.56)
        return TableLayout(columns: [
            Column(kind: .id, width: id),
            Column(kind: .comment, width: comment),
            Column(kind: .triageLabelled, width: triage),
            Column(kind: .ideas, width: rest - comment),
        ])
    }
}

/// The table for a page; `layout` builds the columns for a width.
struct CommentTable: View {
    @Environment(AppModel.self) private var model
    var layout: (CGFloat) -> TableLayout

    var body: some View {
        if model.letter.orderedCommentKeys.isEmpty {
            ContentUnavailableView {
                Label("No comments yet", systemImage: "text.badge.plus")
            } description: {
                Text("Mark the editors' and reviewers' comments in the decision letter first.")
            } actions: {
                Button("Open Decision Letter") { model.selection = .decisionLetter }
            }
        } else {
            GeometryReader { geo in
                // Leave room for a scroller.
                let columns = layout(geo.size.width - 16)
                VStack(spacing: 0) {
                    CommentTableHeader(layout: columns)
                    Divider()
                    CommentTableRows(layout: columns)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
        }
    }
}

struct CommentTableHeader: View {
    @Environment(AppModel.self) private var model
    var layout: TableLayout

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(layout.columns.enumerated()), id: \.offset) { i, column in
                Text(column.kind.title)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(width: column.width, alignment: .leading)
                    .overlay(alignment: .trailing) {
                        if i < layout.columns.count - 1 {
                            Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1)
                        }
                    }
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11 * model.textScale, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.vertical, 5)
        .background(.bar)
    }
}

struct CommentTableRows: View {
    @Environment(AppModel.self) private var model
    var layout: TableLayout

    var body: some View {
        let ids = model.ids
        let flagged = Set(model.issues.filter(\.kind.isBlocking).compactMap(\.commentKey))
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.letter.sections) { section in
                        let keys = model.visibleKeys(in: section, ids: ids)
                        if !keys.isEmpty || !model.isFiltering {
                            SectionBand(section: section, textStart: layout.textStart)
                            ForEach(keys, id: \.self) { key in
                                if let c = model.letter.comments[key] {
                                    CommentTableRow(key: key, comment: c, id: ids[key] ?? "?", layout: layout,
                                                    focused: model.focusedCommentKey == key, flagged: flagged.contains(key))
                                        .id(key)
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 40)
            }
            .onAppear { scroll(proxy, animated: false) }
            .onChange(of: model.scrollRevision) { _, _ in scroll(proxy, animated: true) }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let key = model.scrollTarget else { return }
        DispatchQueue.main.async {
            if animated {
                withAnimation { proxy.scrollTo(key, anchor: .top) }
            } else {
                proxy.scrollTo(key, anchor: .top)
            }
        }
    }
}

/// The black band that starts a section, as in the exported letter.
struct SectionBand: View {
    @Environment(AppModel.self) private var model
    var section: LetterSection
    var textStart: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: textStart, height: 1)
            Text(section.heading)
                .font(.system(size: 13 * model.textScale, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
            Spacer(minLength: 8)
            Button {
                model.newComment(inSection: section.key)
            } label: {
                Image(systemName: "plus").foregroundStyle(.white)
            }
            .buttonStyle(.borderless)
            .help("New comment in \(section.title)")
            .padding(.trailing, 10)
        }
        .padding(.vertical, 6 * model.textScale)
        .background(Color.black)
        .contextMenu {
            Button("Edit Section…") { model.editSection(section.key) }
            Button("New Comment in \(section.title)") { model.newComment(inSection: section.key) }
            Divider()
            Button("Move Section Up") { model.moveSection(section.key, by: -1) }
            Button("Move Section Down") { model.moveSection(section.key, by: 1) }
            Divider()
            Button("Delete Section…") { model.deleteSection(section.key) }
        }
    }
}

/// One comment: every cell shown in full and editable.
struct CommentTableRow: View {
    @Environment(AppModel.self) private var model
    let key: String
    let comment: Comment
    let id: String
    let layout: TableLayout
    let focused: Bool
    let flagged: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(layout.columns.enumerated()), id: \.offset) { i, column in
                cell(column.kind)
                    .frame(width: column.width, alignment: .topLeading)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .overlay(alignment: .trailing) {
                        if i < layout.columns.count - 1 {
                            Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1)
                        }
                    }
            }
        }
        // Every cell as tall as the tallest, like a table row.
        .fixedSize(horizontal: false, vertical: true)
        .background(focused ? Color.accentColor.opacity(0.07) : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1)
        }
        .contextMenu { CommentContextMenu(keys: [key]) }
    }

    @ViewBuilder
    func cell(_ kind: ColumnKind) -> some View {
        let size = model.textSize
        let scale = model.textScale
        switch kind {
        case .id:
            VStack(alignment: .leading, spacing: 6) {
                Button(id) { model.focusRow(key) }
                    .buttonStyle(.plain)
                    .font(.system(size: size, weight: .medium, design: .monospaced))
                    .help("Right-click for split, merge, move and more")
                if flagged {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(model.issues(for: key).filter(\.kind.isBlocking).map(\.message).joined(separator: "\n"))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
        case .triageDot:
            TriagePopUp(key: key, triage: comment.triage, labelled: false, scale: scale)
                .padding(.top, 8)
                .padding(.leading, 10)
        case .triageLabelled:
            TriagePopUp(key: key, triage: comment.triage, labelled: true, scale: scale)
                .padding(.top, 7)
                .padding(.horizontal, 8)
        case .status:
            StatusPopUp(key: key, status: comment.status, scale: scale)
                .padding(.top, 7)
                .padding(.horizontal, 8)
        case .comment:
            PlainTextEditor(
                text: comment.text, size: size, placeholder: "The editor's or reviewer's words",
                onChange: { model.setCommentText(key, $0) },
                onSelectionChange: { range in
                    model.commentCursor = range.length == 0 ? (key, range.location) : nil
                },
                onFocus: { _ in model.focusRow(key) }
            )
        case .ideas:
            PlainTextEditor(
                text: comment.ideas.joined(separator: "\n"), size: size, bulleted: true,
                placeholder: "Ideas, one per line",
                onChange: { model.setIdeas(key, $0) },
                onFocus: { _ in model.focusRow(key) }
            )
        case .response:
            RichTextEditor(
                markup: comment.response, size: size, tokenSignature: model.tokenSignature,
                look: { model.look($0) }, placeholder: "Response",
                onChange: { model.setResponse(key, $0) },
                onFocus: { view in
                    model.activeEditor = view
                    model.focusRow(key)
                },
                onTokenDoubleClick: { model.openToken($0) }
            )
        }
    }
}

/// The triage colour, as a dot (or a dot and its name) that pops up the
/// choices when clicked.
struct TriagePopUp: View {
    @Environment(AppModel.self) private var model
    let key: String
    let triage: Triage
    let labelled: Bool
    let scale: CGFloat

    var body: some View {
        PopUpButton(items: Triage.allCases.map { t in
            PopUpItem(title: t.menuTitle, image: TriageDot.image(t), checked: t == triage) {
                model.setTriage(t, for: [key])
                model.focusRow(key)
            }
        }) {
            HStack(spacing: 6) {
                TriageDot(triage: triage, size: 12 * scale)
                if labelled {
                    Text(triage.label).font(.system(size: 13 * scale))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9 * scale))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .help(triage.menuTitle)
    }
}

struct StatusPopUp: View {
    @Environment(AppModel.self) private var model
    let key: String
    let status: Status
    let scale: CGFloat

    var body: some View {
        PopUpButton(items: Status.allCases.map { s in
            PopUpItem(title: s.label, image: nil, checked: s == status) {
                model.setStatus(s, for: [key])
                model.focusRow(key)
            }
        }) {
            HStack(spacing: 4) {
                StatusIcon(status: status)
                Text(status.label).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9 * scale))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12 * scale))
        }
    }
}

// MARK: - Response Editor

/// The response letter as a table, like a word processor's: section bands,
/// then each comment's ID, triage, status, comment, ideas and response, all
/// shown in full and edited in place. The format bar acts on the response
/// being edited.
struct ResponseEditorView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("responseEditor.showTriage") private var showTriage = true
    @AppStorage("responseEditor.showStatus") private var showStatus = true
    @AppStorage("responseEditor.showIdeas") private var showIdeas = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                FormatBar(editor: { model.activeEditor }, exclude: model.focusedCommentKey)
                    .disabled(model.letter.orderedCommentKeys.isEmpty)
                Spacer(minLength: 8)
                Menu {
                    Toggle("Triage", isOn: $showTriage)
                    Toggle("Status", isOn: $showStatus)
                    Toggle("Ideas", isOn: $showIdeas)
                } label: {
                    Label("Columns", systemImage: "rectangle.split.3x1")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 104)
                .controlSize(.small)
                .help("Show or hide columns")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()
            CommentTable { width in
                .response(total: width, scale: model.textScale, showTriage: showTriage,
                          showStatus: showStatus, showIdeas: showIdeas)
            }
        }
    }
}

// MARK: - Triage Editor

/// Triage, comment by comment, with the neighbours in view: ID, comment,
/// triage and ideas, all edited in place. ⌘1–⌘3 (⌘0 clears) set the triage
/// of the comment being edited; the inspector has its status and related
/// comments.
struct TriageEditorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let p = model.letter.progress()
        VStack(spacing: 0) {
            CommentTable { width in .triage(total: width, scale: model.textScale) }
            Divider()
            HStack {
                Text("⌘1 easy · ⌘2 trickier · ⌘3 needs discussion · ⌘0 clear · ⌘[ ⌘] previous and next comment")
                    .lineLimit(1)
                Spacer()
                Text("\(p.total - p.count(.none)) of \(p.total) triaged").monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
}
