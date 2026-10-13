import XCTest
@testable import ResponseCore

final class YAMLTests: XCTestCase {
    func testRoundTripOfEverythingTheAppWrites() throws {
        let node: YAMLNode = .map([
            ("format", .num(1)),
            ("title", .str("Response: round 2 # draft")),
            ("separator", .str("-")),
            ("empty", .str("")),
            ("nullish", .str("null")),
            ("quote", .str("He said \"no\" \\ twice")),
            ("multi", .str("line one\nline two\n")),
            ("strip", .str("no final newline\n\n  indented line")),
            ("keep", .str("two trailing\n\n\n")),
            ("leading", .str("  starts with spaces\nnext")),
            ("blankFirst", .str("\nafter a blank line")),
            ("short", .list(["a", "b, c", "[x]"])),
            ("long", .list((1...10).map { "c-0000000\($0 % 10)" })),
            ("nested", .map([("separator", .str("-")), ("digits", .num(2))])),
            ("emptyList", .list([])),
            ("items", .sequence([
                .map([("key", .str("s-1")), ("comments", .list(["c-1", "c-2"]))]),
                .map([("key", .str("s-2")), ("text", .str("multi\nline"))]),
            ])),
        ])
        let text = YAML.emit(node)
        XCTAssertEqual(try YAML.parse(text), node, text)
    }

    func testHandWrittenYAML() throws {
        let text = """
        # a comment
        title: 'It''s fine'   # trailing comment
        size: 11
        ideas:
        - first idea
        - "second: with colon"
        text: >
          folded
          lines

          new paragraph
        flow: [one, "two, three" , four]
        nested:
            deep:
              - key: a
                value: b
              -   key: c
        """
        let n = try YAML.parse(text)
        XCTAssertEqual(n["title"]?.string, "It's fine")
        XCTAssertEqual(n["size"]?.int, 11)
        XCTAssertEqual(n["ideas"]?.strings, ["first idea", "second: with colon"])
        XCTAssertEqual(n["text"]?.string, "folded lines\nnew paragraph\n")
        XCTAssertEqual(n["flow"]?.strings, ["one", "two, three", "four"])
        XCTAssertEqual(n["nested"]?["deep"]?.items.count, 2)
        XCTAssertEqual(n["nested"]?["deep"]?.items[1]["key"]?.string, "c")
    }

    func testQuotesInsideFlowItems() throws {
        let n = try YAML.parse("a: [It's 47 — the 'fifty' was wrong, 'x, ''y''', \"z\"]\n")
        XCTAssertEqual(n["a"]?.strings, ["It's 47 — the 'fifty' was wrong", "x, 'y'", "z"])
        let node: YAMLNode = .map([("a", .list(["It's", "say \"hi\""])), ("ideas", .list(["one"])), ("text", .str("x"))])
        let text = YAML.emit(node, blockKeys: ["ideas", "text"])
        XCTAssertTrue(text.contains("ideas:\n  - one\ntext: |-\n  x"), text)
        XCTAssertEqual(try YAML.parse(text), node)
    }

    func testErrorsHaveLineNumbers() {
        XCTAssertThrowsError(try YAML.parse("a: 1\n  b: 2\n")) { error in
            XCTAssertEqual((error as? YAMLError)?.line, 2)
        }
        XCTAssertThrowsError(try YAML.parse("a: &anchor 1\n"))
        XCTAssertThrowsError(try YAML.parse("a: \"open\n"))
    }
}

final class RichTextTests: XCTestCase {
    func testParseAndSerialise() {
        let markup = """
        We thank the reviewer. **Bold**, *italic* and ***both***.
        > Revised text, see {{var:v-1}}.
        - A point with {{ref:c-2}}
        - Pending {{ref:c-3|c-4}}
        Literal \\* star, \\{{not a token}} and \\\\ backslash
        \\- not a bullet
        \\> not a quote

        """
        let rich = RichText(markup: markup)
        XCTAssertEqual(rich.paragraphs.count, 7)
        XCTAssertEqual(rich.paragraphs[1].block, .quote)
        XCTAssertEqual(rich.paragraphs[2].block, .bullet)
        XCTAssertEqual(rich.paragraphs[5].block, .normal)
        XCTAssertEqual(rich.paragraphs[0].inlines[1], .text("Bold", InlineStyle(bold: true)))
        XCTAssertEqual(rich.paragraphs[0].inlines[5], .text("both", InlineStyle(bold: true, italic: true)))
        XCTAssertEqual(rich.tokens.map(\.token), [.variable("v-1"), .ref(["c-2"]), .ref(["c-3", "c-4"])])
        XCTAssertTrue(rich.tokens[2].token.isPending)
        XCTAssertEqual(rich.paragraphs[4].inlines, [.text("Literal * star, {{not a token}} and \\ backslash", .plain)])
        XCTAssertEqual(RichText(markup: rich.markup), rich)
    }

