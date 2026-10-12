import AppKit
import ResponseCore
import SwiftUI

// The response editor is an NSTextView (TextKit 1, so attachment cells draw
// the Variable and Cross-reference "pills") over an attributed string that
// mirrors the markup: custom attributes carry bold, italic and the paragraph
// kind, and MarkupConverter turns one into the other. docs/MAINTENANCE.md
// §Editors explains the design.

extension NSAttributedString.Key {
    static let rlBold = NSAttributedString.Key("org.qdvc.rl.bold")
    static let rlItalic = NSAttributedString.Key("org.qdvc.rl.italic")
    static let rlBlock = NSAttributedString.Key("org.qdvc.rl.block")
}

extension NSPasteboard.PasteboardType {
    /// Response markup, so copy and paste between responses keeps
    /// formatting, Variables and Cross-references.
    static let responseMarkup = NSPasteboard.PasteboardType("org.qdvc.response-letter.markup")
}

/// How a token looks.
enum TokenState {
    case variable, reference, pending, broken

    var color: NSColor {
        switch self {
        case .variable: return .systemTeal
        case .reference: return .systemIndigo
        case .pending: return .systemOrange
        case .broken: return .systemRed
        }
    }
}

struct TokenLook {
    var text: String
    var state: TokenState
    var help: String
}

/// Supplies the current text of tokens; shared by an editor's pills.
@MainActor
final class TokenProvider {
    var look: (Token) -> TokenLook = { _ in TokenLook(text: "?", state: .broken, help: "") }
}

// MARK: - Pills

final class TokenAttachment: NSTextAttachment {
    let token: Token

    @MainActor
    init(token: Token, provider: TokenProvider, font: NSFont) {
        self.token = token
        super.init(data: nil, ofType: nil)
        attachmentCell = TokenCell(token: token, provider: provider, font: font)
    }

    required init?(coder: NSCoder) { fatalError("not used") }
}

final class TokenCell: NSTextAttachmentCell {
    let token: Token
    weak var provider: TokenProvider?
    let textFont: NSFont

    @MainActor
    init(token: Token, provider: TokenProvider, font: NSFont) {
        self.token = token
        self.provider = provider
        self.textFont = font
        super.init(textCell: "")
    }

    required init(coder: NSCoder) { fatalError("not used") }

    var look: TokenLook {
        MainActor.assumeIsolated {
            provider?.look(token) ?? TokenLook(text: "?", state: .broken, help: "")
        }
    }

    override func cellSize() -> NSSize {
        let size = (look.text as NSString).size(withAttributes: [.font: textFont])
        return NSSize(width: ceil(size.width) + 12, height: ceil(textFont.ascender - textFont.descender) + 2)
    }

    override func cellBaselineOffset() -> NSPoint {
        NSPoint(x: 0, y: floor(textFont.descender) - 1)
    }

    override func wantsToTrackMouse() -> Bool { false }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let look = self.look
        let rect = cellFrame.insetBy(dx: 1, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2.6, yRadius: rect.height / 2.6)
        look.state.color.withAlphaComponent(look.state == .pending || look.state == .broken ? 0.30 : 0.18).setFill()
        path.fill()
        look.state.color.withAlphaComponent(0.55).setStroke()
        path.lineWidth = look.state == .pending ? 1.5 : 0.75
        path.stroke()
        let attrs: [NSAttributedString.Key: Any] = [.font: textFont, .foregroundColor: NSColor.labelColor]
        // Text views are flipped, so y grows downwards from the cell's top.
        (look.text as NSString).draw(at: NSPoint(x: cellFrame.minX + 6, y: cellFrame.minY + 1), withAttributes: attrs)
    }
}

// MARK: - Layout manager: bullets and quote bars

