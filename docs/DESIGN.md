# QDVC Response Letter — Design Notes

## Windows

At launch, a welcome window in the style of Xcode and Keynote: the icon,
version, New and Open on the left; recent letters on the right, with the
folder name, manuscript ID and path. It hands over to the main window when
a letter opens, and comes back when the letter is closed. Opening a letter
from the File menu works from either window.

The main window has a sidebar, the page and an inspector (⌥⌘I), using
standard NavigationSplitView, toolbar, search field and inspector, so the
app picks up Liquid Glass on macOS 26 without custom chrome.

The sidebar lists pages, not comments: comments are worked on in tables,
as they are in the Word document, so neighbouring comments stay in view.

- **Response Letter › Overview**: a read-only table of every comment, for
  orientation; the inspector opens a row in either editor.
- **Workflow**, in the order of the work:
  - **Decision Letter**: the letter, read-only, with marked comments
    highlighted (in their triage colour, or the accent colour) and IDs and
    section starts in a margin, like line numbers in a code editor. A bar
    at the bottom offers what makes sense for the selection.
  - **Triage the comments**: the same table as “Respond to the comments” (one
    component, `CommentTable`, with different columns): ID, comment,
    triage (a dot and its name) and ideas, edited in place; the inspector
    has the status and related comments.
  - **Respond to the comments**: the response letter as an editable table, with
    the exported letter's black section bands (aligned with the comment
    column, as in Word). Cells are NSTextViews that size themselves to
    their text; the row takes the height of its tallest cell. One format
    bar acts on the response being edited.
  - **Opening & Closing**.
- **Tools**: Variables, Issues, and Traceability, a map in the spirit of
  network topology views (UniFi, Loopback, AirPort Utility): one invisible
  layer per section, cards ordered within a layer to sit near what they
  link to (a barycentre heuristic, so lines stay short and seldom cross),
  solid lines for related comments and dashed arrows for
  cross-references. Selecting a card dims everything it isn't linked to.

## Comments come from the letter

Every comment is marked in the decision letter, so the tables have no "new
comment" button: a comment missing from the letter is fixed by editing the
letter (Edit Letter), then marking it. Splitting and merging still change
how the marked text is divided.

## Inserting Variables and Cross-references

On the pages with editors the inspector has two tabs, Comment and Insert
(Opening & Closing has only Insert). Insert names the text that will
receive the insertion (from `AppModel.activeEditorLocation`, set when an
editor takes the focus), then lists related comments, Variables and all
comments by section, filtered together. A click inserts at the text cursor;
the editor keeps its selection while the inspector is clicked.

## Related column

Both tables show each comment's links, each with the other comment's triage
dot: related comments (a link icon),
comments its response mentions (→), comments whose responses mention it
(←) and undecided mentions after a split (orange ?). Clicking one goes to
that comment on the same page. On "Respond to the comments" the ideas are
read-only (selectable): they belong to triage. Ideas are lines of markup, so
they can hold Variables and Cross-references (renumbering, splits, merges
and Issues treat them like responses; their cross-references count as
links).

## Progress

Two bars at the foot of the sidebar follow the workflow: Triage (dark:
triaged and with at least one idea; light: triaged) and Respond (dark:
final; light: drafted).

## Large text

A toolbar toggle (⌥⌘=) scales the text, and the fixed columns and controls
around it, by 1.5 on every page where text is read or edited: Overview, the
Decision Letter, both editors, and Opening & Closing. It is meant for screen
sharing, so it is one switch rather than a setting; the base size is in
Settings.

## Terminology

"Variables" (as in Word fields and LaTeX macros: one value, many uses) and
"Cross-references" (as in Word, which also update when things renumber).
Both appear as pills in the text: teal for Variables, indigo for
cross-references, orange for a cross-reference awaiting a decision, red
for anything broken.

## Splitting and merging

IDs are positions, so renumbering is free. The hard part is meaning:

- **Split** (at the insertion point in the comment's text): the first part
  keeps the response, ideas, status and triage; the second starts "to do"
  with the same triage. Every cross-reference to the comment becomes
  pending (`{{ref:A|B}}`), and a sheet lists each in context with a button
  per part, or both ("SE-05 and SE-06"). Related comments are related to
  both parts by default, adjustable in the same sheet. Pending references
  can be left for later; they show in orange and in Issues.
- **Merge** (with the next comment in the section): texts, ideas and
  responses are joined, the stricter triage and the less advanced status
  win, and every reference to the second comment points to the first. A
  paragraph that now says "SE-05 and SE-05" is flagged.
- After any renumbering a banner lists what changed (RE1-04 → RE1-05…),
  since IDs may already have been quoted in emails to co-authors.

## Editing the decision letter

Edit Letter makes the Decision Letter page editable. Every edit is recorded
as the text view reports it (where, how much was replaced, by how much), and
marked comments and section starts are carried through the edits as you
type, so their highlights and IDs stay on their text. Text typed exactly at
either end of a comment stays outside it. On Done each comment is one of:

- **untouched**: its text didn't change; it just moved;
- **found again**: its text was changed or swallowed where it was, but its
  old wording appears exactly once in the new letter (cut and paste, or a
  whole new letter pasted over the old): it is re-anchored there, silently;
- **edited**: its text changed in place. The sheet shows Before and Now and
  offers: use the new wording as the comment's text (the default if the
  comment's text was still the marked text), keep the comment's text and mark
  the new wording (the default if it had been tidied), unmark it, or delete
  it;
- **removed**: its text is gone. Keep the comment unmarked (the default), or
  delete it.

Section starts follow without prompting. The whole edit is one step of
undo, letter included. Keep Editing returns to the editor with the edits
intact.

## Undo

Edit › Undo reverts structural changes field by field: undoing a triage
change restores the triage, not the whole comment, so typing done since is
never lost. Typing has its own undo inside each field.

## Choices worth revisiting

- Writing a response moves a comment from "to do" to "drafted"
  automatically; "final" is always set by hand.
- Comment text in the export is split into paragraphs at blank lines;
  single line breaks stay as line breaks (Join Wrapped Lines tidies
  hard-wrapped text).
- The export's columns: the ID (1.8 cm), then comments and responses at
  equal widths. The header row is not repeated on every page.

## Layout rule

Running text (the decision letter, the opening and the closing) sits in a
centred column at most 1000 points wide (`ReadableColumn.standardWidth`),
on the same white (black in dark mode) right across: very long lines are
hard to read, however wide the window. The tables (Overview, “Triage the comments”,
“Respond to the comments”) use the full width, since they divide it into columns.

No page may make the window wider. Menus in the format bar have fixed
widths (a menu button otherwise takes the width of its longest item, and
these items are long excerpts), text views report the size they are
offered rather than their content's, and the detail area takes whatever
width the split view gives it.