    func testStyleTransitionsRoundTrip() {
        let p = RichParagraph(block: .normal, inlines: [
            .text("a", InlineStyle(bold: true)),
            .text("b", InlineStyle(bold: true, italic: true)),
            .text("c", InlineStyle(italic: true)),
            .token(.variable("v-1"), InlineStyle(italic: true)),
            .text("- d", .plain),
        ])
        let rich = RichText(paragraphs: [p, RichParagraph(block: .normal, inlines: [.text("- starts like a bullet", .plain)])])
        XCTAssertEqual(RichText(markup: rich.markup), rich, rich.markup)
    }
}

final class EditingTests: XCTestCase {
    func sampleLetter() throws -> ResponseLetter {
        let decision = """
        Dear author,
        Senior Editor
        1. Please clarify the theory. Also explain the method.
        2. Tighten the discussion.
        Reviewer 1
        The sample is small.
        """
        var letter = ResponseLetter(decisionLetter: decision)
        let ns = decision as NSString
        let se = letter.addSection(role: .seniorEditor, anchor: ns.range(of: "Senior Editor").location)
        let r1 = letter.addSection(role: .reviewer, number: 1, anchor: ns.range(of: "Reviewer 1").location)
        try letter.markComment(SourceRange(ns.range(of: "2. Tighten the discussion.")), inSection: se)
        try letter.markComment(SourceRange(ns.range(of: "1. Please clarify the theory. Also explain the method.")), inSection: se)
        try letter.markComment(SourceRange(ns.range(of: "\nThe sample is small.")), inSection: r1)
        return letter
    }

    func testMarkingKeepsLetterOrderAndTrims() throws {
        let letter = try sampleLetter()
        let ids = letter.idMap()
        let ordered = letter.orderedComments
        XCTAssertEqual(ordered.map { ids[$0.key] }, ["SE-01", "SE-02", "RE1-01"])
        XCTAssertTrue(ordered[0].text.hasPrefix("1. Please"))
        XCTAssertEqual(ordered[2].text, "The sample is small.")
        XCTAssertEqual(letter.sectionKey(forOffset: (letter.decisionLetter as NSString).range(of: "sample").location),
                       letter.sections[1].key)
        var copy = letter
        XCTAssertThrowsError(try copy.markComment(SourceRange(location: ordered[0].source[0].location + 3, length: 5),
                                                  inSection: letter.sections[0].key))
    }

    func testSplitMakesReferencesPendingAndRenumbers() throws {
        var letter = try sampleLetter()
        let first = letter.orderedComments[0].key
        let second = letter.orderedComments[1].key
        let reviewer = letter.orderedComments[2].key
        letter.comments[reviewer]?.response = "See our response to {{ref:\(first)}} and {{ref:\(second)}}."
        letter.setRelated(reviewer, first, true)

        let text = letter.comments[first]!.text
        let offset = (text as NSString).range(of: "Also").location
        let result = try letter.splitComment(first, atUTF16: offset)

        let ids = letter.idMap()
        XCTAssertEqual(ids[result.secondKey], "SE-02")
        XCTAssertEqual(ids[second], "SE-03")
        XCTAssertEqual(result.renumbered, [Renumbering(key: second, old: "SE-02", new: "SE-03")])
        XCTAssertEqual(letter.comments[first]?.text, "1. Please clarify the theory.")
        XCTAssertEqual(letter.comments[result.secondKey]?.text, "Also explain the method.")
        // Source split precisely, since the text was untouched.
        XCTAssertEqual(letter.sourceText(letter.comments[result.secondKey]!.source[0]), "Also explain the method.")
        XCTAssertEqual(result.pending.count, 1)
        XCTAssertEqual(result.pending[0].candidates, [first, result.secondKey])
        XCTAssertTrue(letter.comments[reviewer]!.related.contains(result.secondKey))
        XCTAssertEqual(letter.issues().filter { $0.kind == .pendingReference }.count, 1)

        XCTAssertTrue(letter.resolvePending(result.pending[0], choosing: [first, result.secondKey]))
        XCTAssertEqual(letter.comments[reviewer]?.response,
                       "See our response to {{ref:\(first)}} and {{ref:\(result.secondKey)}} and {{ref:\(second)}}.")
        XCTAssertTrue(letter.pendingReferences().isEmpty)
        let display = letter.comments[reviewer]!.responseText.plainText { letter.tokenDisplay($0) }
        XCTAssertEqual(display, "See our response to SE-01 and SE-02 and SE-03.")
    }

