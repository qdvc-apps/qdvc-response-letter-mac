import AppKit
import ResponseCore
import SwiftUI

/// Column widths for the Response Editor, from the width available: fixed
/// ID, triage and status columns, the rest shared out.
struct ResponseColumns: Equatable {
    var id: CGFloat = 76
    var triage: CGFloat = 0
    var status: CGFloat = 0
    var comment: CGFloat = 0
    var ideas: CGFloat = 0
    var response: CGFloat = 0

    init(total: CGFloat, showTriage: Bool, showStatus: Bool, showIdeas: Bool) {
        triage = showTriage ? 40 : 0
        status = showStatus ? 96 : 0
        let rest = max(240, total - id - triage - status)
        if showIdeas {
            comment = floor(rest * 0.34)
            ideas = floor(rest * 0.20)
        } else {
            comment = floor(rest * 0.42)
            ideas = 0
        }
        response = rest - comment - ideas
    }

    /// Where the comment column starts (section bands align with it, as in
    /// the exported letter).
    var commentStart: CGFloat { id + triage + status }
}

/// Every comment in one table, like the response letter in a word
/// processor: section bands, then for each comment its ID, triage, status,
/// the comment, the ideas and the response, all shown in full and edited in
/// place. The format bar acts on the response being edited.
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
                    let columns = ResponseColumns(total: geo.size.width - 16, showTriage: showTriage,
                                                  showStatus: showStatus, showIdeas: showIdeas)
                    VStack(spacing: 0) {
                        ResponseHeader(columns: columns)
                        Divider()
                        ResponseTable(columns: columns)
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                }
            }
        }
    }
}

struct ResponseHeader: View {
    var columns: ResponseColumns

    var body: some View {
        HStack(spacing: 0) {
            heading("ID", columns.id)
            if columns.triage > 0 { heading("", columns.triage) }
            if columns.status > 0 { heading("Status", columns.status) }
            heading("Editor/Reviewer Comments", columns.comment)
            if columns.ideas > 0 { heading("Ideas", columns.ideas) }
            heading("Response", columns.response)
            Spacer(minLength: 0)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.vertical, 5)
        .background(.bar)
    }

    func heading(_ text: String, _ width: CGFloat) -> some View {
        Text(text).lineLimit(1).padding(.horizontal, 8).frame(width: width, alignment: .leading)
    }
}

struct ResponseTable: View {
    @Environment(AppModel.self) private var model
    var columns: ResponseColumns

    var body: some View {
        let ids = model.ids
        let flagged = Set(model.issues.filter(\.kind.isBlocking).compactMap(\.commentKey))
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.letter.sections) { section in
                        let keys = model.visibleKeys(in: section, ids: ids)
                        if !keys.isEmpty || !model.isFiltering {
                            SectionBand(section: section, columns: columns)
                            ForEach(keys, id: \.self) { key in
                                if let c = model.letter.comments[key] {
                                    ResponseRow(key: key, comment: c, id: ids[key] ?? "?", columns: columns,
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
    var columns: ResponseColumns

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: columns.commentStart, height: 1)
            Text(section.heading)
                .fontWeight(.bold)
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
        .padding(.vertical, 6)
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
struct ResponseRow: View {
    @Environment(AppModel.self) private var model
    let key: String
    let comment: Comment
    let id: String
    let columns: ResponseColumns
    let focused: Bool
    let flagged: Bool

    var body: some View {
        let size = CGFloat(model.editorFontSize)
        HStack(alignment: .top, spacing: 0) {
            cell(columns.id) {
                VStack(alignment: .leading, spacing: 6) {
                    Button(id) { model.focusRow(key) }
                        .buttonStyle(.plain)
                        .font(.system(.body, design: .monospaced).weight(.medium))
                        .help("Right-click for split, merge, move and more")
                    if flagged {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .help(model.issues(for: key).filter(\.kind.isBlocking).map(\.message).joined(separator: "\n"))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
            }
            if columns.triage > 0 {
                cell(columns.triage) {
                    Menu {
                        ForEach(Triage.allCases, id: \.self) { t in
                            Button(t.menuTitle) { model.setTriage(t, for: [key]) }
                        }
                    } label: {
                        TriageDot(triage: comment.triage, size: 12)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 24)
                    .padding(.top, 8)
                    .padding(.leading, 8)
                    .help(comment.triage.menuTitle)
                }
            }
            if columns.status > 0 {
                cell(columns.status) {
                    Menu {
                        ForEach(Status.allCases, id: \.self) { s in
                            Button(s.label) { model.setStatus(s, for: [key]) }
                        }
                    } label: {
                        Label(comment.status.label, systemImage: comment.status.symbol)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: columns.status - 14)
                    .controlSize(.small)
                    .padding(.top, 7)
                    .padding(.leading, 6)
                }
            }
            cell(columns.comment) {
                PlainTextEditor(
                    text: comment.text, size: size, placeholder: "The editor's or reviewer's words",
                    onChange: { model.setCommentText(key, $0) },
                    onSelectionChange: { range in
                        model.commentCursor = range.length == 0 ? (key, range.location) : nil
                    },
                    onFocus: { _ in model.focusRow(key) }
                )
            }
            if columns.ideas > 0 {
                cell(columns.ideas) {
                    PlainTextEditor(
                        text: comment.ideas.joined(separator: "\n"), size: size, bulleted: true,
                        placeholder: "Ideas",
                        onChange: { model.setIdeas(key, $0) },
                        onFocus: { _ in model.focusRow(key) }
                    )
                }
            }
            cell(columns.response, last: true) {
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
        // Every cell as tall as the tallest, like a table row.
        .fixedSize(horizontal: false, vertical: true)
        .background(focused ? Color.accentColor.opacity(0.07) : Color.clear)
        .overlay(alignment: .bottom) { Divider() }
        .contextMenu { CommentContextMenu(keys: [key]) }
    }

    @ViewBuilder
    func cell<Content: View>(_ width: CGFloat, last: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: width, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .top)
            .overlay(alignment: .trailing) {
                if !last {
                    Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1)
                }
            }
    }
}
