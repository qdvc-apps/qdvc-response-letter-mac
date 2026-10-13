import Foundation

/// Writes .docx files: the response letter (A4, portrait) and a discussion
/// version for co-authors (A4, landscape, with triage colours and ideas).
/// The documents use Word styles (Title, Quote, List Bullet), so they can be
/// restyled in Word.
public enum DocxExport {
    // A4 in twentieths of a point, 2.54 cm margins.
    static let a4Short = 11906
    static let a4Long = 16838
    static let margin = 1440

    public static func responseLetter(_ letter: ResponseLetter, date: Date = Date()) -> Data {
        let ids = letter.idMap()
        let w = Writer(letter: letter, ids: ids)
        // The ID column, then the comments and the responses at equal widths.
        let half = (a4Short - 2 * margin - 1000) / 2
        let widths = [1000, half, a4Short - 2 * margin - 1000 - half]
        var body = ""
        body += w.titleBlock()
        body += w.richParagraphs(RichText(markup: letter.opening))
        if !letter.opening.isEmpty { body += w.paragraph("") }
        body += w.tableStart(widths: widths)
        body += w.row(cells: [
            w.cell(width: widths[0], shading: "D9D9D9", content: w.paragraph("", keepNext: true)),
            w.cell(width: widths[1], shading: "D9D9D9", content: w.paragraph(w.run("Editor/Reviewer Comments", bold: true), keepNext: true)),
            w.cell(width: widths[2], shading: "D9D9D9", content: w.paragraph(w.run("Response", bold: true), keepNext: true)),
        ], header: true)
        for section in letter.sections where !section.commentKeys.isEmpty {
            body += w.sectionRow(section.heading, widths: widths)
            for key in section.commentKeys {
                guard let c = letter.comments[key] else { continue }
                body += w.row(cells: [
                    w.cell(width: widths[0], content: w.paragraph(w.run(ids[key] ?? ""))),
                    w.cell(width: widths[1], content: w.plainParagraphs(c.text)),
                    w.cell(width: widths[2], content: w.richParagraphs(c.responseText, emptyAsParagraph: true)),
                ])
            }
        }
        body += "</w:tbl>"
        if !letter.closing.isEmpty {
            body += w.paragraph("")
            body += w.richParagraphs(RichText(markup: letter.closing))
        }
        return package(letter: letter, body: body, landscape: false, date: date)
    }

