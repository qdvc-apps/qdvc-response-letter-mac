# QDVC Response Letter — Workspace File Format (format 1)

A response letter is a folder. Every file is UTF-8 text with `\n` line
endings, small, and written only when its content changes, so the folder
works well in Git: co-authors editing different comments touch different
files.

```
My paper response letter/
  letter.yml             title, manuscript, numbering and export settings
  decision-letter.txt    the decision letter; rewritten only by Edit Letter
  sections.yml           the sections and the order of their comments
  comments/
    c-1a2b3c4d.yml       one file per comment, named by its stable key
  variables.yml          Variables
  opening.md             text before the table (markup)
  closing.md             text after the table (markup)
```

## Keys and IDs

Sections, comments and Variables have **stable keys** (`s-…`, `c-…`, `v-…`:
a letter, a hyphen and eight hex digits) that never change. A comment's
**ID** (`RE1-03`) is never stored: it is its section's prefix, the
separator and its 1-based position in the section, zero-padded. Splitting,
merging, moving or deleting comments therefore renumbers without touching
any file but `sections.yml`, and cross-references (which store keys) always
show current IDs.

## letter.yml

```yaml
format: 1                       # files written by a newer format are refused
app: QDVC Response Letter
title: Response to the editors and reviewers
manuscript: JIS-2026-0417       # optional
numbering:
  separator: "-"                # RE1-03; "." gives RE1.03, "" gives RE103
  digits: 2                     # zero-padding: 1–6
export:
  font: Times New Roman
  size: 11                      # points, 6–36
  quotes: italic                # italic | blue | plain (always indented)
```

## decision-letter.txt

The decision letter (line endings normalised). Comments and section starts
point into it by **UTF-16 offset** (the units of NSString). The app rewrites
it only when you edit the letter in the app (Edit Letter on the Decision
Letter page), and then carries every offset through your edits. Editing the
file by hand would leave the offsets pointing at the wrong text.

## sections.yml

```yaml
sections:
  - key: s-08f61726
    role: senior-editor         # senior-editor | associate-editor |
                                # special-issue-editor | department-editor |
                                # track-chair | reviewer | other
    title: Senior Editor        # the export heading is "<title> comments"
    prefix: SE
    anchor: 636                 # optional: where it starts in the letter
    comments:                   # in order; the order gives the IDs
      - c-06d6037a
      - c-e92c24a9
  - key: s-f4cef9ae
    role: reviewer
    number: 1                   # reviewers only
    title: Reviewer 1
    prefix: RE1
    comments: []
```

Comments listed here without a file are dropped (with a note); comment files
not listed anywhere are put in a new section, "Unassigned", so nothing is
lost after a merge conflict.

## comments/<key>.yml

```yaml
triage: yellow                  # none | green | yellow | red
status: drafted                 # todo | drafted | final
source: [2543+192]              # where it is in the decision letter: offset+length
related: [c-f0753e0a]           # related comments (kept symmetric)
text: |-
  3. I would like to know more about the sample. …
ideas:                          # one line of markup each
  - "It's {{var:v-e02cc14b}}: fix the 'around fifty' on p. 11"
response: |-
  We conducted {{var:v-e02cc14b}} between March 2024 and June 2025 …
```

`source` has several ranges after a merge. `text` is plain text;
`response` is markup, and each idea is one line of markup (bold, italic,
Variables and Cross-references; no quote or bullet marks, since ideas are
bullets anyway).

## variables.yml

```yaml
variables:
  - key: v-e02cc14b
    name: Interviews            # shown only in the app
    value: 47 semi-structured interviews   # printed wherever it is used
```

## Markup (responses, opening.md, closing.md)

| Markup | Meaning |
| --- | --- |
| a line | a paragraph (an empty line is an empty paragraph) |
| `> text` | quoted text from the manuscript (indented; italic, blue or plain in Word) |
| `- text` | a bullet |
| `**bold**`, `*italic*`, `***both***` | `**` switches bold on or off, `*` italic, `***` both |
| `{{var:v-…}}` | a Variable |
| `{{ref:c-…}}` | a Cross-reference to a comment |
| `{{ref:c-…\|c-…}}` | a cross-reference waiting for a decision after a split |
| `\*` `\\` `\{` | a literal `*`, `\` or `{`; `\>` and `\-` at the start of a line |

## YAML

The app reads and writes YAML with its own small parser (no third-party
library), which handles block mappings and sequences, plain and quoted
scalars, `#` comments, literal and folded block scalars with chomping and
indentation indicators, one-line flow lists, and `[]`/`{}`. Anchors,
aliases, tags, multiple documents and flow mappings are reported as errors
with the file name and line, and a workspace with an unreadable file is not
opened, so nothing is overwritten.
