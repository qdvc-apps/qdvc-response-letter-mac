import AppKit
import ResponseCore
import SwiftUI

/// A map of how comments are linked, in the spirit of a network topology
/// view: one invisible horizontal layer per section (editors above
/// reviewers), a card per comment, solid lines between related comments and
/// dashed arrows for cross-references, from the comment whose response
/// mentions another to that comment. Within a layer, cards are ordered to
/// sit near the cards they link to, which keeps lines short and uncrossed.
struct TraceabilityView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("trace.related") private var showRelated = true
    @AppStorage("trace.references") private var showReferences = true
    @AppStorage("trace.unlinked") private var showUnlinked = false

    static let card = CGSize(width: 188, height: 78)
    static let gap: CGFloat = 26
    static let layerGap: CGFloat = 86
    static let margin: CGFloat = 36
    static let labelHeight: CGFloat = 18

    struct Placed {
        var key: String
        var center: CGPoint
        var layer: Int
    }

    struct MapLayout {
        var cards: [Placed] = []
        var size: CGSize = .zero
        var layers: [(title: String, y: CGFloat)] = []
        func center(_ key: String) -> Placed? { cards.first { $0.key == key } }
    }

    var links: [CommentLink] {
        model.letter.links().filter { link in
            switch link.kind {
            case .related: return showRelated
            case .reference, .pendingReference: return showReferences
            }
        }
    }

    func layout(_ links: [CommentLink]) -> MapLayout {
        var linked = Set<String>()
        for l in links { linked.insert(l.from); linked.insert(l.to) }
        var neighbours: [String: [String]] = [:]
        for l in links {
            neighbours[l.from, default: []].append(l.to)
            neighbours[l.to, default: []].append(l.from)
        }
        var result = MapLayout()
        var x: [String: CGFloat] = [:]
        var layerIndex = 0
        var maxWidth: CGFloat = 0
        var y = Self.margin
        for section in model.letter.sections {
            var keys = section.commentKeys.filter { showUnlinked || linked.contains($0) }
            guard !keys.isEmpty else { continue }
            // Order by where linked cards in the layers above sit (the
            // barycentre heuristic); unconnected cards keep letter order.
            let original = Dictionary(uniqueKeysWithValues: section.commentKeys.enumerated().map { ($1, $0) })
            func barycentre(_ k: String) -> CGFloat? {
                let xs = (neighbours[k] ?? []).compactMap { x[$0] }
                return xs.isEmpty ? nil : xs.reduce(0, +) / CGFloat(xs.count)
            }
            if layerIndex > 0 {
                keys.sort { a, b in
                    switch (barycentre(a), barycentre(b)) {
                    case let (pa?, pb?): return pa == pb ? original[a]! < original[b]! : pa < pb
                    default: return original[a]! < original[b]!
                    }
                }
            }
            result.layers.append((section.title, y))
            let rowY = y + Self.labelHeight + Self.card.height / 2
            for (i, key) in keys.enumerated() {
                let cx = Self.margin + Self.card.width / 2 + CGFloat(i) * (Self.card.width + Self.gap)
                x[key] = cx
                result.cards.append(Placed(key: key, center: CGPoint(x: cx, y: rowY), layer: layerIndex))
            }
            maxWidth = max(maxWidth, Self.margin * 2 + CGFloat(keys.count) * Self.card.width + CGFloat(keys.count - 1) * Self.gap)
            y += Self.labelHeight + Self.card.height + Self.layerGap
            layerIndex += 1
        }
        // Centre each layer on the widest.
        var byLayer: [Int: [Int]] = [:]
        for (i, c) in result.cards.enumerated() { byLayer[c.layer, default: []].append(i) }
        for (_, indices) in byLayer {
            let count = CGFloat(indices.count)
            let width = count * Self.card.width + (count - 1) * Self.gap
            let shift = (maxWidth - Self.margin * 2 - width) / 2
            for i in indices { result.cards[i].center.x += shift }
        }
        result.size = CGSize(width: max(maxWidth, 400), height: y - Self.layerGap + Self.margin)
        return result
    }

    var body: some View {
        let links = self.links
        let layout = self.layout(links)
        let selected = model.traceSelection
        let connected: Set<String> = selected.map { s in
            Set(links.filter { $0.from == s || $0.to == s }.flatMap { [$0.from, $0.to] }).union([s])
        } ?? []
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Toggle("Related", isOn: $showRelated)
                Toggle("Cross-references", isOn: $showReferences)
                Toggle("Unlinked comments", isOn: $showUnlinked)
                Spacer()
                Legend()
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            Divider()
            if layout.cards.isEmpty {
                ContentUnavailableView {
                    Label("No links yet", systemImage: "point.3.connected.trianglepath.dotted")
                } description: {
                    Text("Link related comments in the inspector, or insert cross-references in responses, and they appear here. Tick Unlinked comments to see every comment.")
                }
            } else {
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        // Clicking the background clears the selection.
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { model.traceSelection = nil }
                        ForEach(Array(layout.layers.enumerated()), id: \.offset) { _, layer in
                            Text(layer.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .position(x: Self.margin + 60, y: layer.y + 6)
                                .allowsHitTesting(false)
                        }
                        Canvas { context, _ in
                            for link in links {
                                guard let a = layout.center(link.from), let b = layout.center(link.to) else { continue }
                                let lit = selected == nil || link.from == selected || link.to == selected
                                Self.draw(link, from: a, to: b, lit: lit, in: &context)
                            }
                        }
                        .frame(width: layout.size.width, height: layout.size.height)
                        .allowsHitTesting(false)
                        ForEach(layout.cards, id: \.key) { placed in
                            if let c = model.letter.comments[placed.key] {
                                TraceCard(comment: c, id: model.id(placed.key), selected: selected == placed.key)
                                    .frame(width: Self.card.width, height: Self.card.height)
                                    .opacity(selected == nil || connected.contains(placed.key) ? 1 : 0.35)
                                    .position(placed.center)
                                    .onTapGesture(count: 2) { model.openComment(placed.key) }
                                    .onTapGesture {
                                        model.traceSelection = model.traceSelection == placed.key ? nil : placed.key
                                    }
                                    .contextMenu { CommentContextMenu(keys: [placed.key]) }
                            }
                        }
                    }
                    .frame(width: layout.size.width, height: layout.size.height)
                }
                .background(Color(nsColor: .underPageBackgroundColor))
            }
        }
    }

    /// A line between two cards: from the bottom of the upper card to the
    /// top of the lower one, or an arch over a layer for cards in the same
    /// one.
    static func draw(_ link: CommentLink, from a: Placed, to b: Placed, lit: Bool, in context: inout GraphicsContext) {
        let h = card.height / 2
        var start: CGPoint, end: CGPoint, c1: CGPoint, c2: CGPoint
        if a.layer == b.layer {
            start = CGPoint(x: a.center.x, y: a.center.y - h)
            end = CGPoint(x: b.center.x, y: b.center.y - h)
            let lift = min(70, 24 + abs(b.center.x - a.center.x) / 6)
            c1 = CGPoint(x: start.x, y: start.y - lift)
            c2 = CGPoint(x: end.x, y: end.y - lift)
        } else {
            let down = b.center.y > a.center.y
            start = CGPoint(x: a.center.x, y: a.center.y + (down ? h : -h))
            end = CGPoint(x: b.center.x, y: b.center.y + (down ? -h : h))
            let mid = (end.y - start.y) / 2
            c1 = CGPoint(x: start.x, y: start.y + mid)
            c2 = CGPoint(x: end.x, y: end.y - mid)
        }
        // Related links leave from slightly left of centre and references
        // from slightly right, so both can show between the same two cards.
        let nudge: CGFloat = link.kind == .related ? -10 : 10
        start.x += nudge; end.x += nudge; c1.x += nudge; c2.x += nudge
        var path = Path()
        path.move(to: start)
        path.addCurve(to: end, control1: c1, control2: c2)
        let opacity = lit ? 0.9 : 0.12
        switch link.kind {
        case .related:
            context.stroke(path, with: .color(Color.secondary.opacity(opacity)), lineWidth: 2)
        case .reference, .pendingReference:
            let color = link.kind == .pendingReference ? Color.orange : Color.indigo
            context.stroke(path, with: .color(color.opacity(opacity)),
                           style: StrokeStyle(lineWidth: 1.6, dash: [5, 4]))
            // Arrowhead at the end, along the curve's final direction.
            let dx = end.x - c2.x, dy = end.y - c2.y
            let len = max(0.001, (dx * dx + dy * dy).squareRoot())
            let ux = dx / len, uy = dy / len
            let size: CGFloat = 8
            var head = Path()
            head.move(to: end)
            head.addLine(to: CGPoint(x: end.x - ux * size - uy * size * 0.6, y: end.y - uy * size + ux * size * 0.6))
            head.addLine(to: CGPoint(x: end.x - ux * size + uy * size * 0.6, y: end.y - uy * size - ux * size * 0.6))
            head.closeSubpath()
            context.fill(head, with: .color(color.opacity(opacity)))
        }
    }
}

struct TraceCard: View {
    var comment: Comment
    var id: String
    var selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                TriageDot(triage: comment.triage)
                Text(id).font(.system(.callout, design: .monospaced)).fontWeight(.semibold)
                Spacer(minLength: 0)
                StatusIcon(status: comment.status).font(.caption)
            }
            Text(TextTools.excerpt(comment.text, limit: 110))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(selected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: selected ? 2.5 : 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .help(comment.text)
    }
}

struct Legend: View {
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Capsule().fill(Color.secondary).frame(width: 18, height: 2)
                Text("Related")
            }
            HStack(spacing: 4) {
                Image(systemName: "arrow.right").foregroundStyle(.indigo)
                Text("Cross-reference (from the response that mentions it)")
            }
            HStack(spacing: 4) {
                Image(systemName: "arrow.right").foregroundStyle(.orange)
                Text("Undecided")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}
