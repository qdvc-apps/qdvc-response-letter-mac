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

At launch a welcome window, as in Xcode and Keynote, offers to create or
open a response letter on the left and lists recent ones on the right
(double-click to open; right-click to remove one, or Clear Recent List).
Turn it off in Settings to reopen the last letter instead; Window › Welcome
to QDVC Response Letter (⇧⌘1) brings it back at any time.

The main window has a sidebar of pages, the page itself, and an inspector
(⌥⌘I) for the selected comment. The layout and its precedents are explained
in [docs/DESIGN.md](docs/DESIGN.md).

**Response Letter**

- **Overview**: every comment in one table (ID, triage, status, comment,
  ideas, response). Select rows and press ⌘1–⌘3 to triage (⌘0 clears) or
  ⌥⌘1–⌥⌘3 to set the status; the inspector opens the selected comment in
  “Triage the comments” or “Respond to the comments”; double-click opens it in 
  “Respond to the comments”.

**Workflow**

- **Decision Letter**: paste the decision letter when you start a response
  letter (File › New Response Letter, ⌘N). Select a heading such as
  "Reviewer #1" and choose **New Section Here** (⇧⌘K); the app suggests the
  role, title and ID prefix (SE, AE, SIE, DE, TC, RE1, RE2…). Then select
  each comment's text and choose **Mark as Comment** (⌘K). Marked comments
  are highlighted, with their IDs in the margin; double-click one to open
  it in “Respond to the comments”. **Edit Letter** makes the letter editable
  (to fix a paste, or to paste in a corrected version): marked comments
  follow your edits, comments whose text moved are found again, and on
  Done the app shows Before and Now for any comment whose text you changed
  or deleted and asks what to do.
- **Triage the comments**: the same kind of table as “Respond to the comments”, with
  the ID, comment, triage and ideas columns, every cell shown in full and
  edited in place, plus a Related column. Triage each comment green
  (trivial), yellow (clear solution) or red (needs discussion with
  co-authors) from its triage cell or with ⌘1–⌘3
  (⌘0 clears); ideas are dot points, one per line, and can hold
  Variables and Cross-references (from the bar above the table), which
  follow renumbering like those in responses. The inspector has the
  status and related comments (link comments that ask for the same thing,
  such as an associate editor summarising two reviewers).
- **Respond to the comments**: the whole response letter as one table, as in a
  word processor, so neighbouring comments stay in view. Black bands start
  each section; every cell (comment, ideas, response) is shown in full and
  edited in place, and rows grow as you type. The ideas (written while
  triaging) are shown for reference, read-only but selectable; the Related
  column shows each linked comment once, with the other comment's triage
  colour: → if this comment mentions it, ← if it mentions this one, ↔ if
  both, a link icon if they are only marked related; clicking one goes to
  it. Hide the
  triage, status, ideas or related columns from Columns. Responses have bold (⌘B), italic (⌘I),
  quoted manuscript text (⌘') and bullets (⇧⌘7), plus two kinds of linked
  text, shown as pills:
  - **Variables**: text with one official version, such as a page
    number, a word count or a sentence quoted from the revised manuscript.
    Change it once in the Variables page and every use changes. Select text
    and choose Variable › New Variable from Selection to make one.
  - **Cross-references** to other comments ("see our response to AE-03"),
    which always show the comment's current ID.

  Both can be inserted from the Format menu, the format bar, or the
  inspector's **Insert** tab: it says where the insertion will go (the
  response or ideas you are editing, the opening or the closing), and lists
  the comment's related comments first, then the Variables, then every
  comment by section, with one filter for all; click one to insert it.
