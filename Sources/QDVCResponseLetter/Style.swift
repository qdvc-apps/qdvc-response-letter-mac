import AppKit
import ResponseCore
import SwiftUI

extension Triage {
    var color: Color {
        switch self {
        case .none: return Color(nsColor: .tertiaryLabelColor)
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
        }
    }

    var nsColor: NSColor {
        switch self {
        case .none: return .tertiaryLabelColor
        case .green: return .systemGreen
        case .yellow: return .systemYellow
        case .red: return .systemRed
        }
    }

    /// The menu and help text: "Trivial (green)".
    var menuTitle: String {
        self == .none ? "Not Triaged" : "\(label) (\(rawValue.capitalized))"
    }
}

extension Status {
    var symbol: String {
        switch self {
        case .todo: return "circle"
        case .drafted: return "circle.lefthalf.filled"
        case .final: return "checkmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .todo: return .secondary
        case .drafted: return .orange
        case .final: return .green
        }
    }
}

/// A filled dot in the triage colour, or a hollow ring when not triaged.
struct TriageDot: View {
    var triage: Triage
    var size: CGFloat = 10

    var body: some View {
        Group {
            if triage == .none {
                Circle().strokeBorder(Color(nsColor: .tertiaryLabelColor), lineWidth: 1.5)
            } else {
                Circle().fill(triage.color)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(triage.label)
    }
}

struct StatusIcon: View {
    var status: Status

    var body: some View {
        Image(systemName: status.symbol)
            .foregroundStyle(status.tint)
            .help(status.label)
            .accessibilityLabel(status.label)
    }
}

/// Four dot buttons for choosing a triage colour.
struct TriageChooser: View {
    var triage: Triage
    var set: (Triage) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Triage.allCases, id: \.self) { t in
                Button {
                    set(t)
                } label: {
                    TriageDot(triage: t, size: 16)
                        .padding(3)
                        .overlay(
                            Circle().strokeBorder(Color.accentColor, lineWidth: triage == t ? 2 : 0)
                        )
                }
                .buttonStyle(.plain)
                .help(t.menuTitle)
            }
        }
    }
}

/// The ID of a comment, in a monospaced font.
struct CommentID: View {
    var text: String
    var size: CGFloat?

    var body: some View {
        Text(text)
            .font(size.map { .system(size: $0, design: .monospaced) } ?? .system(.body, design: .monospaced))
            .fontWeight(.medium)
    }
}

/// A transient message at the top of the window.
struct NoticeBanner: View {
    var notice: Notice
    var dismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: notice.isWarning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(notice.isWarning ? Color.orange : Color.accentColor)
            Text(notice.text).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            Button("Dismiss", action: dismiss).buttonStyle(.borderless).controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct Notice: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var isWarning = false
}

/// A titled pane for the comment editor's split view.
struct Pane<Accessory: View, Content: View>: View {
    var title: String
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(title).font(.headline).lineLimit(1).layoutPriority(1)
                Spacer(minLength: 8)
                accessory()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .clipped()
            Divider()
            content()
        }
    }
}

enum Platform {
    /// Opens the Settings window.
    @MainActor
    static func openSettings() {
        _ = NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate()
    }

    /// Sends an action to the first responder (the focused text view).
    @MainActor
    static func send(_ action: Selector) {
        _ = NSApp.sendAction(action, to: nil, from: nil)
    }
}

// MARK: - Pop-up buttons

/// A choice in a PopUpButton.
struct PopUpItem {
    var title: String
    var image: NSImage?
    var checked: Bool
    var action: () -> Void
}

/// A button with any label that pops up a menu of choices. (A SwiftUI Menu's
/// label on macOS shows only text and SF Symbols, so a drawn triage dot in
/// it simply disappears.)
struct PopUpButton<Label: View>: View {
    var items: [PopUpItem]
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button(action: popUp) {
            label().contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func popUp() {
        guard let event = NSApp.currentEvent, let view = event.window?.contentView else { return }
        let menu = NSMenu()
        for item in items {
            let menuItem = ClosureMenuItem(title: item.title, handler: item.action)
            menuItem.image = item.image
            menuItem.state = item.checked ? .on : .off
            menu.addItem(menuItem)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { handler() }
}

extension TriageDot {
    /// The dot as a small image, for menus.
    @MainActor
    static func image(_ triage: Triage, size: CGFloat = 10) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            if triage == .none {
                NSColor.tertiaryLabelColor.setStroke()
                path.lineWidth = 1.2
                path.stroke()
            } else {
                triage.nsColor.setFill()
                path.fill()
            }
            return true
        }
        return image
    }
}