final class MarkupLayoutManager: NSLayoutManager {
    /// Draw every paragraph as a bullet (the ideas editor).
    var allBullets = false
    var bulletFont = NSFont.systemFont(ofSize: 13)

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, storage.length > 0 else { return }
        let string = storage.string as NSString
        enumerateLineFragments(forGlyphRange: glyphsToShow) { rect, usedRect, _, glyphRange, _ in
            let ci = self.characterIndexForGlyph(at: glyphRange.location)
            guard ci < storage.length else { return }
            let block: BlockKind = self.allBullets ? .bullet
                : (storage.attribute(.rlBlock, at: ci, effectiveRange: nil) as? String).flatMap(BlockKind.init) ?? .normal
            switch block {
            case .normal:
                break
            case .quote:
                let bar = NSRect(x: origin.x + rect.minX + 4, y: origin.y + rect.minY, width: 3, height: rect.height)
                NSColor.systemIndigo.withAlphaComponent(0.45).setFill()
                NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
            case .bullet:
                let startsParagraph = ci == 0 || string.character(at: ci - 1) == 10
                guard startsParagraph else { return }
                let attrs: [NSAttributedString.Key: Any] = [.font: self.bulletFont, .foregroundColor: NSColor.secondaryLabelColor]
                ("•" as NSString).draw(at: NSPoint(x: origin.x + rect.minX + 5, y: origin.y + usedRect.minY), withAttributes: attrs)
            }
        }
    }
}

// MARK: - Converting between markup and attributed strings

@MainActor
enum MarkupConverter {
    static func font(bold: Bool, italic: Bool, size: CGFloat) -> NSFont {
        var font = NSFont.systemFont(ofSize: size)
        if bold { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
        if italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        return font
    }

    nonisolated static func paragraphStyle(_ block: BlockKind, bulleted: Bool = false) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 5
        style.lineHeightMultiple = 1.1
        if block != .normal || bulleted {
            style.firstLineHeadIndent = 18
            style.headIndent = 18
        }
        return style
    }

    static func attributes(style: InlineStyle, block: BlockKind, size: CGFloat) -> [NSAttributedString.Key: Any] {
        [
            .font: font(bold: style.bold, italic: style.italic, size: size),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle(block),
            .rlBold: style.bold,
            .rlItalic: style.italic,
            .rlBlock: block.rawValue,
        ]
    }

    static func tokenString(_ token: Token, style: InlineStyle, block: BlockKind, size: CGFloat,
                            provider: TokenProvider) -> NSAttributedString {
        let attachment = TokenAttachment(token: token, provider: provider, font: NSFont.systemFont(ofSize: size - 1))
        let s = NSMutableAttributedString(attachment: attachment)
        s.addAttributes(attributes(style: style, block: block, size: size), range: NSRange(location: 0, length: s.length))
        return s
    }

