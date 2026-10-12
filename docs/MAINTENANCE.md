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
| `Diagnostics.swift` | `Issue`s |
| `Workspace.swift` | loading, saving by `WorkspacePart`, change detection |
| `Docx.swift`, `Zip.swift` | the two Word exports; a stored-entry ZIP writer with CRC-32 |
| `CSVExport.swift` | CSV |

The core's section type is `LetterSection`, not `Section`, because the app
imports SwiftUI, which has its own `Section` (QDVC Progress hit the same
clash with `GridRow`). Check new public type names against SwiftUI, AppKit
and Foundation.

The app (`QDVCResponseLetter`): `ResponseLetterApp` (scene, delegate,
menus), `AppModel` (state, opening and saving, undo, every operation;
`@Observable`, main actor), `ContentView` (welcome, split view, sidebar,
toolbar, sheet routing), `CommentDetailView` (the comment editor, format
bar, inspectors), `LetterView` (decision letter, gutter), `PageViews`
(Overview, Opening & Closing, Variables, Issues), `Sheets` (and the
Settings window), `TextEditors` (below), `Style`.

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

## 3. Behaviour to preserve (tests)

- YAML round trips everything the app writes, and reads hand-written YAML.
- Markup round trips, including escapes and style transitions.
- Marking keeps letter order, trims whitespace and refuses overlaps.
- Split renumbers, splits the source range when the text is untouched, and
  makes references pending; merge redirects them and flags duplicates.
- `revert` keeps typing done after the change it undoes.
- A workspace saves and loads to an identical letter; orphan comment files
  are kept; bad files are reported with file and line.
- DOCX output is a valid ZIP with the table's header, black section rows
  and escaped text.
