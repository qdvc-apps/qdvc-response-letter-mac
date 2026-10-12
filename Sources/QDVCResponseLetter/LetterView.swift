import AppKit
import ResponseCore
import SwiftUI

/// The decision letter, with every marked comment highlighted and its ID
/// in the margin. Select text, then Mark as Comment (⌘K) or New Section Here
/// (⇧⌘K). Edit Letter makes it editable; marked comments follow the edits,
/// and Done asks about any whose text was changed or deleted.
struct LetterView: View {
    @Environment(AppModel.self) private var model
    @State private var placed: [PlacedLabel] = []

    var body: some View {
        let editing = model.isEditingLetter
        let current = editing ? nil : model.letter.commentKey(atSourceOffset: model.letterSelection.location)
        let deco = decorations(current: current, edits: editing ? model.letterEdits : [])
        // The letter in a readable, centred column; the bar below spans the
        // page, and can't make it wider than the window.
        GeometryReader { geo in
            VStack(spacing: 0) {
                ReadableColumn {
                    FillingScroll(padding: 0) {
                        HStack(alignment: .top, spacing: 0) {
                            LetterMargin(placed: placed, width: 112 * model.textScale)
                                .frame(maxHeight: .infinity, alignment: .top)
                            LetterTextView(
                                text: editing ? model.letterDraft : model.letter.decisionLetter,
                                isEditing: editing,
                                highlights: deco.highlights,
                                labels: deco.labels,
                                size: model.textSize,
                                reveal: model.revealInLetter.flatMap { model.letter.comments[$0]?.source.first }
                                    .map { NSRange(location: $0.location, length: $0.length) },
                                revealRevision: model.revealRevision,
                                onSelection: { range in
                                    model.letterSelection = range
                                    if range.length > 0 { model.letterSectionChoice = model.inferredSection(for: range) }
                                },
                                onDoubleClickComment: { offset in
                                    guard !model.isEditingLetter else { return }
                                    if let key = model.letter.commentKey(atSourceOffset: offset) { model.openComment(key) }
                                },
                                onEdits: { edits, text in model.recordLetterEdits(edits, text: text) },
                                onPlaced: { placed = $0 }
                            )
                        }
                        // The margin as tall as the letter, so every ID in it
                        // can be clicked.
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(width: geo.size.width)
                .frame(maxHeight: .infinity)
                Divider()
                LetterActionBar(current: current)
                    .frame(width: geo.size.width)
                    .clipped()
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    /// Highlights for the marked comments, and margin labels for comment
    /// IDs and section starts; while editing, carried through the edits so
    /// far.
    func decorations(current: String?, edits: [LetterEdit]) -> (highlights: [LetterHighlight], labels: [GutterLabel]) {
        let ids = model.ids
        let letter = model.letter
        var highlights: [LetterHighlight] = []
        var labels: [GutterLabel] = []
        for section in letter.sections {
            if let a = section.anchor {
                labels.append(GutterLabel(location: Remap.map(offset: a, through: edits), text: section.title, isSection: true,
                                          key: nil))
            }
            for key in section.commentKeys {
                guard let c = letter.comments[key] else { continue }
                for (i, original) in c.source.enumerated() {
                    let r = edits.isEmpty ? original : Remap.map(original, through: edits).range
                    guard r.length > 0 else { continue }
                    highlights.append(LetterHighlight(range: NSRange(location: r.location, length: r.length),
                                                      color: highlightColor(c.triage), strong: key == current))
                    if i == 0 { labels.append(GutterLabel(location: r.location, text: ids[key] ?? "?", isSection: false, key: key)) }
                }
            }
        }
        return (highlights, labels)
    }

    func highlightColor(_ t: Triage) -> NSColor {
        guard model.triageColoursInLetter, t != .none else { return .controlAccentColor }
        return t.nsColor
    }
}

struct LetterActionBar: View {
    @Environment(AppModel.self) private var model
    var current: String?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            bar(compact: false)
            bar(compact: true)
        }
        .controlSize(.regular)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    /// The bar's contents; compact drops the explanations and shortens the
    /// buttons, for narrow windows.
    @ViewBuilder
    func bar(compact: Bool) -> some View {
        @Bindable var model = model
        let sel = model.letterSelection
        HStack(spacing: 10) {
            if model.isEditingLetter {
                Image(systemName: "pencil").foregroundStyle(.tint)
                Text(compact ? "Editing" : "Editing the decision letter. Marked comments follow your edits; if you change or delete one's text, you'll be asked what to do.")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                Button("Cancel") { model.cancelEditingLetter() }
                    .keyboardShortcut(.cancelAction)
                Button("Done") { model.finishEditingLetter() }
                    .buttonStyle(.borderedProminent)
            } else if sel.length > 0 {
                Text(compact ? "\(sel.length)" : "\(sel.length) characters selected").foregroundStyle(.secondary)
                Spacer()
                if !model.letter.sections.isEmpty {
                    Picker(compact ? "" : "Add to", selection: $model.letterSectionChoice) {
                        ForEach(model.letter.sections) { s in Text(s.title).tag(Optional(s.key)) }
                    }
                    .frame(maxWidth: 240)
                }
                Button(compact ? "Section…" : "New Section Here…") {
                    let text = (model.letter.decisionLetter as NSString)
                        .substring(with: NSRange(location: sel.location, length: min(sel.length, 80)))
                    model.sheet = .section(model.newSectionDraft(anchor: sel.location, hint: text))
                }
                .help("Start a section (such as Reviewer 1) at the selected heading (⇧⌘K)")
                Button(compact ? "Mark" : "Mark as Comment") { model.markComment() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.letter.sections.isEmpty)
                    .help("Make the selected text a comment (⌘K)")
            } else if let current, let c = model.letter.comments[current] {
                TriageDot(triage: c.triage)
                CommentID(text: model.id(current))
                if !compact {
                    Text(TextTools.excerpt(c.text, limit: 70)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button(compact ? "Open" : "Open Comment") { model.openComment(current) }
                Button(compact ? "Remove…" : "Remove Comment…") { model.deleteComments([current]) }
                Button(compact ? "Edit" : "Edit Letter") { model.beginEditingLetter() }
            } else {
                if !compact {
                    Text(model.letter.sections.isEmpty
                         ? "Select a heading such as “Reviewer 1” and choose New Section Here (⇧⌘K)."
                         : "Select a comment's text and choose Mark as Comment (⌘K). Double-click a highlighted comment to open it.")
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button(compact ? "Edit" : "Edit Letter") { model.beginEditingLetter() }
                    .help("Edit the decision letter's text; marked comments follow your edits")
            }
        }
    }
}

struct LetterHighlight: Equatable {
    var range: NSRange
    var color: NSColor
    var strong: Bool
}

struct GutterLabel: Equatable {
    var location: Int
    var text: String
    var isSection: Bool
    /// The comment, for an ID.
    var key: String?
}

/// The decision letter's text view: as tall as its text (SwiftUI scrolls
/// it). The margin of IDs beside it is a SwiftUI view (LetterMargin), placed
/// from this view's layout.
final class LetterNSTextView: NSTextView {
    var onDoubleClickAt: ((Int) -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            let point = convert(event.locationInWindow, from: nil)
            let index = characterIndexForInsertion(at: point)
            onDoubleClickAt?(index)
        }
        super.mouseDown(with: event)
    }
}

/// A margin label placed level with its line.
struct PlacedLabel: Identifiable, Equatable {
    var id: String
    var label: GutterLabel
    var y: CGFloat
}

/// The comment IDs and section names, level with their lines; click an ID
/// to open the comment.
struct LetterMargin: View {
    @Environment(AppModel.self) private var model
    var placed: [PlacedLabel]
    var width: CGFloat

    var body: some View {
        let scale = model.textScale
        ZStack(alignment: .topTrailing) {
            Color.clear
            ForEach(placed) { p in
                Group {
                    if p.label.isSection {
                        Text(p.label.text)
                            .font(.system(size: 10 * scale, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .offset(y: p.y - 15 * scale)
                    } else {
                        Button(p.label.text) {
                            if let key = p.label.key { model.openComment(key) }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11 * scale, weight: .medium, design: .monospaced))
                        .help("Respond to \(p.label.text)")
                        .offset(y: p.y + 1)
                    }
                }
                .frame(width: width - 12, alignment: .trailing)
            }
        }
        .frame(width: width)
    }
}

struct LetterTextView: NSViewRepresentable {
    var text: String
    var isEditing: Bool
    var highlights: [LetterHighlight]
    var labels: [GutterLabel]
    var size: CGFloat
    var reveal: NSRange?
    var revealRevision: Int
    var onSelection: (NSRange) -> Void
    var onDoubleClickComment: (Int) -> Void
    /// Edits since the last report, and the text after them.
    var onEdits: ([LetterEdit], String) -> Void
    /// Where the margin labels go (in the text view's coordinates).
    var onPlaced: ([PlacedLabel]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> LetterNSTextView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        let tv = LetterNSTextView(frame: .zero, textContainer: container)
        tv.isEditable = false
        tv.isSelectable = true
        tv.isRichText = false
        tv.isVerticallyResizable = false
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = []
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 6, height: 16)
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.allowsUndo = true
        tv.delegate = context.coordinator
        tv.textStorage?.delegate = context.coordinator
        context.coordinator.parent = self
        tv.onDoubleClickAt = { [weak coordinator = context.coordinator] index in
            coordinator?.parent?.onDoubleClickComment(index)
        }
        apply(to: tv, coordinator: context.coordinator, force: true)
        return tv
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LetterNSTextView, context: Context) -> CGSize? {
        let width = proposedLength(proposal.width, default: 600)
        let offered = proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? 0
        let height = fittingHeight(of: nsView, width: width)
        context.coordinator.place(labels, in: nsView)
        return CGSize(width: width, height: max(height, offered))
    }

    func updateNSView(_ tv: LetterNSTextView, context: Context) {
        context.coordinator.parent = self
        apply(to: tv, coordinator: context.coordinator, force: false)
    }

    private func apply(to tv: LetterNSTextView, coordinator c: Coordinator, force: Bool) {
        if force || isEditing != c.isEditing {
            c.isEditing = isEditing
            tv.isEditable = isEditing
            c.undo.removeAllActions()
            if isEditing && !force { DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) } }
        }
        if force || text != c.text || size != c.size {
            c.recording = false
            defer { c.recording = true }
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineHeightMultiple = 1.15
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: size),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ]
            tv.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attributes))
            tv.font = NSFont.systemFont(ofSize: size)
            tv.typingAttributes = attributes
            c.text = text
            c.size = size
            c.highlights = []
            c.pending = []
        }
        if let lm = tv.layoutManager, highlights != c.highlights {
            let full = NSRange(location: 0, length: (tv.string as NSString).length)
            lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)
            for h in highlights where NSMaxRange(h.range) <= full.length {
                lm.addTemporaryAttribute(.backgroundColor, value: h.color.withAlphaComponent(h.strong ? 0.38 : 0.18),
                                         forCharacterRange: h.range)
            }
            c.highlights = highlights
        }
        c.place(labels, in: tv)
        if revealRevision != c.revealRevision {
            c.revealRevision = revealRevision
            if let reveal, NSMaxRange(reveal) <= (tv.string as NSString).length {
                DispatchQueue.main.async {
                    tv.scrollRangeToVisible(reveal)
                    tv.setSelectedRange(NSRange(location: reveal.location, length: 0))
                    tv.showFindIndicator(for: reveal)
                }
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: LetterTextView?
        var text = ""
        var size: CGFloat = 0
        var highlights: [LetterHighlight] = []
        var revealRevision = -1
        var isEditing = false
        /// Off while the app itself replaces the text.
        var recording = true
        var pending: [LetterEdit] = []
        let undo = UndoManager()
        var placed: [PlacedLabel] = []

        func undoManager(for view: NSTextView) -> UndoManager? { undo }

        /// Works out where each margin label goes, from the laid-out text,
        /// and reports it when it changes.
        func place(_ labels: [GutterLabel], in tv: NSTextView) {
            guard let lm = tv.layoutManager, let tc = tv.textContainer else { return }
            let length = (tv.string as NSString).length
            var result: [PlacedLabel] = []
            if length > 0 {
                lm.ensureLayout(for: tc)
                let originY = tv.textContainerInset.height
                for (i, label) in labels.enumerated() {
                    let ci = max(0, min(label.location, length - 1))
                    let glyph = lm.glyphIndexForCharacter(at: ci)
                    let line = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                    result.append(PlacedLabel(id: "\(i)-\(label.text)", label: label, y: originY + line.minY))
                }
            }
            guard result != placed else { return }
            placed = result
            // Not during a view update.
            DispatchQueue.main.async { [weak self] in self?.parent?.onPlaced(result) }
        }

        /// Records each edit exactly as the text storage reports it: the
        /// edited range is in the new text, so the replaced length is the
        /// edited length minus the change in length.
        nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                                     range editedRange: NSRange, changeInLength delta: Int) {
            guard editedMask.contains(.editedCharacters) else { return }
            let edit = LetterEdit(location: editedRange.location, length: editedRange.length - delta,
                                  replacementLength: editedRange.length)
            MainActor.assumeIsolated {
                guard recording, isEditing else { return }
                pending.append(edit)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard isEditing, let tv = notification.object as? NSTextView, !pending.isEmpty else { return }
            let edits = pending
            pending = []
            text = tv.string
            parent?.onEdits(edits, tv.string)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let range = tv.selectedRange()
            // Defer: SwiftUI state must not change during a view update.
            DispatchQueue.main.async { [weak self] in self?.parent?.onSelection(range) }
        }
    }
}