    static func attributed(_ rich: RichText, size: CGFloat, provider: TokenProvider) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for (i, p) in rich.paragraphs.enumerated() {
            for inline in p.inlines {
                switch inline {
                case .text(let t, let s):
                    out.append(NSAttributedString(string: t, attributes: attributes(style: s, block: p.block, size: size)))
                case .token(let t, let s):
                    out.append(tokenString(t, style: s, block: p.block, size: size, provider: provider))
                }
            }
            if i < rich.paragraphs.count - 1 {
                out.append(NSAttributedString(string: "\n", attributes: attributes(style: .plain, block: p.block, size: size)))
            }
        }
        return out
    }

    /// The markup model of an attributed string made by this editor.
    static func richText(_ attr: NSAttributedString) -> RichText {
        let ns = attr.string as NSString
        guard ns.length > 0 else { return .empty }
        var paragraphs: [RichParagraph] = []
        var start = 0
        while start <= ns.length {
            let nl = ns.range(of: "\n", options: [], range: NSRange(location: start, length: ns.length - start))
            let end = nl.location == NSNotFound ? ns.length : nl.location
            let range = NSRange(location: start, length: end - start)
            let probe = range.length > 0 ? range.location : (end < ns.length ? end : -1)
            let block = probe >= 0
                ? (attr.attribute(.rlBlock, at: probe, effectiveRange: nil) as? String).flatMap(BlockKind.init) ?? .normal
                : .normal
            var inlines: [Inline] = []
            if range.length > 0 {
                attr.enumerateAttributes(in: range, options: []) { attrs, sub, _ in
                    let style = InlineStyle(bold: attrs[.rlBold] as? Bool ?? false, italic: attrs[.rlItalic] as? Bool ?? false)
                    if let token = attrs[.attachment] as? TokenAttachment {
                        inlines.append(.token(token.token, style))
                        return
                    }
                    let text = ns.substring(with: sub).replacingOccurrences(of: "\u{FFFC}", with: "")
                    if !text.isEmpty { inlines.append(.text(text, style)) }
                }
            }
            paragraphs.append(RichParagraph(block: block, inlines: coalesce(inlines)))
            if nl.location == NSNotFound { break }
            start = end + 1
        }
        return RichText(paragraphs: paragraphs)
    }

    static func coalesce(_ inlines: [Inline]) -> [Inline] {
        var out: [Inline] = []
        for inline in inlines {
            if case .text(let t, let s) = inline, case .text(let pt, let ps)? = out.last, ps == s {
                out[out.count - 1] = .text(pt + t, s)
            } else {
                out.append(inline)
            }
        }
        return out
    }

    /// Plain text with pills replaced by what they say.
    static func displayString(_ attr: NSAttributedString) -> String {
        var out = ""
        let ns = attr.string as NSString
        attr.enumerateAttributes(in: NSRange(location: 0, length: attr.length), options: []) { attrs, range, _ in
            if let token = attrs[.attachment] as? TokenAttachment,
               let cell = token.attachmentCell as? TokenCell {
                out += cell.look.text
            } else {
                out += ns.substring(with: range).replacingOccurrences(of: "\u{FFFC}", with: "")
            }
        }
        return out
    }
}

// MARK: - The text view

