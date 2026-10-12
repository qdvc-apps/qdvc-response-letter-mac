import AppKit
import ResponseCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        @Bindable var model = model
        Group {
            if model.isOpen {
                MainView()
            } else {
                WelcomeView()
            }
        }
        .navigationTitle(model.windowTitle)
        .navigationSubtitle(model.isOpen ? model.letter.settings.manuscript : "")
        .onAppear { model.undoManager = undoManager }
        .onChange(of: undoManager) { _, new in model.undoManager = new }
        .sheet(item: $model.sheet) { kind in
            SheetHost(kind: kind)
                .environment(model)
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
            Text("QDVC Response Letter").font(.largeTitle).fontWeight(.semibold)
            Text("Paste a decision letter, mark up the editors' and reviewers' comments, triage them, draft a response to each, and export the response letter as a Word table.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 520)
            HStack(spacing: 12) {
                Button("New Response Letter…") { model.sheet = .newLetter(nil) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                Button("Open…") { model.chooseWorkspace() }
            }
            .controlSize(.large)
            if !model.recentWorkspaces.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent").font(.headline)
                    ForEach(model.recentWorkspaces.prefix(6), id: \.self) { url in
                        Button {
                            model.open(url)
                        } label: {
                            Label(url.lastPathComponent, systemImage: "folder")
                        }
                        .buttonStyle(.link)
                        .help(url.path)
                    }
                }
                .frame(width: 360, alignment: .leading)
                .padding(.top, 8)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Main view

struct MainView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 230, ideal: 290, max: 420)
        } detail: {
            DetailView()
                .safeAreaInset(edge: .top, spacing: 0) {
                    if let notice = model.notice {
                        NoticeBanner(notice: notice) { model.notice = nil }
                    }
                }
        }
        .inspector(isPresented: $model.showInspector) {
            InspectorView()
                .inspectorColumnWidth(min: 240, ideal: 290, max: 400)
        }
        .searchable(text: $model.searchText, placement: .sidebar, prompt: "Search comments")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                FilterMenu()
                Menu {
                    Button("Response Letter (Word)…") { model.sheet = .exportLetter }
                    Button("For Co-authors (Word)…") { model.exportDiscussion() }
                    Button("Comments (CSV)…") { model.exportCSV() }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .help("Export the response letter")
            }
        }
    }
}