    func testMergeRedirectsReferences() throws {
        var letter = try sampleLetter()
        let a = letter.orderedComments[0].key
        let b = letter.orderedComments[1].key
        let r = letter.orderedComments[2].key
        letter.comments[a]?.triage = .green
        letter.comments[b]?.triage = .red
        letter.comments[a]?.status = .final
        letter.comments[r]?.response = "See {{ref:\(a)}} and {{ref:\(b)}}."
        letter.setRelated(r, b, true)
        _ = try letter.mergeComment(a, withNext: b)
        XCTAssertNil(letter.comments[b])
        XCTAssertEqual(letter.comments[a]?.triage, .red)
        XCTAssertEqual(letter.comments[a]?.status, .todo)
        XCTAssertEqual(letter.comments[a]?.source.count, 2)
        XCTAssertEqual(letter.comments[r]?.related, [a])
        XCTAssertEqual(letter.comments[r]?.response, "See {{ref:\(a)}} and {{ref:\(a)}}.")
        XCTAssertEqual(letter.issues().filter { $0.kind == .duplicateReference }.count, 1)
        XCTAssertThrowsError(try letter.mergeComment(a, withNext: r))
    }

    func testDeleteLeavesBrokenReference() throws {
        var letter = try sampleLetter()
        let a = letter.orderedComments[0].key
        let r = letter.orderedComments[2].key
        letter.comments[r]?.response = "See {{ref:\(a)}}."
        XCTAssertEqual(letter.deleteComment(a), 1)
        XCTAssertEqual(letter.issues().filter { $0.kind == .brokenReference }.count, 1)
    }

    func testVariables() throws {
        var letter = try sampleLetter()
        let v = letter.addVariable(name: "Sample size", value: "N = 412")
        let unused = letter.addVariable(name: "Unused", value: "x")
        let r = letter.orderedComments[2].key
        letter.comments[r]?.response = "Our sample is **{{var:\(v)}}** now."
        XCTAssertEqual(letter.variableUses()[v], [.response(r)])
        XCTAssertEqual(letter.issues().filter { $0.kind == .unusedVariable }.map(\.variableKey), [unused])
        letter.updateVariable(Variable(key: v, name: "Sample size", value: "N = 500"))
        XCTAssertEqual(letter.comments[r]!.responseText.plainText { letter.tokenDisplay($0) }, "Our sample is N = 500 now.")
        letter.deleteVariable(v)
        XCTAssertEqual(letter.comments[r]?.response, "Our sample is **N = 500** now.")
    }

    func testMoveComments() throws {
        var letter = try sampleLetter()
        let keys = letter.sections[0].commentKeys
        letter.moveComments(inSection: letter.sections[0].key, fromOffsets: IndexSet(integer: 0), toOffset: 2)
        XCTAssertEqual(letter.sections[0].commentKeys, [keys[1], keys[0]])
        let r = letter.orderedComments[2].key
        letter.moveComment(r, toSection: letter.sections[0].key, at: 0)
        XCTAssertEqual(letter.idMap()[r], "SE-01")
        XCTAssertTrue(letter.sections[1].commentKeys.isEmpty)
    }

    func testRevertKeepsLaterTyping() throws {
        let original = try sampleLetter()
        let a = original.orderedComments[0].key
        var before = original
        before.comments[a]?.triage = .none
        var after = before
        after.comments[a]?.triage = .red
        var current = after
        current.comments[a]?.response = "typed later"
        current.revert(changesFrom: before, to: after)
        XCTAssertEqual(current.comments[a]?.triage, Triage.none)
        XCTAssertEqual(current.comments[a]?.response, "typed later")

        // Undo and redo of a split.
        var split = original
        let result = try split.splitComment(a, atUTF16: 10)
        var undone = split
        undone.revert(changesFrom: original, to: split)
        XCTAssertEqual(undone, original)
        undone.revert(changesFrom: split, to: original)
        XCTAssertEqual(undone, split)
        _ = result
    }

