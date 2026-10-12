import AppKit
import ResponseCore
import SwiftUI

/// The window shown at launch, as in Xcode and Keynote: the app on the
/// left with New and Open, recent response letters on the right.
struct WelcomeWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var selection: URL?

    static let id = "welcome"

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development build"
    }

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Spacer(minLength: 28)
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 128, height: 128)
                Text("QDVC Response Letter")
                    .font(.system(size: 26, weight: .semibold))
                    .padding(.top, 6)
                Text("Version \(version)")
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                Spacer(minLength: 28)
                VStack(alignment: .leading, spacing: 6) {
                    WelcomeAction(symbol: "plus.square", title: "Create a New Response Letter…",
                                  detail: "Start by pasting a decision letter") {
                        if model.isOpen { proceed() }
                        model.sheet = .newLetter(nil)
                    }
                    WelcomeAction(symbol: "folder", title: "Open an Existing Response Letter…",
                                  detail: "Choose a response letter folder") {
                        model.chooseWorkspace()
                        if model.isOpen { proceed() }
                    }
                }
                .frame(width: 330)
                Spacer(minLength: 28)
                Toggle("Show this window when QDVC Response Letter opens", isOn: $model.showWelcomeAtLaunch)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 16)
            }
            .frame(width: 440)

            Divider()

            VStack(spacing: 0) {
                if model.recentWorkspaces.isEmpty {
                    ContentUnavailableView("No Recent Response Letters", systemImage: "clock",
                                           description: Text("Letters you open appear here."))
                } else {
                    List(selection: $selection) {
                        ForEach(model.recentWorkspaces, id: \.self) { url in
                            RecentRow(url: url).tag(url)
                        }
                    }
                    .listStyle(.sidebar)
                    .contextMenu(forSelectionType: URL.self) { urls in
                        if let url = urls.first {
                            Button("Open") { openRecent(url) }
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            Divider()
                            Button("Remove from List") { model.removeRecent(url) }
                        }
                    } primaryAction: { urls in
                        if let url = urls.first { openRecent(url) }
                    }
                }
                Divider()
                HStack {
                    Text(model.recentWorkspaces.isEmpty ? "" : "Double-click to open")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Clear Recent List") {
                        model.clearRecent()
                        selection = nil
                    }
                    .disabled(model.recentWorkspaces.isEmpty)
                }
                .controlSize(.small)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .frame(width: 340)
        }
        .frame(height: 460)
        .ignoresSafeArea()
        // Sheets and alerts show here only while no letter is open; with a
        // letter open, the main window shows them.
        .sheet(item: model.isOpen ? .constant(nil) : $model.sheet) { kind in
            SheetHost(kind: kind).environment(model)
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { !model.isOpen && model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onAppear {
            model.startUp()
            if model.isOpen && !model.welcomeRequested { proceed() }
            model.welcomeRequested = false
        }
        .onChange(of: model.workspaceURL) { _, url in
            if url != nil { proceed() }
        }
    }

    private func openRecent(_ url: URL) {
        model.open(url)
        if model.isOpen { proceed() }
    }

    /// Hands over to the main window.
    private func proceed() {
        openWindow(id: MainWindowID.main)
        // Close this one a moment later, so the app never has no window
        // (which would quit it).
        DispatchQueue.main.async { dismissWindow(id: Self.id) }
    }
}

enum MainWindowID {
    static let main = "main"
}

/// A big row on the left of the welcome window.
struct WelcomeAction: View {
    var symbol: String
    var title: String
    var detail: String
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 22))
                    .foregroundStyle(.tint)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).fontWeight(.medium)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Color.primary.opacity(0.07) : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A recent response letter: its folder name, title and manuscript, and
/// where it is.
struct RecentRow: View {
    var url: URL

    var body: some View {
        let summary = Workspace.summary(url)
        HStack(spacing: 10) {
            Image(systemName: summary == nil ? "questionmark.folder" : "folder.fill")
                .font(.system(size: 22))
                .foregroundStyle(summary == nil ? Color.secondary : Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent).fontWeight(.medium).lineLimit(1)
                if let summary, !summary.manuscript.isEmpty {
                    Text(summary.manuscript).font(.caption).lineLimit(1)
                }
                Text(summary == nil ? "Not found" : (url.path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 3)
        .help(url.path)
    }
}
