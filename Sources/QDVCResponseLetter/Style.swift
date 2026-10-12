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

    /// The menu and help text: "Easy (green)".
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
    var body: some View {
        Text(text).font(.system(.body, design: .monospaced)).fontWeight(.medium)
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
                Text(title).font(.headline)
                Spacer(minLength: 8)
                accessory()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
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