struct FilterMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Menu {
            Section("Triage") {
                ForEach(Triage.allCases, id: \.self) { t in
                    Toggle(t.menuTitle, isOn: Binding(
                        get: { model.triageFilter.contains(t) },
                        set: { on in if on { model.triageFilter.insert(t) } else { model.triageFilter.remove(t) } }
                    ))
                }
            }
            Section("Status") {
                ForEach(Status.allCases, id: \.self) { s in
                    Toggle(s.label, isOn: Binding(
                        get: { model.statusFilter.contains(s) },
                        set: { on in if on { model.statusFilter.insert(s) } else { model.statusFilter.remove(s) } }
                    ))
                }
            }
            Divider()
            Button("Show All") {
                model.triageFilter = []
                model.statusFilter = []
                model.searchText = ""
            }
            .disabled(!model.isFiltering)
        } label: {
            Label("Filter", systemImage: model.triageFilter.isEmpty && model.statusFilter.isEmpty
                  ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .help("Show only some comments")
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let ids = model.ids
        let issues = model.issues
        let issueCount = issues.count
        let flagged = Set(issues.filter(\.kind.isBlocking).compactMap(\.commentKey))
        List(selection: $model.selection) {
            Section("Response Letter") {
                Label("Overview", systemImage: "tablecells").tag(SidebarItem.overview)
                Label("Decision Letter", systemImage: "doc.plaintext").tag(SidebarItem.decisionLetter)
                Label("Opening & Closing", systemImage: "text.alignleft").tag(SidebarItem.openingClosing)
                Label("Variables", systemImage: "curlybraces")
                    .badge(model.letter.variables.count)
                    .tag(SidebarItem.variables)
                Label("Issues", systemImage: issueCount == 0 ? "checkmark.seal" : "exclamationmark.triangle")
                    .badge(issueCount)
                    .tag(SidebarItem.issues)
            }
            ForEach(model.letter.sections) { section in
                Section(isExpanded: Binding(
                    get: { !model.collapsedSections.contains(section.key) },
                    set: { open in
                        if open { model.collapsedSections.remove(section.key) } else { model.collapsedSections.insert(section.key) }
                    }
                )) {
                    ForEach(model.visibleKeys(in: section, ids: ids), id: \.self) { key in
                        if let c = model.letter.comments[key] {
                            CommentRow(comment: c, id: ids[key] ?? "?", flagged: flagged.contains(key))
                                .tag(SidebarItem.comment(key))
                                .contextMenu { CommentContextMenu(keys: [key]) }
                        }
                    }
                    .onMove(perform: model.isFiltering ? nil : { from, to in
                        model.moveComments(inSection: section.key, from: from, to: to)
                    })
                } header: {
                    SectionHeader(section: section)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) { ProgressFooter() }
        .overlay {
            if model.letter.sections.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Text("No sections yet").font(.headline)
                    Text("Open the Decision Letter, select a heading such as “Reviewer 1” and choose Comment › New Section Here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding()
                .allowsHitTesting(false)
            }
        }
    }
}

struct SectionHeader: View {
    @Environment(AppModel.self) private var model
    var section: LetterSection

    var body: some View {
        let p = model.letter.progress(keys: section.commentKeys)
        HStack {
            Text(section.title)
            Spacer()
            if p.total > 0 {
                Text("\(p.count(.final))/\(p.total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .help("\(p.count(.final)) of \(p.total) responses final")
            }
        }
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

struct CommentRow: View {
    var comment: Comment
    var id: String
    var flagged: Bool

    var body: some View {
        HStack(spacing: 8) {
            TriageDot(triage: comment.triage)
            CommentID(text: id)
            Text(TextTools.excerpt(comment.text, limit: 80))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 2)
            if flagged {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("This comment's response has a problem; see Issues.")
            }
            StatusIcon(status: comment.status)
        }
    }
}

struct ProgressFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let p = model.letter.progress()
        if p.total > 0 {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: p.fractionDone)
                    .tint(.green)
                Text("\(p.count(.final)) final · \(p.count(.drafted)) drafted · \(p.count(.todo)) to do")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .help("Drafted responses count half")
        }
    }
}

/// Menu items for one or more comments (sidebar, overview).
struct CommentContextMenu: View {
    @Environment(AppModel.self) private var model
    var keys: [String]

    var body: some View {
        if keys.count == 1, let key = keys.first {
            Button("Open") { model.openComment(key) }
            if model.letter.comments[key]?.source.isEmpty == false {
                Button("Show in Decision Letter") {
                    model.selection = .decisionLetter
                    model.revealInLetter = key
                    model.revealRevision += 1
                }
            }
            Divider()
        }
        Menu("Triage") {
            ForEach(Triage.allCases, id: \.self) { t in Button(t.menuTitle) { model.setTriage(t, for: keys) } }
        }
        Menu("Status") {
            ForEach(Status.allCases, id: \.self) { s in Button(s.label) { model.setStatus(s, for: keys) } }
        }
        if keys.count == 1, let key = keys.first {
            Divider()
            Button("Insert Cross-reference to \(model.id(key))") { model.insertReference(key) }
                .disabled(model.activeEditor == nil)
            Button("Merge with Next Comment") { model.mergeWithNext(key) }
                .disabled(!model.canMergeWithNext(key))
            Menu("Move to") {
                ForEach(model.letter.sections) { s in
                    Button(s.title) { model.moveComment(key, toSection: s.key) }
                        .disabled(model.letter.section(ofComment: key)?.key == s.key)
                }
            }
        }
        Divider()
        Button(keys.count == 1 ? "Delete Comment…" : "Delete \(keys.count) Comments…") { model.deleteComments(keys) }
    }
}

// MARK: - Detail

struct DetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.selection {
        case .overview?:
            OverviewView()
        case .decisionLetter?:
            LetterView()
        case .openingClosing?:
            OpeningClosingView()
        case .variables?:
            VariablesView()
        case .issues?:
            IssuesView()
        case .comment(let key)?:
            if model.letter.comments[key] != nil {
                CommentDetailView(key: key).id(key)
            } else {
                ContentUnavailableView("Comment not found", systemImage: "questionmark.square.dashed")
            }
        case nil:
            ContentUnavailableView("Nothing selected", systemImage: "sidebar.left",
                                   description: Text("Choose a comment or a page in the sidebar."))
        }
    }
}

// MARK: - Sheets

struct SheetHost: View {
    var kind: SheetKind

    var body: some View {
        switch kind {
        case .newLetter(let url): NewLetterSheet(folder: url)
        case .letterSettings: LetterSettingsSheet()
        case .section(let draft): SectionSheet(draft: draft)
        case .splitResolution(let result): SplitResolutionSheet(result: result)
        case .exportLetter: ExportSheet()
        case .newVariable(let value): NewVariableSheet(value: value)
        }
    }
}
