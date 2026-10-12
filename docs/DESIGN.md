# QDVC Response Letter — Design Notes

## The window

A three-column window in the Mail/Notes/Xcode mould: a sidebar, the page or
comment being worked on, and an inspector (⌥⌘I), using standard
NavigationSplitView, toolbar, search field and inspector, so the app picks
up Liquid Glass on macOS 26 without custom chrome.

The sidebar has five pages, then every section with its comments (a triage
dot, the ID, the start of the comment, a warning if its response has a
problem, and a status icon). Sections fold, show "final of total", and are
edited from their heading's context menu; comments are dragged to reorder.
A progress bar sits at the bottom (drafted counts half).

- **Overview**: every comment in one table, for triage. Multi-select and
  colour with ⌘1–⌘3, like labels in Finder.
- **Decision Letter**: the letter, read-only, with marked comments
  highlighted (in their triage colour, or the accent colour) and IDs and
  section starts in a margin, like line numbers in a code editor. A bar at
  the bottom offers what makes sense for the selection: mark it, start a
  section there, or open the comment under the cursor.
- **Opening & Closing**, **Variables** (a table; the value is edited in
  place), **Issues** (with the split decisions inline).
- **A comment**: a header with the ID, triage dots and a status control,
  then three resizable panes: the comment (plain text: Join Wrapped Lines,
  Split Here, Merge with Next), the ideas (one bullet per line) and the
  response (rich text with a format bar).

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
- The export's column widths are fixed (1.8 cm, 6 cm, the rest).