    public static func discussion(_ letter: ResponseLetter, date: Date = Date()) -> Data {
        let ids = letter.idMap()
        let w = Writer(letter: letter, ids: ids)
        // The ID, then the comment and the draft response at equal widths,
        // with the ideas between them.
        let half = (a4Long - 2 * margin - 1300 - 3700) / 2
        let widths = [1300, half, 3700, a4Long - 2 * margin - 1300 - 3700 - half]
        let p = letter.progress()
        var body = ""
        body += w.paragraph(w.run(letter.settings.title.isEmpty ? "Response letter" : letter.settings.title,
                                  bold: true, size: letter.settings.fontSize + 4), style: "Title")
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        var subtitle = "Discussion draft for co-authors, \(formatter.string(from: date))."
        if !letter.settings.manuscript.isEmpty { subtitle = "Manuscript \(letter.settings.manuscript). " + subtitle }
        body += w.paragraph(w.run(subtitle, italic: true))
        let triage = "Triage: \(p.count(.green)) trivial, \(p.count(.yellow)) with a clear solution, \(p.count(.red)) needing discussion"
            + (p.count(.none) > 0 ? ", \(p.count(.none)) not yet triaged" : "") + "."
        let status = "Responses: \(p.count(.final)) final, \(p.count(.drafted)) drafted, \(p.count(.todo)) to do, of \(p.total)."
        body += w.paragraph(w.run(triage + " " + status))
        body += w.tableStart(widths: widths)
        body += w.row(cells: [
            w.cell(width: widths[0], shading: "D9D9D9", content: w.paragraph("", keepNext: true)),
            w.cell(width: widths[1], shading: "D9D9D9", content: w.paragraph(w.run("Comment", bold: true), keepNext: true)),
            w.cell(width: widths[2], shading: "D9D9D9", content: w.paragraph(w.run("Triage and ideas", bold: true), keepNext: true)),
            w.cell(width: widths[3], shading: "D9D9D9", content: w.paragraph(w.run("Draft response", bold: true), keepNext: true)),
        ], header: true)
        for section in letter.sections where !section.commentKeys.isEmpty {
            body += w.sectionRow(section.heading, widths: widths)
            for key in section.commentKeys {
                guard let c = letter.comments[key] else { continue }
                var idCell = w.paragraph(w.run(ids[key] ?? "", bold: true))
                idCell += w.paragraph(w.run(c.triage.label, size: letter.settings.fontSize - 2))
                idCell += w.paragraph(w.run(c.status.label, italic: true, size: letter.settings.fontSize - 2))
                // Ideas are markup lines: rendered as bullets, with their
                // Variables and Cross-references.
                let bullets = c.ideas.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map { idea -> RichParagraph in
                    var p = RichText(markup: idea).paragraphs.first ?? RichParagraph()
                    p.block = .bullet
                    return p
                }
                var ideas = w.richParagraphs(RichText(paragraphs: bullets))
                let related = c.related.compactMap { ids[$0] }
                if !related.isEmpty {
                    ideas += w.paragraph(w.run("Related: " + related.joined(separator: ", "), italic: true))
                }
                if ideas.isEmpty { ideas = w.paragraph("") }
                body += w.row(cells: [
                    w.cell(width: widths[0], shading: triageFill(c.triage), content: idCell),
                    w.cell(width: widths[1], content: w.plainParagraphs(c.text)),
                    w.cell(width: widths[2], content: ideas),
                    w.cell(width: widths[3], content: w.richParagraphs(c.responseText, emptyAsParagraph: true)),
                ])
            }
        }
        body += "</w:tbl>"
        return package(letter: letter, body: body, landscape: true, date: date)
    }

    /// Excel's conditional-formatting fills: easy to read, easy to print.
    static func triageFill(_ t: Triage) -> String? {
        switch t {
        case .none: return nil
        case .green: return "C6EFCE"
        case .yellow: return "FFEB9C"
        case .red: return "FFC7CE"
        }
    }

    // MARK: - Package

    static let wNS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    static let rNS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    static let header = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"

    static func package(letter: ResponseLetter, body: String, landscape: Bool, date: Date) -> Data {
        let size = landscape
            ? "<w:pgSz w:w=\"\(a4Long)\" w:h=\"\(a4Short)\" w:orient=\"landscape\"/>"
            : "<w:pgSz w:w=\"\(a4Short)\" w:h=\"\(a4Long)\"/>"
        let sect = "<w:sectPr><w:footerReference w:type=\"default\" r:id=\"rId4\"/>\(size)"
            + "<w:pgMar w:top=\"\(margin)\" w:right=\"\(margin)\" w:bottom=\"\(margin)\" w:left=\"\(margin)\" "
            + "w:header=\"708\" w:footer=\"708\" w:gutter=\"0\"/></w:sectPr>"
        let document = header + "<w:document xmlns:w=\"\(wNS)\" xmlns:r=\"\(rNS)\"><w:body>"
            + body + sect + "</w:body></w:document>"

        var zip = ZipWriter(date: date)
        zip.add("[Content_Types].xml", contentTypes)
        zip.add("_rels/.rels", rootRels)
        zip.add("docProps/core.xml", coreProperties(title: letter.settings.title, date: date))
        zip.add("docProps/app.xml", appProperties)
        zip.add("word/document.xml", document)
        zip.add("word/styles.xml", styles(letter.settings))
        zip.add("word/numbering.xml", numbering)
        zip.add("word/settings.xml", settingsXML)
        zip.add("word/footer1.xml", footer)
        zip.add("word/_rels/document.xml.rels", documentRels)
        return zip.finish()
    }

