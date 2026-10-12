import Foundation

/// RFC 4180 CSV, for spreadsheets.
public enum CSV {
    public static func field(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r")
            || s.hasPrefix(" ") || s.hasSuffix(" ") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    public static func row(_ fields: [String]) -> String {
        fields.map(field).joined(separator: ",")
    }

    /// One row per comment: ID, section, triage, status, comment, ideas,
    /// related, response (as plain text), response word count.
    public static func comments(_ letter: ResponseLetter) -> String {
        let ids = letter.idMap()
        var lines = [row(["ID", "Section", "Triage", "Status", "Comment", "Ideas", "Related", "Response", "Words"])]
        for section in letter.sections {
            for key in section.commentKeys {
                guard let c = letter.comments[key] else { continue }
                let response = c.responseText.plainText { letter.tokenDisplay($0, ids: ids) }
                lines.append(row([
                    ids[key] ?? "",
                    section.title,
                    c.triage == .none ? "" : c.triage.rawValue,
                    c.status.label,
                    c.text,
                    c.ideas.map { "• " + $0 }.joined(separator: "\n"),
                    c.related.compactMap { ids[$0] }.joined(separator: ", "),
                    response,
                    String(TextStats.wordCount(response)),
                ]))
            }
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }
}