    func testLinks() throws {
        var letter = try sampleLetter()
        let a = letter.orderedComments[0].key
        let b = letter.orderedComments[1].key
        let r = letter.orderedComments[2].key
        letter.setRelated(r, a, true)
        letter.comments[r]?.response = "See {{ref:\(a)}}, {{ref:\(a)}} and {{ref:\(r)}}."
        letter.comments[b]?.response = "Pending {{ref:\(a)|\(r)}}."
        let links = letter.links()
        XCTAssertEqual(links.filter { $0.kind == .related }, [CommentLink(from: a, to: r, kind: .related)])
        XCTAssertEqual(links.filter { $0.kind == .reference }, [CommentLink(from: r, to: a, kind: .reference)])
        XCTAssertEqual(links.filter { $0.kind == .pendingReference }.count, 2)
    }

    func testIdeasHoldTokensThatFollowSplits() throws {
        var letter = try sampleLetter()
        let a = letter.orderedComments[0].key
        let r = letter.orderedComments[2].key
        let v = letter.addVariable(name: "Page", value: "p. 3")
        letter.comments[r]?.ideas = ["Same as {{ref:\(a)}}", "Check {{var:\(v)}}"]
        XCTAssertEqual(letter.variableUses()[v], [.ideas(r)])
        XCTAssertEqual(letter.ideaText(letter.comments[r]!.ideas[0]), "Same as SE-01")
        XCTAssertTrue(letter.links().contains(CommentLink(from: r, to: a, kind: .reference)))
        let split = try letter.splitComment(a, atUTF16: 10)
        XCTAssertEqual(split.pending.map(\.location), [.ideas(r)])
        XCTAssertTrue(letter.resolvePending(split.pending[0], choosing: [split.secondKey]))
        XCTAssertEqual(letter.ideaText(letter.comments[r]!.ideas[0]), "Same as SE-02")
        XCTAssertEqual(letter.comments[r]?.ideas.count, 2)
        // Markup pasted in with quote or bullet marks becomes plain ideas.
        XCTAssertEqual(ResponseLetter.ideaLines("> quoted\n- bullet\n\n"), ["quoted", "bullet"])
        // While typing, an empty line for the next idea is kept.
        letter.setMarkup("first\n", at: .ideas(r))
        XCTAssertEqual(letter.markup(at: .ideas(r)), "first\n")
    }

    func testProgress() throws {
        var letter = try sampleLetter()
        let keys = letter.orderedCommentKeys
        letter.comments[keys[0]]?.triage = .green
        letter.comments[keys[0]]?.ideas = ["thank them"]
        letter.comments[keys[1]]?.triage = .red
        letter.comments[keys[1]]?.ideas = ["  "]
        letter.comments[keys[2]]?.ideas = ["untriaged idea"]
        let p = letter.progress()
        XCTAssertEqual(p.triaged, 2)
        XCTAssertEqual(p.triagedWithIdeas, 1)
        XCTAssertEqual(Triage.yellow.label, "Clear solution")
    }

    func testUnwrap() {
        let text = "This is a hard-\nwrapped line\nthat continues.\n\n1. A list item\n2. Another\n\n\nEnd"
        XCTAssertEqual(TextTools.unwrap(text), "This is a hard- wrapped line that continues.\n\n1. A list item\n2. Another\n\nEnd")
    }
}