    static let contentTypes = header + """
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
    <Default Extension="xml" ContentType="application/xml"/>\
    <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>\
    <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>\
    <Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>\
    <Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>\
    <Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>\
    <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>\
    <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>\
    </Types>
    """

    static let rootRels = header + """
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>\
    <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>\
    <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>\
    </Relationships>
    """

    static let documentRels = header + """
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>\
    <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>\
    <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/>\
    <Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>\
    </Relationships>
    """

    static let appProperties = header + """
    <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">\
    <Application>QDVC Response Letter</Application></Properties>
    """

    static func coreProperties(title: String, date: Date) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let stamp = iso.string(from: date)
        return header + "<cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" "
            + "xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:dcterms=\"http://purl.org/dc/terms/\" "
            + "xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\">"
            + "<dc:title>\(Writer.escape(title))</dc:title><dc:creator>QDVC Response Letter</dc:creator>"
            + "<dcterms:created xsi:type=\"dcterms:W3CDTF\">\(stamp)</dcterms:created>"
            + "<dcterms:modified xsi:type=\"dcterms:W3CDTF\">\(stamp)</dcterms:modified>"
            + "</cp:coreProperties>"
    }

    static let settingsXML = header + """
    <w:settings xmlns:w="\(wNS)"><w:defaultTabStop w:val="720"/>\
    <w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat>\
    </w:settings>
    """

    static let footer = header + """
    <w:ftr xmlns:w="\(wNS)" xmlns:r="\(rNS)"><w:p><w:pPr><w:jc w:val="center"/></w:pPr>\
    <w:r><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>\
    <w:r><w:fldChar w:fldCharType="separate"/></w:r><w:r><w:t>1</w:t></w:r><w:r><w:fldChar w:fldCharType="end"/></w:r>\
    </w:p></w:ftr>
    """

    static let numbering = header + """
    <w:numbering xmlns:w="\(wNS)"><w:abstractNum w:abstractNumId="0"><w:multiLevelType w:val="singleLevel"/>\
    <w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="\u{2022}"/><w:lvlJc w:val="left"/>\
    <w:pPr><w:ind w:left="357" w:hanging="357"/></w:pPr></w:lvl></w:abstractNum>\
    <w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num></w:numbering>
    """

    static func styles(_ s: LetterSettings) -> String {
        let font = Writer.escape(s.fontName)
        let size = Int((s.fontSize * 2).rounded())
        var quoteRun = ""
        switch s.quoteStyle {
        case .italic: quoteRun = "<w:rPr><w:i/><w:iCs/></w:rPr>"
        case .blue: quoteRun = "<w:rPr><w:color w:val=\"1F4E9A\"/></w:rPr>"
        case .plain: quoteRun = ""
        }
        return header + "<w:styles xmlns:w=\"\(wNS)\">"
            + "<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii=\"\(font)\" w:hAnsi=\"\(font)\" w:eastAsia=\"\(font)\" w:cs=\"\(font)\"/>"
            + "<w:sz w:val=\"\(size)\"/><w:szCs w:val=\"\(size)\"/></w:rPr></w:rPrDefault>"
            + "<w:pPrDefault><w:pPr><w:spacing w:after=\"120\" w:line=\"252\" w:lineRule=\"auto\"/></w:pPr></w:pPrDefault></w:docDefaults>"
            + "<w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\"><w:name w:val=\"Normal\"/><w:qFormat/></w:style>"
            + "<w:style w:type=\"paragraph\" w:styleId=\"Title\"><w:name w:val=\"Title\"/><w:basedOn w:val=\"Normal\"/><w:next w:val=\"Normal\"/><w:qFormat/>"
            + "<w:pPr><w:spacing w:after=\"240\"/></w:pPr><w:rPr><w:b/><w:bCs/><w:sz w:val=\"\(size + 8)\"/><w:szCs w:val=\"\(size + 8)\"/></w:rPr></w:style>"
            + "<w:style w:type=\"paragraph\" w:styleId=\"Quote\"><w:name w:val=\"Quote\"/><w:basedOn w:val=\"Normal\"/><w:qFormat/>"
            + "<w:pPr><w:ind w:left=\"425\" w:right=\"284\"/></w:pPr>\(quoteRun)</w:style>"
            + "<w:style w:type=\"paragraph\" w:styleId=\"ListBullet\"><w:name w:val=\"List Bullet\"/><w:basedOn w:val=\"Normal\"/>"
            + "<w:pPr><w:numPr><w:numId w:val=\"1\"/></w:numPr><w:spacing w:after=\"60\"/></w:pPr></w:style>"
            + "<w:style w:type=\"table\" w:default=\"1\" w:styleId=\"TableNormal\"><w:name w:val=\"Normal Table\"/><w:uiPriority w:val=\"99\"/>"
            + "<w:semiHidden/><w:unhideWhenUsed/><w:tblPr><w:tblInd w:w=\"0\" w:type=\"dxa\"/><w:tblCellMar>"
            + "<w:top w:w=\"0\" w:type=\"dxa\"/><w:left w:w=\"108\" w:type=\"dxa\"/><w:bottom w:w=\"0\" w:type=\"dxa\"/>"
            + "<w:right w:w=\"108\" w:type=\"dxa\"/></w:tblCellMar></w:tblPr></w:style>"
            + "</w:styles>"
    }

    // MARK: - XML writing

    struct Writer {
        var letter: ResponseLetter
        var ids: [String: String]

        static func escape(_ s: String) -> String {
            var out = ""
            out.reserveCapacity(s.count)
            for scalar in s.unicodeScalars {
                switch scalar {
                case "&": out += "&amp;"
                case "<": out += "&lt;"
                case ">": out += "&gt;"
                case "\"": out += "&quot;"
                default:
                    let v = scalar.value
                    // Only characters XML 1.0 allows.
                    if v == 0x9 || v == 0xA || v == 0xD || (v >= 0x20 && v <= 0xD7FF)
                        || (v >= 0xE000 && v <= 0xFFFD) || v >= 0x10000 {
                        out.unicodeScalars.append(scalar)
                    }
                }
            }
            return out
        }

        func run(_ text: String, bold: Bool = false, italic: Bool = false, color: String? = nil,
                 size: Double? = nil) -> String {
            guard !text.isEmpty else { return "" }
            var props = ""
            if bold { props += "<w:b/><w:bCs/>" }
            if italic { props += "<w:i/><w:iCs/>" }
            if let color { props += "<w:color w:val=\"\(color)\"/>" }
            if let size {
                let half = Int((size * 2).rounded())
                props += "<w:sz w:val=\"\(half)\"/><w:szCs w:val=\"\(half)\"/>"
            }
            var out = "<w:r>" + (props.isEmpty ? "" : "<w:rPr>\(props)</w:rPr>")
            let lines = text.components(separatedBy: "\n")
            for (i, line) in lines.enumerated() {
                if i > 0 { out += "<w:br/>" }
                let parts = line.components(separatedBy: "\t")
                for (j, part) in parts.enumerated() {
                    if j > 0 { out += "<w:tab/>" }
                    if !part.isEmpty { out += "<w:t xml:space=\"preserve\">\(Self.escape(part))</w:t>" }
                }
            }
            return out + "</w:r>"
        }

        func paragraph(_ runs: String, style: String? = nil, keepNext: Bool = false) -> String {
            var props = ""
            if let style { props += "<w:pStyle w:val=\"\(style)\"/>" }
            if keepNext { props += "<w:keepNext/>" }
            return "<w:p>" + (props.isEmpty ? "" : "<w:pPr>\(props)</w:pPr>") + runs + "</w:p>"
        }

        func titleBlock() -> String {
            var out = ""
            if !letter.settings.title.isEmpty {
                out += paragraph(run(letter.settings.title), style: "Title")
            }
            if !letter.settings.manuscript.isEmpty {
                out += paragraph(run("Manuscript: " + letter.settings.manuscript))
            }
            return out
        }

        /// Comment text: blank lines separate paragraphs; single line breaks
        /// stay line breaks.
        func plainParagraphs(_ text: String) -> String {
            let blocks = text.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .newlines) }
                .filter { !$0.isEmpty }
            if blocks.isEmpty { return paragraph("") }
            return blocks.map { paragraph(run($0)) }.joined()
        }

        func richParagraphs(_ rich: RichText, emptyAsParagraph: Bool = false) -> String {
            if rich.paragraphs.isEmpty { return emptyAsParagraph ? paragraph("") : "" }
            return rich.paragraphs.map { p in
                let runs = p.inlines.map { inline -> String in
                    switch inline {
                    case .text(let t, let s): return run(t, bold: s.bold, italic: s.italic)
                    case .token(let t, let s):
                        return run(letter.tokenDisplay(t, ids: ids), bold: s.bold, italic: s.italic)
                    }
                }.joined()
                switch p.block {
                case .normal: return paragraph(runs)
                case .quote: return paragraph(runs, style: "Quote")
                case .bullet: return paragraph(runs, style: "ListBullet")
                }
            }.joined()
        }

        func tableStart(widths: [Int]) -> String {
            let total = widths.reduce(0, +)
            let border = "w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"000000\""
            return "<w:tbl><w:tblPr><w:tblW w:w=\"\(total)\" w:type=\"dxa\"/>"
                + "<w:tblBorders><w:top \(border)/><w:left \(border)/><w:bottom \(border)/><w:right \(border)/>"
                + "<w:insideH \(border)/><w:insideV \(border)/></w:tblBorders>"
                + "<w:tblLayout w:type=\"fixed\"/>"
                + "<w:tblCellMar><w:top w:w=\"57\" w:type=\"dxa\"/><w:left w:w=\"85\" w:type=\"dxa\"/>"
                + "<w:bottom w:w=\"57\" w:type=\"dxa\"/><w:right w:w=\"85\" w:type=\"dxa\"/></w:tblCellMar>"
                + "<w:tblLook w:val=\"04A0\" w:firstRow=\"1\" w:lastRow=\"0\" w:firstColumn=\"1\" w:lastColumn=\"0\" w:noHBand=\"0\" w:noVBand=\"1\"/>"
                + "</w:tblPr><w:tblGrid>" + widths.map { "<w:gridCol w:w=\"\($0)\"/>" }.joined() + "</w:tblGrid>"
        }

        func cell(width: Int, shading: String? = nil, content: String) -> String {
            var props = "<w:tcW w:w=\"\(width)\" w:type=\"dxa\"/>"
            if let shading { props += "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"\(shading)\"/>" }
            return "<w:tc><w:tcPr>\(props)</w:tcPr>\(content.isEmpty ? paragraph("") : content)</w:tc>"
        }

        /// The header row appears once, at the top of the table (it is not
        /// repeated on later pages); it is kept on one page.
        func row(cells: [String], header: Bool = false, cantSplit: Bool = false) -> String {
            var props = ""
            if cantSplit || header { props += "<w:cantSplit/>" }
            return "<w:tr>" + (props.isEmpty ? "" : "<w:trPr>\(props)</w:trPr>") + cells.joined() + "</w:tr>"
        }

        /// The black band that starts a section, its heading in bold white
        /// in the second column; kept with the first comment below it.
        func sectionRow(_ heading: String, widths: [Int]) -> String {
            let cells = widths.enumerated().map { i, width in
                cell(width: width, shading: "000000",
                     content: paragraph(i == 1 ? run(heading, bold: true, color: "FFFFFF") : "", keepNext: true))
            }
            return row(cells: cells, cantSplit: true)
        }
    }
}
