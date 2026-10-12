import AppKit
import ResponseCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        @Bindable var model = model
        Group {
            if model.isOpen {
                MainView()
            } else {
                Color.clear
            }
        }
        .navigationTitle(model.windowTitle)
        .navigationSubtitle(model.isOpen ? model.letter.settings.manuscript : "")
        .onAppear {
            model.undoManager = undoManager
            if !model.isOpen { showWelcome() }
        }
        .onChange(of: undoManager) { _, new in model.undoManager = new }
        .onChange(of: model.workspaceURL) { _, url in
            if url == nil { showWelcome() }
        }
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

extension ContentView {
    /// With no letter open, the welcome window takes over.
    func showWelcome() {
        openWindow(id: WelcomeWindow.id)
        DispatchQueue.main.async { dismissWindow(id: MainWindowID.main) }
    }
}

// MARK: - Main view

struct MainView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 320)
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
                .inspectorColumnWidth(min: 240, ideal: 300, max: 440)
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search comments")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: $model.largeText) {
                    Label("Large Text", systemImage: "textformat.size")
                }
                .toggleStyle(.button)
                .help("Large text in the letter, the tables and the editors, for sharing your screen (⌥⌘=)")
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

/// The pages, in the order of the work: the decision letter, triage,
/// responses, the opening and closing; then tools.
struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let issueCount = model.issues.count
        let p = model.letter.progress()
        List(selection: $model.selection) {
            Section("Response Letter") {
                Label("Overview", systemImage: "tablecells").tag(SidebarItem.overview)
            }
            Section("Workflow") {
                Label("Decision Letter", systemImage: "doc.plaintext").tag(SidebarItem.decisionLetter)
                Label("Triage the comments", systemImage: "flag")
                    .badge(p.count(.none))
                    .help("\(p.count(.none)) comment(s) not yet triaged")
                    .tag(SidebarItem.triageEditor)
                Label("Respond to the comments", systemImage: "text.bubble")
                    .badge(p.count(.todo))
                    .help("\(p.count(.todo)) response(s) still to do")
                    .tag(SidebarItem.responseEditor)
                Label("Opening & Closing", systemImage: "text.alignleft").tag(SidebarItem.openingClosing)
            }
            Section("Tools") {
                Label("Variables", systemImage: "curlybraces")
                    .badge(model.letter.variables.count)
                    .tag(SidebarItem.variables)
                Label("Issues", systemImage: issueCount == 0 ? "checkmark.seal" : "exclamationmark.triangle")
                    .badge(issueCount)
                    .tag(SidebarItem.issues)
                Label("Traceability", systemImage: "point.3.connected.trianglepath.dotted")
                    .tag(SidebarItem.traceability)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) { ProgressFooter() }
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
            if model.selection != .responseEditor {
                Button("Respond to This Comment") { model.openComment(key) }
            }
            if model.selection != .triageEditor {
                Button("Triage This Comment") { model.openInTriage(key) }
            }
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
        page
            .frame(minWidth: 300, maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
            .clipped()
    }

    @ViewBuilder
    private var page: some View {
        switch model.selection {
        case .overview?:
            OverviewView()
        case .decisionLetter?:
            LetterView()
        case .triageEditor?:
            TriageEditorView()
        case .responseEditor?:
            ResponseEditorView()
        case .traceability?:
            TraceabilityView()
        case .openingClosing?:
            OpeningClosingView()
        case .variables?:
            VariablesView()
        case .issues?:
            IssuesView()
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
        case .letterRevision(let revision): LetterRevisionSheet(revision: revision)
        }
    }
}