final class WorkspaceTests: XCTestCase {
    var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("rl-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    func testCreateSaveLoad() throws {
        var letter = try Workspace.create(at: folder, decisionLetter: "Reviewer 1\r\nGood paper.\r\n",
                                          settings: LetterSettings(title: "Response", manuscript: "MS-1"))
        XCTAssertEqual(letter.decisionLetter, "Reviewer 1\nGood paper.\n")
        let s = letter.addSection(role: .reviewer, number: 1, anchor: 0)
        let c = try letter.markComment(SourceRange(location: 11, length: 11), inSection: s)
        letter.comments[c]?.ideas = ["thank them", "ideas: with colon"]
        letter.comments[c]?.response = "Thank you.\n> Quoted\n- bullet"
        letter.comments[c]?.triage = .yellow
        letter.opening = "Dear Editor,"
        _ = letter.addVariable(name: "Page", value: "p. 3")
        try Workspace.save(letter, parts: Workspace.allParts(of: letter), to: folder)

        let loaded = try Workspace.load(folder)
        XCTAssertEqual(loaded.letter, letter)
        XCTAssertTrue(loaded.notes.isEmpty)
        XCTAssertEqual(Workspace.summary(folder)?.manuscript, "MS-1")

        // Deleting a comment deletes its file on save.
        var changed = letter
        changed.deleteComment(c)
        try Workspace.save(changed, parts: changed.changedParts(since: letter), to: folder)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("comments/\(c).yml").path))
        XCTAssertEqual(try Workspace.load(folder).letter, changed)
    }

    func testOrphanCommentFilesAreKept() throws {
        let letter = try Workspace.create(at: folder, decisionLetter: "x", settings: LetterSettings())
        try "text: Hand-made comment\n".write(to: folder.appendingPathComponent("comments/c-hand.yml"),
                                              atomically: true, encoding: .utf8)
        let loaded = try Workspace.load(folder)
        XCTAssertEqual(loaded.letter.sections.last?.title, "Unassigned")
        XCTAssertEqual(loaded.letter.comments["c-hand"]?.text, "Hand-made comment")
        XCTAssertEqual(loaded.repairedParts, [.sections])
        _ = letter
    }

    func testBadFileReportsNameAndLine() throws {
        _ = try Workspace.create(at: folder, decisionLetter: "x", settings: LetterSettings())
        try "sections:\n  - key: a\n   bad: indent\n".write(to: folder.appendingPathComponent("sections.yml"),
                                                          atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try Workspace.load(folder)) { error in
            let message = (error as? WorkspaceError)?.errorDescription ?? ""
            XCTAssertTrue(message.hasPrefix("sections.yml: line 3"), message)
        }
    }
}

final class ExportTests: XCTestCase {
    func testDocxIsAZipWithTheTable() throws {
        var letter = ResponseLetter(decisionLetter: "R1 says hi")
        let s = letter.addSection(role: .reviewer, number: 1)
        let c = letter.addComment(inSection: s, text: "Please fix <this> & that.")!
        letter.comments[c]?.response = "Done, see **p. 2**.\n> Quote\n- Bullet"
        let data = DocxExport.responseLetter(letter)
        XCTAssertEqual(Array(data.prefix(4)), [0x50, 0x4B, 0x03, 0x04])
        let xml = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(xml.contains("Reviewer 1 comments"))
        XCTAssertTrue(xml.contains("Please fix &lt;this&gt; &amp; that."))
        XCTAssertTrue(xml.contains("w:fill=\"000000\""))
        XCTAssertFalse(xml.contains("<w:tblHeader/>"), "the header row must not repeat on every page")
        // Comments and responses get equal widths.
        XCTAssertEqual(xml.components(separatedBy: "<w:gridCol w:w=\"4013\"/>").count, 3)
        XCTAssertTrue(xml.contains("Editor/Reviewer Comments"))
        XCTAssertFalse(DocxExport.discussion(letter).isEmpty)
    }

    func testCRC() {
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF4_3926)
    }

    func testCSV() {
        var letter = ResponseLetter()
        let s = letter.addSection(role: .seniorEditor)
        let c = letter.addComment(inSection: s, text: "Say \"why\", please")!
        letter.comments[c]?.ideas = ["one"]
        let csv = CSV.comments(letter)
        XCTAssertTrue(csv.contains("SE-01,Senior Editor,,To do,\"Say \"\"why\"\", please\",• one,,,0"))
    }
}

extension SourceRange {
    init(_ r: NSRange) { self.init(location: r.location, length: r.length) }
}

final class LetterRevisionTests: XCTestCase {
    /// The decision letter, edited by replacing `old` with `new` once.
    func edit(_ letter: ResponseLetter, _ old: String, _ new: String) -> (String, LetterEdit) {
        let ns = letter.decisionLetter as NSString
        let r = ns.range(of: old)
        precondition(r.location != NSNotFound, old)
        let text = ns.replacingCharacters(in: r, with: new)
        return (text, LetterEdit(location: r.location, length: r.length, replacementLength: (new as NSString).length))
    }

    func sample() throws -> ResponseLetter {
        let decision = "Dear author,\nSenior Editor\n1. Clarify the theory.\n2. Tighten the discussion.\nReviewer 1\nThe sample is small.\n"
        var letter = ResponseLetter(decisionLetter: decision)
        let ns = decision as NSString
        let se = letter.addSection(role: .seniorEditor, anchor: ns.range(of: "Senior Editor").location)
        let r1 = letter.addSection(role: .reviewer, number: 1, anchor: ns.range(of: "Reviewer 1").location)
        for s in ["1. Clarify the theory.", "2. Tighten the discussion."] {
            try letter.markComment(SourceRange(location: ns.range(of: s).location, length: ns.range(of: s).length), inSection: se)
        }
        let r = ns.range(of: "The sample is small.")
        try letter.markComment(SourceRange(location: r.location, length: r.length), inSection: r1)
        return letter
    }

