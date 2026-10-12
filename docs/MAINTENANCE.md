# QDVC Response Letter for macOS — Maintenance Guide

The one rule that matters most: **the workspace is the contract.** The files
the app writes are documented in [FILE_FORMAT.md](FILE_FORMAT.md) and
checked by the unit tests. Any change to a file name or to the bytes of a
file is a format change: update FILE_FORMAT.md and the tests with it.

## 1. Layout

```
Package.swift                   SwiftPM manifest (no Xcode project, no dependencies)
Sources/ResponseCore/           the model: Foundation only, no AppKit/SwiftUI
Sources/QDVCResponseLetter/     the SwiftUI/AppKit app
Tests/ResponseCoreTests/        unit tests (and the sample-workspace generator)
tools/make_icon.py              regenerates Resources/AppIcon.{svg,icns}
tools/sample-decision-letter.txt  the sample's decision letter
scripts/build-app.sh            builds (with the newest Xcode) and ad-hoc signs the app
Resources/Info.plist            bundle id org.qdvc.response-letter.mac
sample-workspace/               a worked example (regenerate, below)
docs/                           DESIGN, FILE_FORMAT, this guide
```

`ResponseCore` builds and tests on Linux (Swift 5.10 or later), which is how
it was developed; the app target is declared on macOS only.

### 1.0 Toolchain

Build with full Xcode. From Xcode 27, SwiftUI's `@State` is a macro whose
implementation (the SwiftUIMacros compiler plugin) ships with Xcode, so the
Command Line Tools or a swift.org toolchain fail with "plugin for module
'SwiftUIMacros' not found". `scripts/build-app.sh` therefore sets
`DEVELOPER_DIR` to the newest installed Xcode when `xcode-select` points at
the Command Line Tools, runs `xcrun swift`, prints the compiler and SDK
versions, and warns when the SDK is older than 26 (no Liquid Glass). An
explicit `DEVELOPER_DIR` is respected. The same block is used in the other
QDVC macOS apps; keep them in step.

AppKit decides on Liquid Glass from the SDK version recorded in the
executable's `LC_BUILD_VERSION`. `swift build` records the deployment target
there (`sdk 14.0`), so after copying the executable into the bundle the
script rewrites that field with `vtool -set-build-version macos <minos>
<sdk> -replace`, before signing. Check with `vtool -show-build`.

### 1.1 App icon

`tools/make_icon.py` writes `Resources/AppIcon.svg` and
`Resources/AppIcon.icns` (needs `rsvg-convert`). "Slate" palette, Apple's
template geometry, matching the other QDVC apps. `--preview` also writes
`build/icon-preview.png`.

### 1.2 Sample workspace

`MAKE_SAMPLE=$PWD/sample-workspace swift test --filter MakeSampleTests`
rebuilds it from `tools/sample-decision-letter.txt` through the core API (so
it is always valid), and writes both DOCX exports and the CSV to the temp
folder for checking.

## 2. Modules

`ResponseCore`:

| File | Responsibility |
| --- | --- |
| `YAML.swift` | the YAML subset: `YAMLNode`, parser (line numbers in errors), emitter (`blockKeys`) |
| `RichText.swift` | markup ↔ `RichText` (paragraphs, bold/italic, `Token`s), `TextStats` |
| `Model.swift` | `Triage`, `Status`, `SectionRole`, `LetterSection`, `Comment`, `Variable`, `LetterSettings`, `ResponseLetter` (lookups, numbering, progress), `Keys` |
| `Editing.swift` | sections, marking, moving, related, split, merge, pending references, Variables, `revert` (undo), `TextTools` |
| `Diagnostics.swift` | `Issue`s, `CommentLink`s (`links()`) |
| `LetterRevision.swift` | editing the decision letter: `LetterEdit`, `Remap`, `revision(newText:edits:)`, `apply(_:decisions:)` |
| `Workspace.swift` | loading, saving by `WorkspacePart`, change detection |
| `Docx.swift`, `Zip.swift` | the two Word exports; a stored-entry ZIP writer with CRC-32 |
| `CSVExport.swift` | CSV |

The core's section type is `LetterSection`, not `Section`, because the app
imports SwiftUI, which has its own `Section` (QDVC Progress hit the same
clash with `GridRow`). Check new public type names against SwiftUI, AppKit
and Foundation.

The app (`QDVCResponseLetter`): `ResponseLetterApp` (the welcome and main
window scenes, delegate, menus), `Welcome` (the welcome window; it and
the main window hand over to each other by watching
`AppModel.workspaceURL`), `AppModel` (state, opening and saving, undo, every operation;
`@Observable`, main actor), `ContentView` (the split view, sidebar, toolbar, page and sheet routing),
`PageViews` (Overview, “Triage the comments”, Opening & Closing, Variables,
Issues), `CommentTable` (the editable table behind both “Triage the comments” and 
“Respond to the comments”; `TableLayout` sets each one's columns), `Traceability` (the link
map, from `ResponseLetter.links()`), `Inspectors` (the format bar and one
inspector per page), `LetterView` (decision letter, gutter), `Sheets` (and the
Settings window), `TextEditors` (below), `PaneStack` (resizable stacked
panes), `Style`.