- **Opening & Closing**: the text before and after the table ("Dear
  Professor…").

Comments can be split and merged (⌥⌘D splits at the insertion point in a
comment's text; ⌥⌘J merges with the next). They renumber themselves and
cross-references follow. After a split, the app asks, for each
cross-reference to the original comment, which part it now means (or both),
and which parts the related comments relate to. Anything left undecided is
flagged as an orange pill and in Issues. Right-click a comment's ID for
moving, merging and deleting; right-click a section band to edit, move or
delete the section.

**Tools**

- **Variables**: the table of Variables; edit a value and it changes
  everywhere.
- **Issues**: undecided, broken (to a deleted comment) and duplicated
  cross-references; deleted, empty and unused Variables; comments marked
  final with no response.
- **Traceability**: a map of how comments are linked, like a network
  topology view. Each section is a layer (editors above reviewers), each
  linked comment a card; solid lines join related comments and dashed
  arrows run from a response that mentions a comment to that comment.
  Click a card to highlight its links; double-click to open it.

**Export** (⇧⌘E) an A4 Word document: the title, the opening, the table (a
blank ID heading, then the comments and responses in two columns of equal
width, with a black band and a bold white heading such as "Reviewer 1
comments" at the start of each section; the header row appears once, at the
top) and the closing, with page numbers. Quoted text and bullets use Word's
Quote and List Bullet styles, so they can be restyled in Word. The font,
size and quote style are in Letter Settings (⌥⌘L), as is the ID style
(separator and digits: RE1-01, RE1.1…). **Export for Co-authors**
(⌥⇧⌘E): landscape A4, with each comment's triage colour, status, ideas,
related comments and draft response, and a summary of progress. **Export
Comments as CSV** for spreadsheets.

The sidebar shows two progress bars: **Triage** (dark: triaged and with
ideas written down; light: triaged) and **Respond** (dark: final; light:
drafted).

Comments come from the decision letter: mark them there (or edit the letter
to add text to mark). There is no way to add a comment that isn't in it.

**Large text** (the toolbar's text-size button, or ⌥⌘=) makes the text
in Overview, the Decision Letter, both editors and Opening & Closing half as
large again, for sharing your screen with co-authors on small screens.

**Undo** (⌘Z) covers marking, splitting, merging, deleting, moving, triage,
status, related comments and Variables. Typing is undone in the field you
are typing in.

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
associate editor and two reviewers, and 17 comments at every stage,
including each reviewer's closing summary, whose ideas and response
cross-reference the points it sums up. All
three triage colours are used, two comments are not yet triaged, and some
triaged comments have no ideas yet, so both shades of the Triage bar show.
Responses are final, drafted or still to do. Six Variables appear in
responses, ideas and the opening, alongside cross-references in responses
and ideas (some two-way) and a few related links where no cross-reference
already links two comments (Traceability has plenty to draw); one Variable
is a quotation long enough to wrap; quoted text,
bullets, bold and italic all appear. Opening an empty folder offers to
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
- Preferences (text size, highlight colours, recent letters, the welcome
  window): the standard
  macOS defaults domain (`defaults read org.qdvc.response-letter.mac`).

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘N / ⌘O | New / open response letter |
| ⇧⌘1 | Welcome window (recent response letters) |
| ⌘K | Mark selected text as a comment (Decision Letter) |
| ⇧⌘K | New section at the selection (Decision Letter) |
| ⌘1 ⌘2 ⌘3 / ⌘0 | Triage green, yellow, red / clear |
| ⌥⌘1 ⌥⌘2 ⌥⌘3 | Status to do, drafted, final |
| ⌥⌘D | Split the comment at the insertion point |
| ⌥⌘J | Merge with the next comment |
| ⌥⌘↑ / ⌥⌘↓ | Move the comment up / down |
| ⌘[ / ⌘] | Previous / next comment (on the current page) |
| ⌘B ⌘I ⌘' ⇧⌘7 | Bold, italic, quoted text, bullets |
| ⌃⌘1 … ⌃⌘8 | Overview, Decision Letter, “Triage the comments”, “Respond to the comments”, Opening & Closing, Variables, Issues, Traceability |
| ⌥⌘I | Show or hide the inspector |
| ⌥⌘= | Large text (also the toolbar's text-size button) |
| ⇧⌘E / ⌥⇧⌘E | Export the response letter / the co-author version |
| ⌥⌘L | Letter Settings |
| ⌘R | Reload from disk |