final class EditorTextView: NSTextView, NSViewToolTipOwner {
    /// Rich: formatting, pills and markup on the pasteboard. Plain: text only.
    var isRichEditor = false
    var placeholder: String?
    var baseSize: CGFloat = 13
    var tokenProvider: TokenProvider?
    var onFocus: ((EditorTextView) -> Void)?
    var onTokenDoubleClick: ((Token) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocus?(self) }
        return ok
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let placeholder, string.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: baseSize),
                .foregroundColor: NSColor.placeholderTextColor,
            ]
            let x = textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 5)
                + ((layoutManager as? MarkupLayoutManager)?.allBullets == true ? 18 : 0)
            (placeholder as NSString).draw(at: NSPoint(x: x, y: textContainerOrigin.y), withAttributes: attrs)
        }
    }

    override func didChangeText() {
        super.didChangeText()
        if string.isEmpty { needsDisplay = true }
    }

    // MARK: Pasteboard

    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
        isRichEditor ? [.responseMarkup, .string] : [.string]
    }

    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        guard isRichEditor else { return super.writeSelection(to: pboard, types: types) }
        pboard.declareTypes(types, owner: nil)
        var wrote = false
        for type in types where writeSelection(to: pboard, type: type) { wrote = true }
        return wrote
    }

    override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard isRichEditor, let storage = textStorage else { return super.writeSelection(to: pboard, type: type) }
        let range = selectedRange()
        guard range.length > 0 else { return false }
        let sub = storage.attributedSubstring(from: range)
        switch type {
        case .responseMarkup:
            return pboard.setString(MarkupConverter.richText(sub).markup, forType: type)
        case .string:
            return pboard.setString(MarkupConverter.displayString(sub), forType: .string)
        default:
            return super.writeSelection(to: pboard, type: type)
        }
    }

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        isRichEditor ? [.responseMarkup, .string] : [.string]
    }

    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if isRichEditor, type == .responseMarkup, let markup = pboard.string(forType: type), let provider = tokenProvider {
            let attr = MarkupConverter.attributed(RichText(markup: markup), size: baseSize, provider: provider)
            insertText(attr, replacementRange: selectedRange())
            return true
        }
        if type == .string, let text = pboard.string(forType: .string) {
            // Plain text takes the formatting where it lands.
            insertText(text, replacementRange: selectedRange())
            return true
        }
        return super.readSelection(from: pboard, type: type)
    }

    // MARK: Formatting (Format menu and the format bar)

    func restyle(_ range: NSRange, _ change: (inout [NSAttributedString.Key: Any]) -> Void) {
        guard let storage = textStorage, range.length > 0, shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        storage.enumerateAttributes(in: range, options: []) { attrs, sub, _ in
            var a = attrs
            change(&a)
            let bold = a[.rlBold] as? Bool ?? false
            let italic = a[.rlItalic] as? Bool ?? false
            if a[.attachment] == nil {
                a[.font] = MarkupConverter.font(bold: bold, italic: italic, size: baseSize)
            }
            storage.setAttributes(a, range: sub)
        }
        storage.endEditing()
        didChangeText()
    }

    func toggleTrait(_ key: NSAttributedString.Key) {
        guard isRichEditor else { return }
        let range = selectedRange()
        if range.length == 0 {
            var t = typingAttributes
            let on = !(t[key] as? Bool ?? false)
            t[key] = on
            t[.font] = MarkupConverter.font(bold: t[.rlBold] as? Bool ?? false, italic: t[.rlItalic] as? Bool ?? false,
                                            size: baseSize)
            typingAttributes = t
            return
        }
        var allOn = true
        textStorage?.enumerateAttribute(key, in: range, options: []) { value, _, stop in
            if !(value as? Bool ?? false) { allOn = false; stop.pointee = true }
        }
        restyle(range) { $0[key] = !allOn }
    }

    func toggleBlock(_ block: BlockKind) {
        guard isRichEditor, let storage = textStorage else { return }
        let ns = storage.string as NSString
        let range = ns.paragraphRange(for: selectedRange())
        if range.length == 0 {
            var t = typingAttributes
            let current = (t[.rlBlock] as? String).flatMap(BlockKind.init) ?? .normal
            let new: BlockKind = current == block ? .normal : block
            t[.rlBlock] = new.rawValue
            t[.paragraphStyle] = MarkupConverter.paragraphStyle(new)
            typingAttributes = t
            needsDisplay = true
            return
        }
        var all = true
        storage.enumerateAttribute(.rlBlock, in: range, options: []) { value, _, stop in
            if (value as? String) != block.rawValue { all = false; stop.pointee = true }
        }
        let new: BlockKind = all ? .normal : block
        restyle(range) { a in
            a[.rlBlock] = new.rawValue
            a[.paragraphStyle] = MarkupConverter.paragraphStyle(new)
        }
        var t = typingAttributes
        t[.rlBlock] = new.rawValue
        t[.paragraphStyle] = MarkupConverter.paragraphStyle(new)
        typingAttributes = t
        needsDisplay = true
    }

    @objc func rlToggleBold(_ sender: Any?) { toggleTrait(.rlBold) }
    @objc func rlToggleItalic(_ sender: Any?) { toggleTrait(.rlItalic) }
    @objc func rlToggleQuote(_ sender: Any?) { toggleBlock(.quote) }
    @objc func rlToggleBullets(_ sender: Any?) { toggleBlock(.bullet) }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(rlToggleBold(_:)), #selector(rlToggleItalic(_:)),
             #selector(rlToggleQuote(_:)), #selector(rlToggleBullets(_:)):
            return isRichEditor && isEditable
        default:
            return super.validateUserInterfaceItem(item)
        }
    }

    /// Inserts a Variable or Cross-reference at the insertion point (or in
    /// place of the selection).
    func insertToken(_ token: Token) {
        guard isRichEditor, let provider = tokenProvider else { return }
        let t = typingAttributes
        let style = InlineStyle(bold: t[.rlBold] as? Bool ?? false, italic: t[.rlItalic] as? Bool ?? false)
        let block = (t[.rlBlock] as? String).flatMap(BlockKind.init) ?? .normal
        let s = MarkupConverter.tokenString(token, style: style, block: block, size: baseSize, provider: provider)
        window?.makeFirstResponder(self)
        insertText(s, replacementRange: selectedRange())
    }

    var selectedPlainText: String {
        guard let storage = textStorage else { return "" }
        let range = selectedRange()
        guard range.length > 0 else { return "" }
        return MarkupConverter.displayString(storage.attributedSubstring(from: range))
    }

    /// Redraws pills after Variables or numbering change.
    func refreshTokens() {
        guard let lm = layoutManager, let storage = textStorage else { return }
        lm.invalidateLayout(forCharacterRange: NSRange(location: 0, length: storage.length), actualCharacterRange: nil)
        needsDisplay = true
    }

    /// The Variable or Cross-reference under the mouse, for tooltips.
    func token(at point: NSPoint) -> Token? {
        guard let lm = layoutManager, let tc = textContainer, let storage = textStorage, storage.length > 0 else { return nil }
        let p = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = lm.glyphIndex(for: p, in: tc)
        let rect = lm.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: tc)
        guard rect.contains(p) else { return nil }
        let ci = lm.characterIndexForGlyph(at: glyph)
        guard ci < storage.length else { return nil }
        return (storage.attribute(.attachment, at: ci, effectiveRange: nil) as? TokenAttachment)?.token
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint,
              userData data: UnsafeMutableRawPointer?) -> String {
        guard let token = token(at: point), let provider = tokenProvider else { return "" }
        return provider.look(token).help
    }
}

