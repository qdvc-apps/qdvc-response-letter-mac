import AppKit
import ResponseCore
import SwiftUI

@main
struct ResponseLetterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    init() {
        // Don't reopen windows from the last session: the welcome window
        // (the first scene) decides what opens at launch.
        UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": false])
    }

    var body: some Scene {
        // Shown at launch, like Xcode's and Keynote's welcome windows.
        Window("Welcome to QDVC Response Letter", id: WelcomeWindow.id) {
            WelcomeWindow()
                .environment(model)
                .onAppear { appDelegate.model = model }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // One window, one response letter at a time, like a document.
        Window("QDVC Response Letter", id: MainWindowID.main) {
            ContentView()
                .environment(model)
                .frame(minWidth: 720, minHeight: 520)
                .onAppear { appDelegate.model = model }
        }
        .defaultSize(width: 1360, height: 860)
        .commands {
            ResponseCommands(model: model)
            InspectorCommands()
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run`) rather than
        // from the .app bundle, so the app gets a Dock icon and menu bar.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model?.checkForOutsideChanges()
    }

    func applicationDidResignActive(_ notification: Notification) {
        model?.flushSaves()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.flushSaves()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

struct ResponseCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    private var key: String? { model.selectedCommentKey }
    private var hasTargets: Bool { !model.targetKeys.isEmpty }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Response Letter…") { model.sheet = .newLetter(nil) }
                .keyboardShortcut("n")
            Button("Open Response Letter…") { model.chooseWorkspace() }
                .keyboardShortcut("o")
            Menu("Open Recent") {
                ForEach(model.recentWorkspaces, id: \.self) { url in
                    Button(url.lastPathComponent) { model.open(url) }
                }
                Divider()
                Button("Clear Menu") { model.clearRecent() }
                    .disabled(model.recentWorkspaces.isEmpty)
            }
            Divider()
            Button("Show in Finder") { model.revealInFinder() }
                .disabled(!model.isOpen)
            Button("Close Response Letter") { model.closeWorkspace() }
                .disabled(!model.isOpen)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Export Response Letter…") { model.sheet = .exportLetter }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!model.isOpen)
            Button("Export for Co-authors…") { model.exportDiscussion() }
                .keyboardShortcut("e", modifiers: [.command, .option, .shift])
                .disabled(!model.isOpen)
            Button("Export Comments as CSV…") { model.exportCSV() }
                .disabled(!model.isOpen)
            Divider()
            Button("Edit Decision Letter") { model.beginEditingLetter() }
                .disabled(!model.isOpen || model.isEditingLetter)
            Button("Letter Settings…") { model.sheet = .letterSettings }
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(!model.isOpen)
        }

        CommandGroup(after: .toolbar) {
            Toggle("Large Text", isOn: Binding(get: { model.largeText }, set: { model.largeText = $0 }))
                .keyboardShortcut("=", modifiers: [.command, .option])
            Button("Reload from Disk") { model.checkForOutsideChanges(force: true) }
                .keyboardShortcut("r")
                .disabled(!model.isOpen)
            Divider()
        }

        CommandMenu("Format") {
            Button("Bold") { Platform.send(#selector(EditorTextView.rlToggleBold(_:))) }
                .keyboardShortcut("b")
            Button("Italic") { Platform.send(#selector(EditorTextView.rlToggleItalic(_:))) }
                .keyboardShortcut("i")
            Divider()
            Button("Quoted Text") { Platform.send(#selector(EditorTextView.rlToggleQuote(_:))) }
                .keyboardShortcut("'")
            Button("Bulleted List") { Platform.send(#selector(EditorTextView.rlToggleBullets(_:))) }
                .keyboardShortcut("7", modifiers: [.command, .shift])
            Divider()
            Menu("Insert Variable") {
                ForEach(model.letter.variables) { v in
                    Button("\(v.name) — \(TextTools.excerpt(v.value, limit: 40))") { model.insertVariable(v.key) }
                }
                if !model.letter.variables.isEmpty { Divider() }
                Button("New Variable from Selection…") { model.beginNewVariable() }
            }
            .disabled(!model.isOpen)
            Menu("Insert Cross-reference") {
                CrossReferenceMenuItems(model: model, exclude: key) { model.insertReference($0) }
            }
            .disabled(!model.isOpen)
        }

        CommandMenu("Comment") {
            Menu("Triage") {
                ForEach(Array(Triage.allCases.enumerated()), id: \.element) { i, t in
                    Button(t.menuTitle) { model.setTriage(t) }
                        .keyboardShortcut(KeyEquivalent(Character(String(t == .none ? 0 : i))), modifiers: .command)
                }
            }
            .disabled(!hasTargets)
            Menu("Status") {
                ForEach(Array(Status.allCases.enumerated()), id: \.element) { i, s in
                    Button(s.label) { model.setStatus(s) }
                        .keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: [.command, .option])
                }
            }
            .disabled(!hasTargets)
            Divider()
            Button("Mark as Comment") { model.markComment() }
                .keyboardShortcut("k")
                .disabled(model.selection != .decisionLetter || model.letterSelection.length == 0 || model.isEditingLetter)
            Button("New Section Here…") {
                let text = (model.letter.decisionLetter as NSString)
                    .substring(with: NSRange(location: model.letterSelection.location,
                                             length: min(model.letterSelection.length, 80)))
                model.sheet = .section(model.newSectionDraft(anchor: model.letterSelection.location, hint: text))
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(model.selection != .decisionLetter || model.isEditingLetter)
            Button("New Section…") {
                model.sheet = .section(model.newSectionDraft(anchor: nil, hint: ""))
            }
            .disabled(!model.isOpen)
            Button("New Comment") { model.newComment() }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(!model.isOpen || model.letter.sections.isEmpty)
            Divider()
            Button("Split at Insertion Point") { model.splitAtCursor() }
                .keyboardShortcut("d", modifiers: [.command, .option])
                .disabled(!model.canSplit)
            Button("Merge with Next Comment") { model.mergeWithNext() }
                .keyboardShortcut("j", modifiers: [.command, .option])
                .disabled(!model.canMergeWithNext(key))
            Button("Join Wrapped Lines") { if let key { model.unwrapCommentText(key) } }
                .disabled(key == nil)
            Divider()
            Button("Move Up") { if let key { model.moveComment(key, by: -1) } }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(key == nil)
            Button("Move Down") { if let key { model.moveComment(key, by: 1) } }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(key == nil)
            Divider()
            Button("Previous Comment") { model.step(-1) }
                .keyboardShortcut("[")
                .disabled(!model.isOpen)
            Button("Next Comment") { model.step(1) }
                .keyboardShortcut("]")
                .disabled(!model.isOpen)
            Divider()
            Button("Delete Comment…") { model.deleteComments() }
                .disabled(!hasTargets)
        }

        CommandGroup(before: .windowList) {
            Button("Welcome to QDVC Response Letter") {
                model.welcomeRequested = true
                openWindow(id: WelcomeWindow.id)
            }
            .keyboardShortcut("1", modifiers: [.command, .shift])
            Divider()
        }

        CommandGroup(before: .sidebar) {
            let pages: [(String, SidebarItem)] = [
                ("Overview", .overview), ("Decision Letter", .decisionLetter), ("Triage Editor", .triageEditor),
                ("Response Editor", .responseEditor), ("Opening & Closing", .openingClosing),
                ("Variables", .variables), ("Issues", .issues), ("Traceability", .traceability),
            ]
            ForEach(Array(pages.enumerated()), id: \.offset) { i, page in
                Button(page.0) { model.selection = page.1 }
                    .keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: [.command, .control])
                    .disabled(!model.isOpen)
            }
            Divider()
        }
    }
}

/// Comments by section, for Insert Cross-reference and Add Related.
struct CrossReferenceMenuItems: View {
    let model: AppModel
    var exclude: String?
    var excludeAlso: [String] = []
    var action: (String) -> Void

    var body: some View {
        let ids = model.ids
        ForEach(model.letter.sections) { section in
            Menu(section.title) {
                ForEach(section.commentKeys.filter { $0 != exclude && !excludeAlso.contains($0) }, id: \.self) { k in
                    Button("\(ids[k] ?? "?")  \(TextTools.excerpt(model.letter.comments[k]?.text ?? "", limit: 60))") {
                        action(k)
                    }
                }
            }
            .disabled(section.commentKeys.isEmpty)
        }
    }
}