### 2.1 Editors

The response editor is an `NSTextView` built on TextKit 1 explicitly (its
own `NSLayoutManager`), because Variables and Cross-references are
`NSTextAttachmentCell`s (`TokenCell`) that draw pills and ask a
`TokenProvider` what to say, so renaming a Variable or renumbering only
needs a re-layout. Bold, italic and the paragraph kind are custom
attributes (`rlBold`, `rlItalic`, `rlBlock`); `MarkupConverter` maps the
attributed string to `RichText` and back. `MarkupLayoutManager` draws
bullets and quote bars. Copy and paste use a private pasteboard type
carrying markup (plain text for other apps); pasted plain text takes the
formatting where it lands.

Editors have no scroll view of their own: `sizeThatFits` lays the text out
at the offered width and returns its height, so a “Respond to the comments” row grows
as you type, and Opening & Closing scroll them in a `FillingScroll`.

Each editor reports its markup on every change; `updateNSView` reloads
only when the model's markup differs from what the editor last produced,
and redraws pills when `AppModel.tokenSignature` changes. Each editor has
its own `UndoManager` (via the `undoManager(for:)` delegate method).

### 2.2 Changes, undo and saving

- `perform(name) { letter in … }` applies an undoable change and registers
  `revert(changesFrom:to:)` with the window's undo manager (and the redo).
- `updateText { … }` is for typing: saved, not on Edit › Undo.
- Both mark the changed `WorkspacePart`s dirty; `flushSaves` writes them
  0.6 s later, when the selection changes, when the app is left, and on
  quit. Identical content is never rewritten.
- On returning to the app, file stamps are compared and the workspace is
  reloaded if something outside changed it.

### 2.3 Layout

Never let a view's content decide the window's width (docs/DESIGN.md
§Layout rule): no `.fixedSize()` on menus or pickers whose items are long
(give them a width), `sizeThatFits` on every `NSViewRepresentable`, and the
detail area in a flexible, clipped frame.

Stacked, resizable panes use `PaneStack`, not SwiftUI's `VSplitView`: it
measures the space with a GeometryReader and gives every pane exactly that
width and its share of the height, so a pane can never be wider than the
window (with `VSplitView`, the comment and Opening & Closing panes came out
far wider than the window and their lines ran off the edge). Pane heights
are remembered in the defaults (`panes.comment`, `panes.openingClosing`).

Text views in the tables handle ⌘C, ⌘X, ⌘V and ⌘A themselves
(`EditorTextView.performKeyEquivalent`), and the comment's context menu sits
on the ID cell only: on the whole row, SwiftUI's context menu replaced the
text views' own Cut / Copy / Paste menu.

A SwiftUI `Menu`'s label on macOS shows only text and SF Symbols: a drawn
view (a triage dot) silently disappears, leaving what looks like an empty
column. Use `PopUpButton`, which takes any label and pops up an AppKit menu
(with images).

Don't pair `.onTapGesture(count: 2)` with a single `.onTapGesture` on one
view: SwiftUI then delays every single click by the system double-click
interval (Traceability's cards felt a second slow). Use one tap handler
that checks `NSApp.currentEvent?.clickCount`, or a Table's `primaryAction`.

The same goes for any page whose main content is a text view (the
Decision Letter page): measure it with a GeometryReader and give the text
view, and the bars around it, exactly the measured width; a plain VStack in
the detail column did not keep the text view to the window's width. Bars of
buttons use `ViewThatFits` with a compact form.

Pages of running text wrap their content in `ReadableColumn` (centred, at
most 1000 points, on the text background colour).

**No text view lives in an AppKit scroll view.** Hosted in SwiftUI, an
NSTextView inside an NSScrollView repeatedly ended up wider than the space
it was given, whatever the scroll view was told (a starting width,
re-tiling, explicit line widths). Every text view is instead sized by
SwiftUI through `sizeThatFits` (the width offered; the height of its text,
from `fittingHeight(of:width:)`), exactly like “Respond to the comments”'s cells,
which always wrapped correctly; pages that scroll put it in a SwiftUI
ScrollView (`FillingScroll`). The decision letter's text view draws its own
margin of IDs and section names (`LetterNSTextView`, which shifts
`textContainerOrigin` and sets its line width itself) instead of using an
NSRulerView.

## 3. Behaviour to preserve (tests)

- YAML round trips everything the app writes, and reads hand-written YAML.
- Markup round trips, including escapes and style transitions.
- Marking keeps letter order, trims whitespace and refuses overlaps.
- Split renumbers, splits the source range when the text is untouched, and
  makes references pending; merge redirects them and flags duplicates.
- `revert` keeps typing done after the change it undoes.
- `links()` gives related links once and cross-references by direction,
  pending ones separately.
- Editing the decision letter shifts untouched comments and section
  starts, finds moved text again, reports edited and removed comments with
  sensible defaults, and undoes completely (`LetterRevisionTests`).
- A workspace saves and loads to an identical letter; orphan comment files
  are kept; bad files are reported with file and line.
- DOCX output is a valid ZIP with the table's header (not repeated on every
  page), equal comment and response columns, black section rows and
  escaped text.