/// Lets SwiftUI views (the format bar, sheets) reach the text view of an
/// editor they contain.
@MainActor
final class EditorHandle {
    weak var textView: EditorTextView?
}

/// A scroll view whose text view is always exactly as wide as the visible
/// area, so text wraps at the pane's edge, and at least as tall, so a click
/// anywhere in an empty pane starts typing. (Autoresizing alone keeps
/// whatever width difference the text view started with: a text view made
/// 400 points wide inside a scroll view that SwiftUI then sized from zero
/// stayed 400 points too wide, and its lines ran off the right.)
final class TextScrollView: NSScrollView {
    override func tile() {
        super.tile()
        guard let tv = documentView as? NSTextView else { return }
        let size = contentSize
        if tv.minSize.height != size.height {
            tv.minSize = NSSize(width: 0, height: size.height)
        }
        if abs(tv.frame.width - size.width) > 0.5 || tv.frame.height < size.height {
            tv.setFrameSize(NSSize(width: size.width, height: max(tv.frame.height, size.height)))
            if let container = tv.textContainer, let layout = tv.layoutManager {
                layout.ensureLayout(for: container)
                tv.sizeToFit()
            }
        }
    }
}

@MainActor
func makeEditorScrollView(bulleted: Bool, rich: Bool, size: CGFloat) -> (NSScrollView, EditorTextView) {
    let storage = NSTextStorage()
    let layout = MarkupLayoutManager()
    layout.allBullets = bulleted
    layout.bulletFont = NSFont.systemFont(ofSize: size)
    storage.addLayoutManager(layout)
    let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
    container.widthTracksTextView = true
    layout.addTextContainer(container)
    // Zero-sized to start with: TextScrollView gives it the visible width.
    let tv = EditorTextView(frame: .zero, textContainer: container)
    tv.isRichEditor = rich
    tv.baseSize = size
    tv.minSize = .zero
    tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    tv.isVerticallyResizable = true
    tv.isHorizontallyResizable = false
    tv.autoresizingMask = [.width]
    tv.textContainerInset = NSSize(width: 8, height: 8)
    tv.isRichText = rich
    tv.importsGraphics = false
    tv.allowsUndo = true
    tv.usesFindBar = true
    tv.isIncrementalSearchingEnabled = true
    tv.isContinuousSpellCheckingEnabled = true
    tv.drawsBackground = true
    tv.backgroundColor = .textBackgroundColor
    tv.font = NSFont.systemFont(ofSize: size)
    tv.textColor = .labelColor
    let style = MarkupConverter.paragraphStyle(.normal, bulleted: bulleted)
    tv.defaultParagraphStyle = style
    tv.typingAttributes = rich
        ? MarkupConverter.attributes(style: .plain, block: .normal, size: size)
        : [.font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.labelColor, .paragraphStyle: style]
    // One tooltip area over the whole text; it only says something over a pill.
    tv.addToolTip(NSRect(x: 0, y: 0, width: 100_000, height: 1_000_000), owner: tv, userData: nil)
    let scroll = TextScrollView()
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = false
    scroll.borderType = .noBorder
    scroll.drawsBackground = true
    scroll.backgroundColor = .textBackgroundColor
    scroll.documentView = tv
    return (scroll, tv)
}

