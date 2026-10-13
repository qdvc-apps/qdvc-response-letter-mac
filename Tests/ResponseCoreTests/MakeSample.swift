import XCTest
@testable import ResponseCore

final class MakeSampleTests: XCTestCase {
  func testMakeSample() throws {
    guard ProcessInfo.processInfo.environment["MAKE_SAMPLE"] != nil else { return }
    // Regenerates sample-workspace/ (and, for checking, exports in /tmp):
    //   MAKE_SAMPLE=$PWD/sample-workspace swift test --filter MakeSampleTests
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let decision = try String(contentsOf: root.appendingPathComponent("tools/sample-decision-letter.txt"), encoding: .utf8)
    let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MAKE_SAMPLE"]!)
    try? FileManager.default.removeItem(at: out)
    var l = try Workspace.create(at: out, decisionLetter: decision,
      settings: LetterSettings(title: "Response to the editors and reviewers", manuscript: "JIS-2026-0417"))
    let ns = l.decisionLetter as NSString
    func at(_ s: String) -> Int { let r = ns.range(of: s); precondition(r.location != NSNotFound, s); return r.location }
    func mark(_ s: String, _ sec: String) throws -> String {
      let r = ns.range(of: s); precondition(r.location != NSNotFound, s)
      return try l.markComment(SourceRange(location: r.location, length: r.length), inSection: sec)
    }
    let se = l.addSection(role: .seniorEditor, anchor: at("\nSenior Editor\n") + 1)
    let ae = l.addSection(role: .associateEditor, anchor: at("\nAssociate Editor\n") + 1)
    let r1 = l.addSection(role: .reviewer, number: 1, anchor: at("Reviewer #1"))
    let r2 = l.addSection(role: .reviewer, number: 2, anchor: at("Reviewer #2"))
    let se1 = try mark("The reviewers and the AE see real promise in this paper. The field access is unusual and the question matters. My main concern echoes theirs: the theoretical contribution is not yet clear. At present the paper reads as a rich description of how one firm adopted digital twins, and the reader is left asking what we learn about organising more generally.", se)
    let se2 = try mark("Second, the methods section needs to say much more about how the data were analysed. How did you move from interview transcripts to the three mechanisms in Figure 2?", se)
    let se3 = try mark("Finally, please shorten the paper. The current draft is 14,200 words; our limit is 11,000 including references.", se)
    let ae1 = try mark("1. Both reviewers question the framing around sociomateriality (R1 comment 2, R2 comment 1). I share their view that the paper does not need this framing and that it obscures your contribution. Consider building instead on the literature on routines, which seems to fit your data better.", ae)
    let ae2 = try mark("2. The paper needs a clearer account of the boundary conditions of your findings. Would the same mechanisms appear in a firm with a less hierarchical maintenance organisation?", ae)
    let ae3 = try mark("3. Please make sure the abstract and introduction state the contribution in one or two sentences.", ae)
    let r11 = try mark("1. The research question shifts between the introduction (how digital twins change maintenance work) and the discussion (how organisations govern data). Please settle on one.", r1)
    let r12 = try mark("2. The sociomateriality framing feels bolted on. The concepts of entanglement and performativity are introduced on page 6 but are hardly used in the findings.", r1)
    let r13 = try mark("3. I would like to know more about the sample. How many interviews were conducted, with whom, and over what period? The paper mentions \"around fifty\" interviews in one place and 47 in another.", r1)
    let r14 = try mark("4. The quotations in the findings are very long. Some run to half a page. Shorter quotes, with more of your own interpretation around them, would help the reader.", r1)
    let r15 = try mark("5. Minor: the paper uses \"digital twin\" and \"digital shadow\" interchangeably. These are distinct concepts in the engineering literature.", r1)
    let r21 = try mark("1. Like the other reviewer I struggled with the sociomateriality lens. If the authors want to keep it, they need to show what it explains that other lenses cannot.", r2)
    let r22 = try mark("2. The three mechanisms (anticipating, rehearsing and deferring) are interesting, but it is not clear how they relate to each other. Are they sequential? Do they reinforce one another? A process model would help.", r2)
    let r23 = try mark("3. The discussion should engage with the work on predictive maintenance in operations management, which has studied similar settings.", r2)
    let r24 = try mark("4. Table 3 is hard to read. Consider splitting it into two tables.", r2)

    let words = l.addVariable(name: "Word count", value: "10,940 words")
    let interviews = l.addVariable(name: "Interviews", value: "47 semi-structured interviews")
    let theory = l.addVariable(name: "Theory section", value: "Section 2.2 (pp. 7–9)")
    let methods = l.addVariable(name: "Analysis section", value: "Section 3.3 (pp. 12–14)")
    let model = l.addVariable(name: "Process model figure", value: "Figure 3")
    let contribution = l.addVariable(name: "Contribution statement",
      value: "We show how digital twins reorganise maintenance work by shifting its focus from repairing failures to anticipating them.")

    func set(_ k: String, _ t: Triage, _ s: Status, _ ideas: [String], _ response: String) {
      l.comments[k]?.triage = t; l.comments[k]?.status = s; l.comments[k]?.ideas = ideas; l.comments[k]?.response = response
    }
    set(se1, .red, .drafted, ["Reframe around routines (see {{ref:\(ae1)}})", "Write the contribution in two sentences first, then rebuild the intro", "Discuss with Sam and Priya before drafting"],
        "Thank you for this encouraging assessment and for pinpointing the paper's main weakness. We have rebuilt the paper around a single theoretical contribution, which the introduction now states as follows:\n> {{var:\(contribution)}}\nAs suggested by the Associate Editor (see our response to {{ref:\(ae1)}}), we now draw on the literature on organisational routines rather than sociomateriality. The new theoretical background is in {{var:\(theory)}}.")
    set(se2, .yellow, .drafted, ["Add a coding table to {{var:\(methods)}}", "Describe the three rounds of coding", "Sample details overlap with {{ref:\(r13)}}", "Mention the member checks with the maintenance planners"],
        "We agree that the analysis was under-described. {{var:\(methods)}} now explains how we moved from the {{var:\(interviews)}} to the three mechanisms, in three steps:\n- open coding of the transcripts and field notes;\n- grouping codes into **second-order themes**, shown in a new coding table (Appendix B);\n- comparing the themes across the three depots to arrive at the mechanisms.\nSee also our response to {{ref:\(r13)}} on the sample.")
    set(se3, .green, .final, ["Now {{var:\(words)}}: cut the second case vignette", "Merge sections 5.2 and 5.3", "Shorter quotes ({{ref:\(r14)}}) save most of it"],
        "The revised manuscript is {{var:\(words)}} including references, within the limit of 11,000. We shortened the findings mainly by shortening the quotations (see our response to {{ref:\(r14)}}).")
    set(ae1, .red, .drafted, ["**Big change:** drop sociomateriality (also asked in {{ref:\(r12)}} and {{ref:\(r21)}})", "Routines: Feldman & Pentland; Pentland et al. on *routine dynamics*", "New framing goes in {{var:\(theory)}}"],
        "We are grateful for this clear steer. We have removed the sociomateriality framing and now build on the literature on routine dynamics, which, as you suggest, fits our data much better. The new framing is set out in {{var:\(theory)}}. This also addresses the concerns raised in {{ref:\(r12)}} and {{ref:\(r21)}}.")
    set(ae2, .yellow, .todo, ["New paragraph in the discussion on boundary conditions", "Hierarchy, safety regulation, asset age", "Tie to the process model ({{var:\(model)}})"], "")
    set(ae3, .green, .final, [],
        "Both the abstract and the introduction now state the contribution in one sentence:\n> {{var:\(contribution)}}")
    set(r11, .yellow, .drafted, ["Settle on maintenance work, not data governance", "Check the intro still matches {{var:\(contribution)}}"],
        "Thank you. We have settled on the first question, how digital twins change maintenance work, and removed the material on data governance from the discussion.")
    set(r12, .red, .drafted, ["Same as {{ref:\(ae1)}}"], "Please see our response to {{ref:\(ae1)}}.")
    set(r13, .green, .final, ["It's {{var:\(interviews)}}: fix the 'around fifty' on p. 11"],
        "We conducted {{var:\(interviews)}} between March 2024 and June 2025, with maintenance planners, technicians, data engineers and managers. The \"around fifty\" was an error, now corrected. A new table in {{var:\(methods)}} lists the interviews by role and depot.")
    set(r14, .green, .drafted, [], "We have shortened every quotation in the findings to at most four lines and added more of our own interpretation around them.")
    set(r15, .none, .todo, [], "")
    set(r21, .red, .drafted, ["Same as {{ref:\(ae1)}}"], "Please see our response to {{ref:\(ae1)}}.")
    set(r22, .yellow, .drafted, ["Draw the process model as {{var:\(model)}}", "Mechanisms are partly sequential: anticipating enables rehearsing", "Fits the routines framing in {{ref:\(ae1)}}"],
        "This is a very helpful suggestion. We now present a process model ({{var:\(model)}}) that shows how the three mechanisms relate.")
    set(r23, .none, .todo, ["Ask Priya for the OM references"], "")
    set(r24, .green, .final, [], "We have split Table 3 into Tables 3 and 4.")
    l.setRelated(ae1, r12, true); l.setRelated(ae1, r21, true); l.setRelated(se1, ae1, true)
    l.setRelated(se2, r13, true); l.setRelated(se3, r14, true); l.setRelated(se1, ae3, true)
    l.setRelated(ae2, r22, true); l.setRelated(r11, se1, true)
    l.opening = "Dear Professor Lindqvist,\nThank you for the opportunity to revise our manuscript, *Digital twins and the reorganisation of maintenance work: A field study*. We are grateful to you, the Associate Editor and the two reviewers for their careful and constructive comments.\nThe main changes are a new theoretical framing around routine dynamics, a fuller account of our analysis, and a shorter paper of {{var:\(words)}}. Below we respond to each comment in turn."
    l.closing = "Thank you again for your guidance. We look forward to hearing from you.\nYours sincerely,\nThe authors"
    try Workspace.save(l, parts: Workspace.allParts(of: l), to: out)
    let back = try Workspace.load(out)
    XCTAssertEqual(back.letter, l)
    try DocxExport.responseLetter(l).write(to: URL(fileURLWithPath: NSTemporaryDirectory() + "sample-response.docx"))
    try DocxExport.discussion(l).write(to: URL(fileURLWithPath: NSTemporaryDirectory() + "sample-discussion.docx"))
    try CSV.comments(l).write(toFile: NSTemporaryDirectory() + "sample-comments.csv", atomically: true, encoding: .utf8)
    print("ISSUES", l.issues().map(\.message))
  }
}
