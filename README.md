# QDVC Response Letter for macOS

Write the response letter that goes with a revised journal manuscript. Paste
the decision letter, mark up the comments from the senior editor, associate
editor and reviewers, triage them, jot down ideas, draft a response to each,
and export the classic three-column Word table: ID, Editor/Reviewer
Comments, Response. A native SwiftUI and AppKit app for macOS 14 (Sonoma)
and later.

Each response letter is a plain folder of small YAML and text files, one
file per comment, so it diffs cleanly and is easy to keep in Git and share
with co-authors. The format is documented in
[docs/FILE_FORMAT.md](docs/FILE_FORMAT.md).

## What it does

The window has a sidebar (pages, then every section and its comments), the
page or comment you are working on, and an inspector (⌥⌘I). The layout and
its precedents in Mail, Notes and Xcode are explained in
[docs/DESIGN.md](docs/DESIGN.md).

- **Start from the decision letter** (File › New Response Letter, ⌘N):
  paste it as plain text and choose where to keep the folder.
- **Mark it up** in the Decision Letter page. Select a heading such as
  "Reviewer #1" and choose **New Section Here** (⇧⌘K); the app suggests
  the role, title and ID prefix (SE, AE, SIE, DE, TC, RE1, RE2…). Then select
  each comment's text and choose **Mark as Comment** (⌘K). Marked comments
  are highlighted, with their IDs in the margin; double-click one to open
  it. Comments can also be typed in directly (Comment › New Comment).
- **Triage** each comment green (easy), yellow (trickier) or red (needs
  discussion with co-authors), and give it a status: to do, drafted or
  final. The Overview page lists every comment in one table: select rows
  and press ⌘1–⌘3 (⌘0 clears) or ⌥⌘1–⌥⌘3. Filter by triage and status
  from the toolbar, and search from the sidebar.
- **Ideas:** dot points of first thoughts for each response, one per line.
- **Related comments** (inspector): link comments that ask for the same
  thing, such as an associate editor summarising two reviewers. Links work
  both ways.