    func testRemapRules() {
        let r = SourceRange(location: 10, length: 5)        // [10, 15)
        XCTAssertEqual(Remap.map(r, through: [LetterEdit(location: 2, length: 0, replacementLength: 3)]).range.location, 13)
        XCTAssertFalse(Remap.map(r, through: [LetterEdit(location: 15, length: 0, replacementLength: 3)]).touched)
        XCTAssertFalse(Remap.map(r, through: [LetterEdit(location: 10, length: 0, replacementLength: 3)]).touched)
        let inside = Remap.map(r, through: [LetterEdit(location: 12, length: 1, replacementLength: 4)])
        XCTAssertTrue(inside.touched)
        XCTAssertEqual(inside.range, SourceRange(location: 10, length: 8))
        let gone = Remap.map(r, through: [LetterEdit(location: 8, length: 10, replacementLength: 0)])
        XCTAssertEqual(gone.range.length, 0)
        XCTAssertEqual(Remap.map(offset: 10, through: [LetterEdit(location: 10, length: 0, replacementLength: 2)]), 12)
        XCTAssertEqual(Remap.map(offset: 12, through: [LetterEdit(location: 10, length: 5, replacementLength: 1)]), 10)
    }

    func testEditsElsewhereJustShift() throws {
        var letter = try sample()
        let (text, e) = edit(letter, "Dear author,", "Dear Dr Nguyen and co-authors,")
        let rev = letter.revision(newText: text, edits: [e])
        XCTAssertTrue(rev.changes.isEmpty)
        XCTAssertEqual(rev.shifted, 3)
        letter.apply(rev)
        XCTAssertEqual(letter.orderedComments.map { letter.sourceText($0.source[0]) },
                       ["1. Clarify the theory.", "2. Tighten the discussion.", "The sample is small."])
        XCTAssertEqual(letter.sourceText(SourceRange(location: letter.sections[1].anchor!, length: 10)), "Reviewer 1")
    }

    func testEditedAndRemovedComments() throws {
        var letter = try sample()
        let keys = letter.orderedCommentKeys
        letter.comments[keys[1]]?.text = "Tighten the discussion (tidied)."
        var (text, e1) = edit(letter, "Clarify the theory", "Clarify the theoretical framing")
        var edited = letter
        edited.decisionLetter = text
        let (text2, e2) = edit(edited, "2. Tighten the discussion.\n", "")
        text = text2
        let rev = letter.revision(newText: text, edits: [e1, e2])
        XCTAssertEqual(rev.changes.map(\.kind), [.edited, .removed])
        XCTAssertEqual(rev.changes[0].newText, "1. Clarify the theoretical framing.")
        XCTAssertEqual(rev.changes[0].defaultDecision, .useNewText)
        XCTAssertEqual(rev.changes[1].defaultDecision, .unmark)
        letter.apply(rev, decisions: [keys[1]: .delete])
        XCTAssertEqual(letter.comments[keys[0]]?.text, "1. Clarify the theoretical framing.")
        XCTAssertNil(letter.comments[keys[1]])
        XCTAssertEqual(letter.sourceText(letter.comments[keys[2]]!.source[0]), "The sample is small.")
    }

    func testReplacedLetterIsFoundAgain() throws {
        let letter = try sample()
        let pasted = "Decision: major revision.\n\nReviewer 1\nThe sample is small.\n\nSenior Editor\n1. Clarify the theory.\n"
        let all = LetterEdit(location: 0, length: letter.decisionLetter.utf16.count, replacementLength: pasted.utf16.count)
        let rev = letter.revision(newText: pasted, edits: [all])
        XCTAssertEqual(rev.relocated.count, 2)
        XCTAssertEqual(rev.needsAttention.map(\.kind), [.removed])
        var applied = letter
        applied.apply(rev)
        XCTAssertEqual(applied.sourceText(applied.comments[letter.orderedCommentKeys[2]]!.source[0]), "The sample is small.")
        // Undo restores the letter and the ranges.
        var undone = applied
        undone.revert(changesFrom: letter, to: applied)
        XCTAssertEqual(undone, letter)
    }
}