// MARK: - SwiftUI wrappers

/// A proposed length, or a modest default when SwiftUI asks for an ideal
/// size. Text views report this instead of their content's width, so a long
/// paragraph never widens the window.
func proposedLength(_ value: CGFloat?, default fallback: CGFloat) -> CGFloat {
    guard let value, value.isFinite else { return fallback }
    return value
}

/// The response (and opening/closing) editor.
struct RichTextEditor: NSViewRepresentable {
    var markup: String
    var size: CGFloat
    /// Changes when Variables or numbering change, to redraw pills.
    var tokenSignature: Int
    var look: (Token) -> TokenLook
    var handle: EditorHandle?
    var placeholder: String?
    var onChange: (String) -> Void
    var onFocus: ((EditorTextView) -> Void)?
    var onTokenDoubleClick: ((Token) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let (scroll, tv) = makeEditorScrollView(bulleted: false, rich: true, size: size)
        let c = context.coordinator
        c.parent = self
        c.provider.look = look
        tv.tokenProvider = c.provider
        tv.placeholder = placeholder
        tv.delegate = c
        tv.textStorage?.delegate = c
        tv.onFocus = { view in c.parent?.onFocus?(view) }
        tv.onTokenDoubleClick = { token in c.parent?.onTokenDoubleClick?(token) }
        c.load(markup, into: tv, size: size)
        c.signature = tokenSignature
        handle?.textView = tv
        return scroll
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        CGSize(width: proposedLength(proposal.width, default: 320), height: proposedLength(proposal.height, default: 160))
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? EditorTextView else { return }
        let c = context.coordinator
        c.parent = self
        c.provider.look = look
        handle?.textView = tv
        tv.placeholder = placeholder
        if size != tv.baseSize || markup != c.lastMarkup {
            tv.baseSize = size
            c.load(markup, into: tv, size: size)
            c.signature = tokenSignature
        } else if tokenSignature != c.signature {
            c.signature = tokenSignature
            tv.refreshTokens()
        }
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.undo.removeAllActions()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: RichTextEditor?
        let provider = TokenProvider()
        let undo = UndoManager()
        var lastMarkup = ""
        var signature = 0
        var loading = false

        func load(_ markup: String, into tv: EditorTextView, size: CGFloat) {
            loading = true
            defer { loading = false }
            let selection = tv.selectedRange()
            let attr = MarkupConverter.attributed(RichText(markup: markup), size: size, provider: provider)
            tv.textStorage?.setAttributedString(attr)
            let length = (tv.string as NSString).length
            tv.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
            lastMarkup = markup
            undo.removeAllActions()
        }

        func undoManager(for view: NSTextView) -> UndoManager? { undo }

        func textDidChange(_ notification: Notification) {
            guard !loading, let tv = notification.object as? EditorTextView, let storage = tv.textStorage else { return }
            let markup = MarkupConverter.richText(storage).markup
            guard markup != lastMarkup else { return }
            lastMarkup = markup
            parent?.onChange(markup)
        }

        /// Keeps each paragraph's kind uniform after edits that join or
        /// split paragraphs.
        nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                                     range editedRange: NSRange, changeInLength delta: Int) {
            guard editedMask.contains(.editedCharacters), textStorage.length > 0 else { return }
            let ns = textStorage.string as NSString
            let safe = NSRange(location: min(editedRange.location, ns.length), length: 0)
            let paragraphs = ns.paragraphRange(for: NSRange(location: safe.location,
                                                            length: min(editedRange.length, ns.length - safe.location)))
            var p = paragraphs.location
            while p < NSMaxRange(paragraphs) {
                let para = ns.paragraphRange(for: NSRange(location: p, length: 0))
                guard para.length > 0 else { break }
                let raw = textStorage.attribute(.rlBlock, at: para.location, effectiveRange: nil) as? String ?? "normal"
                var uniform = true
                textStorage.enumerateAttribute(.rlBlock, in: para, options: []) { value, _, stop in
                    if (value as? String ?? "normal") != raw { uniform = false; stop.pointee = true }
                }
                if !uniform {
                    let block = BlockKind(rawValue: raw) ?? .normal
                    let style = MarkupConverter.paragraphStyle(block)
                    textStorage.addAttributes([.rlBlock: raw, .paragraphStyle: style], range: para)
                }
                p = NSMaxRange(para)
            }
        }

