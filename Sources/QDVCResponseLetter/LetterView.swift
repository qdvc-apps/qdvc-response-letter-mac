import AppKit
import ResponseCore
import SwiftUI

/// The decision letter, with every marked comment highlighted and its ID
/// in the margin. Select text, then Mark as Comment (⌘K) or New Section Here
/// (⇧⌘K). Edit Letter makes it editable; marked comments follow the edits,
/// and Done asks about any whose text was changed or deleted.
struct LetterView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let editing = model.isEditingLetter
        let current = editing ? nil : model.letter.commentKey(atSourceOffset: model.letterSelection.location)
        let deco = decorations(current: current, edits: editing ? model.letterEdits : [])
        VStack(spacing: 0) {
            LetterTextView(
                text: editing ? model.letterDraft : model.letter.decisionLetter,
                isEditing: editing,
                highlights: deco.highlights,
                labels: deco.labels,
                size: CGFloat(model.editorFontSize),
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
                onEdits: { edits, text in model.recordLetterEdits(edits, text: text) }
            )
            Divider()
            LetterActionBar(current: current)
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
                labels.append(GutterLabel(location: Remap.map(offset: a, through: edits), text: section.title, isSection: true))
            }
            for key in section.commentKeys {
                guard let c = letter.comments[key] else { continue }
                for (i, original) in c.source.enumerated() {
                    let r = edits.isEmpty ? original : Remap.map(original, through: edits).range
                    guard r.length > 0 else { continue }
                    highlights.append(LetterHighlight(range: NSRange(location: r.location, length: r.length),
                                                      color: highlightColor(c.triage), strong: key == current))
                    if i == 0 { labels.append(GutterLabel(location: r.location, text: ids[key] ?? "?", isSection: false)) }
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
        @Bindable var model = model
        let sel = model.letterSelection
        HStack(spacing: 10) {
            if model.isEditingLetter {
                Image(systemName: "pencil").foregroundStyle(.tint)
                Text("Editing the decision letter. Marked comments follow your edits; if you change or delete one's text, you'll be asked what to do.")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                Button("Cancel") { model.cancelEditingLetter() }
                    .keyboardShortcut(.cancelAction)
                Button("Done") { model.finishEditingLetter() }
                    .buttonStyle(.borderedProminent)
            } else if sel.length > 0 {
                Text("\(sel.length) characters selected").foregroundStyle(.secondary)
                Spacer()
                if !model.letter.sections.isEmpty {
                    Picker("Add to", selection: $model.letterSectionChoice) {
                        ForEach(model.letter.sections) { s in Text(s.title).tag(Optional(s.key)) }
                    }
                    .frame(maxWidth: 240)
                }
                Button("New Section Here…") {
                    let text = (model.letter.decisionLetter as NSString)
                        .substring(with: NSRange(location: sel.location, length: min(sel.length, 80)))
                    model.sheet = .section(model.newSectionDraft(anchor: sel.location, hint: text))
                }
                .help("Start a section (such as Reviewer 1) at the selected heading (⇧⌘K)")
                Button("Mark as Comment") { model.markComment() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.letter.sections.isEmpty)
                    .help("Make the selected text a comment (⌘K)")
            } else if let current, let c = model.letter.comments[current] {
                TriageDot(triage: c.triage)
                CommentID(text: model.id(current))
                Text(TextTools.excerpt(c.text, limit: 70)).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button("Open Comment") { model.openComment(current) }
                Button("Remove Comment…") { model.deleteComments([current]) }
                Button("Edit Letter") { model.beginEditingLetter() }
            } else {
                Text(model.letter.sections.isEmpty
                     ? "Select a heading such as “Reviewer 1” and choose New Section Here (⇧⌘K)."
                     : "Select a comment's text and choose Mark as Comment (⌘K). Double-click a highlighted comment to open it.")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                Button("Edit Letter") { model.beginEditingLetter() }
                    .help("Edit the decision letter's text; marked comments follow your edits")
            }
        }
        .controlSize(.regular)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
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
}

final class LetterGutter: NSRulerView {
    var labels: [GutterLabel] = [] {
        didSet { if labels != oldValue { needsDisplay = true } }
    }

    init(textView: NSTextView, scrollView: NSScrollView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 92
    }

    required init(coder: NSCoder) { fatalError("not used") }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = clientView as? NSTextView, let lm = tv.layoutManager else { return }
        let length = (tv.string as NSString).length
        guard length > 0 else { return }
        for label in labels {
            let ci = max(0, min(label.location, length - 1))
            let glyph = lm.glyphIndexForCharacter(at: ci)
            let line = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let y = convert(NSPoint(x: 0, y: line.minY + tv.textContainerOrigin.y), from: tv).y
            let font: NSFont = label.isSection
                ? .systemFont(ofSize: 10, weight: .semibold)
                : .monospacedSystemFont(ofSize: 11, weight: .medium)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: label.isSection ? NSColor.secondaryLabelColor : NSColor.labelColor,
            ]
            var text = label.text as NSString
            if label.isSection, text.length > 14 { text = (text.substring(to: 13) + "…") as NSString }
            let size = text.size(withAttributes: attrs)
            let point = NSPoint(x: ruleThickness - size.width - 8, y: y + (label.isSection ? -size.height - 1 : 1))
            guard point.y + size.height >= rect.minY - 20, point.y <= rect.maxY + 20 else { continue }
            text.draw(at: point, withAttributes: attrs)
        }
    }
}

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

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
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
        tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainerInset = NSSize(width: 14, height: 14)
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.delegate = context.coordinator
        tv.textStorage?.delegate = context.coordinator
        tv.allowsUndo = true
        let scroll = TextScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.documentView = tv
        let gutter = LetterGutter(textView: tv, scrollView: scroll)
        scroll.verticalRulerView = gutter
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        context.coordinator.parent = self
        tv.onDoubleClickAt = { [weak coordinator = context.coordinator] index in
            coordinator?.parent?.onDoubleClickComment(index)
        }
        apply(to: tv, scroll: scroll, coordinator: context.coordinator, force: true)
        return scroll
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        CGSize(width: proposedLength(proposal.width, default: 480), height: proposedLength(proposal.height, default: 300))
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? LetterNSTextView else { return }
        context.coordinator.parent = self
        apply(to: tv, scroll: scroll, coordinator: context.coordinator, force: false)
    }

    private func apply(to tv: NSTextView, scroll: NSScrollView, coordinator c: Coordinator, force: Bool) {
        if force || isEditing != c.isEditing {
            c.isEditing = isEditing
            tv.isEditable = isEditing
            tv.isRichText = false
            c.undo.removeAllActions()
            if isEditing && !force { DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) } }
        }
        if force || text != c.text || size != c.size {
            c.recording = false
            defer { c.recording = true }
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineHeightMultiple = 1.15
            tv.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: size),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ]))
            c.text = text
            c.size = size
            c.highlights = []
            c.pending = []
            tv.typingAttributes = [
                .font: NSFont.systemFont(ofSize: size),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ]
        }
        if let lm = tv.layoutManager, highlights != c.highlights {
            let full = NSRange(location: 0, length: (tv.string as NSString).length)
            lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)
            lm.removeTemporaryAttribute(.underlineStyle, forCharacterRange: full)
            for h in highlights where NSMaxRange(h.range) <= full.length {
                lm.addTemporaryAttribute(.backgroundColor, value: h.color.withAlphaComponent(h.strong ? 0.38 : 0.18),
                                         forCharacterRange: h.range)
            }
            c.highlights = highlights
        }
        (scroll.verticalRulerView as? LetterGutter)?.labels = labels
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

        func undoManager(for view: NSTextView) -> UndoManager? { undo }

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