- **Draft responses** with bold (⌘B), italic (⌘I), quoted manuscript text
  (⌘') and bullets (⇧⌘7), plus two kinds of linked text, shown as pills:
  - **Variables**: text with one official version, such as a page
    number, a word count or a sentence quoted from the revised manuscript.
    Change it once in the Variables page and every use changes. Select text
    and choose Variable › New Variable from Selection to make one.
  - **Cross-references** to other comments ("see our response to AE-03"),
    which always show the comment's current ID.
- **Split and merge** comments (⌥⌘D splits at the insertion point in the
  comment's text; ⌥⌘J merges with the next). Comments renumber themselves
  and cross-references follow. After a split, the app asks, for each
  cross-reference to the original comment, which part it now means (or
  both), and which parts the related comments relate to. Anything left
  undecided is flagged as an orange pill and in Issues.
- **Issues** collects what needs a look: undecided, broken (to a deleted
  comment) and duplicated cross-references; deleted, empty and unused
  Variables; and comments marked final with no response.
- **Opening & Closing**: the text before and after the table ("Dear
  Professor…").
- **Export** (⇧⌘E) an A4 Word document: the title, the opening, the table
  (a blank ID heading, a black band with a bold white heading such as
  "Reviewer 1 comments" at the start of each section, the header row
  repeated on every page) and the closing, with page numbers. Quoted text
  and bullets use Word's Quote and List Bullet styles, so they can be
  restyled in Word. The font, size and quote style are in Letter Settings
  (⌥⌘L), as is the ID style (separator and digits: RE1-01, RE1.1…).
- **Export for Co-authors** (⌥⇧⌘E): landscape A4, with each comment's
  triage colour, status, ideas, related comments and draft response, and a
  summary of progress. **Export Comments as CSV** for spreadsheets.
- **Undo** (⌘Z) covers marking, splitting, merging, deleting, moving,
  triage, status, related comments and Variables. Typing is undone in the
  field you are typing in.

## Requirements

- macOS 14 Sonoma or later.
- Xcode 16 or later (free from the Mac App Store); Xcode 26 or later for the
  Liquid Glass look. Full Xcode is needed, not just the Command Line Tools:
  from Xcode 27, SwiftUI's `@State` is a macro whose compiler plugin
  (SwiftUIMacros) ships only with Xcode, so a Command Line Tools or swift.org
  toolchain fails with "plugin for module 'SwiftUIMacros' not found".
- No paid Apple Developer account.

## Build and run

From the repository root:

```sh
scripts/build-app.sh            # build "build/QDVC Response Letter.app" (release)
scripts/build-app.sh --install  # …and copy it to ~/Applications
```

`scripts/build-app.sh` builds with Xcode's toolchain even when
`xcode-select` points at the Command Line Tools: it picks the newest Xcode
installed, and says which Xcode and macOS SDK it is using (warning if the
SDK predates Liquid Glass). It also records that SDK in the app's binary,
which is what turns on Liquid Glass (`swift build` alone writes the
deployment target there, 14.0, so a `swift run` build keeps the classic
look). Check a build with
`vtool -show-build "build/QDVC Response Letter.app/Contents/MacOS/QDVCResponseLetter"`:
`sdk` should be 26.0 or later.

To run or test from the command line, point the tools at Xcode:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
# or: sudo xcode-select --switch /Applications/Xcode.app
swift run                       # build and launch (debug)
swift test                      # run the unit tests
```

The core library (`ResponseCore`: the model, YAML, markup, split and merge,
DOCX and CSV export) has no AppKit or SwiftUI and builds and tests on
Linux too (docs/MAINTENANCE.md).

Or open the repository folder in Xcode (File → Open…, choose the folder that
contains `Package.swift`), pick the **QDVCResponseLetter** scheme and press
⌘R. Xcode may ask for a team: choose **None** / **Sign to Run Locally**.

A ready-made `sample-workspace/` is included to try the app straight away
(File → Open Response Letter…): a decision letter with a senior editor, an
associate editor and two reviewers, 15 comments at various stages, six
Variables and a few cross-references. Opening an empty folder offers to
start a response letter there.

## Signing without a paid account

`scripts/build-app.sh` signs the app **ad hoc** (`codesign --sign -`). That is
all macOS needs to run an app on the Mac that built it. If you give the app
to someone else, macOS will block the first launch; they can allow it in
**System Settings → Privacy & Security → Open Anyway**, or run:

```sh
xattr -dr com.apple.quarantine "/Applications/QDVC Response Letter.app"
```

## App icon

The icon, a frosted-glass version of the exported table (a black section
band, triage dots, grey comment lines and blue response lines) sealed with
an indigo reply-arrow badge, is generated by `tools/make_icon.py` on Apple's
macOS icon template, in the same style as the other QDVC apps, in the
"Slate" palette. It appears in the `.app` built by `scripts/build-app.sh`,
not with `swift run`.

## Where things are stored

- Each response letter: only in its folder, as described in
  [docs/FILE_FORMAT.md](docs/FILE_FORMAT.md). Changes are written as you
  go (typing, after a short pause). The app notices files changed by Git or
  another editor when you come back to it, and View › Reload from Disk (⌘R)
  re-reads them at any time.
- Preferences (text size, highlight colours, recent letters): the standard
  macOS defaults domain (`defaults read org.qdvc.response-letter.mac`).

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘N / ⌘O | New / open response letter |
| ⌘K | Mark selected text as a comment (Decision Letter) |
| ⇧⌘K | New section at the selection (Decision Letter) |
| ⌥⌘N | New comment |
| ⌘1 ⌘2 ⌘3 / ⌘0 | Triage green, yellow, red / clear |
| ⌥⌘1 ⌥⌘2 ⌥⌘3 | Status to do, drafted, final |
| ⌥⌘D | Split the comment at the insertion point |
| ⌥⌘J | Merge with the next comment |
| ⌥⌘↑ / ⌥⌘↓ | Move the comment up / down |
| ⌘[ / ⌘] | Previous / next comment |
| ⌘B ⌘I ⌘' ⇧⌘7 | Bold, italic, quoted text, bullets |
| ⌃⌘1 … ⌃⌘5 | Overview, Decision Letter, Opening & Closing, Variables, Issues |
| ⌥⌘I | Show or hide the inspector |
| ⇧⌘E / ⌥⇧⌘E | Export the response letter / the co-author version |
| ⌥⌘L | Letter Settings |
| ⌘R | Reload from disk |