        /// Return in an empty bullet or quote ends the list; Tab is kept
        /// for moving between fields.
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)), let storage = textView.textStorage else { return false }
            let ns = storage.string as NSString
            let sel = textView.selectedRange()
            let para = ns.paragraphRange(for: NSRange(location: sel.location, length: 0))
            let content = ns.substring(with: para).trimmingCharacters(in: .newlines)
            let attrs = textView.typingAttributes
            let block = (attrs[.rlBlock] as? String).flatMap(BlockKind.init) ?? .normal
            if block != .normal && content.isEmpty && sel.length == 0 {
                (textView as? EditorTextView)?.toggleBlock(block)
                return true
            }
            return false
        }

        func textView(_ textView: NSTextView, doubleClickedOn cell: NSTextAttachmentCellProtocol, in cellFrame: NSRect, at charIndex: Int) {
            if let token = (cell as? TokenCell)?.token { parent?.onTokenDoubleClick?(token) }
        }
    }
}

/// A plain-text editor: the comment's text, or the ideas (one dot point per
/// line, drawn as bullets).
struct PlainTextEditor: NSViewRepresentable {
    var text: String
    var size: CGFloat
    var bulleted = false
    var placeholder: String?
    var onChange: (String) -> Void
    var onSelectionChange: ((NSRange) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let (scroll, tv) = makeEditorScrollView(bulleted: bulleted, rich: false, size: size)
        context.coordinator.parent = self
        tv.placeholder = placeholder
        tv.delegate = context.coordinator
        context.coordinator.load(text, into: tv)
        return scroll
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        CGSize(width: proposedLength(proposal.width, default: 320), height: proposedLength(proposal.height, default: 100))
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? EditorTextView else { return }
        context.coordinator.parent = self
        tv.placeholder = placeholder
        if text != context.coordinator.lastText || size != tv.baseSize {
            tv.baseSize = size
            tv.font = NSFont.systemFont(ofSize: size)
            context.coordinator.load(text, into: tv)
        }
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.undo.removeAllActions()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlainTextEditor?
        let undo = UndoManager()
        var lastText = ""
        var loading = false

        func load(_ text: String, into tv: EditorTextView) {
            loading = true
            defer { loading = false }
            let selection = tv.selectedRange()
            tv.string = text
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: tv.baseSize),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: MarkupConverter.paragraphStyle(.normal, bulleted: parent?.bulleted ?? false),
            ]
            tv.textStorage?.setAttributes(attrs, range: NSRange(location: 0, length: (text as NSString).length))
            tv.typingAttributes = attrs
            tv.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
            lastText = text
            undo.removeAllActions()
        }

        func undoManager(for view: NSTextView) -> UndoManager? { undo }

        func textDidChange(_ notification: Notification) {
            guard !loading, let tv = notification.object as? NSTextView else { return }
            lastText = tv.string
            parent?.onChange(tv.string)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !loading, let tv = notification.object as? NSTextView else { return }
            parent?.onSelectionChange?(tv.selectedRange())
        }
    }
}
