import AppKit
import SwiftUI

/// Panes stacked vertically with draggable dividers, used instead of
/// SwiftUI's VSplitView. Every pane is given exactly the width and height
/// available, measured with a GeometryReader, so nothing inside a pane (a
/// long line, a menu, a text view's own idea of its size) can make it wider
/// than the window. Heights are shared fractions, remembered between
/// comments and launches under `storageKey`.
struct PaneStack: View {
    struct Item: Identifiable {
        let id: String
        var minHeight: CGFloat
        /// Starting share of the height.
        var weight: CGFloat
        var view: AnyView
    }

    let items: [Item]
    @AppStorage private var stored: String
    @State private var dragStart: [CGFloat]?

    static let dividerHeight: CGFloat = 7

    init(storageKey: String, items: [Item]) {
        self.items = items
        _stored = AppStorage(wrappedValue: "", "panes.\(storageKey)")
    }

    /// The panes' shares of the height, summing to 1.
    private var fractions: [CGFloat] {
        let saved = stored.split(separator: ",").compactMap { Double($0) }.map { CGFloat($0) }
        if saved.count == items.count, saved.allSatisfy({ $0 > 0 }) {
            let total = saved.reduce(0, +)
            return saved.map { $0 / total }
        }
        let total = items.map(\.weight).reduce(0, +)
        return items.map { $0.weight / max(total, 0.001) }
    }

    /// Heights for the given space, honouring each pane's minimum.
    private func heights(_ fractions: [CGFloat], available: CGFloat) -> [CGFloat] {
        var h = zip(fractions, items).map { max($0 * available, $1.minHeight) }
        let excess = h.reduce(0, +) - available
        if excess > 0 {
            // Take the excess from the panes that are above their minimum.
            var remaining = excess
            for i in h.indices.reversed() where remaining > 0 {
                let spare = h[i] - items[i].minHeight
                let take = min(spare, remaining)
                h[i] -= take
                remaining -= take
            }
        }
        return h
    }

    var body: some View {
        GeometryReader { geo in
            let available = max(0, geo.size.height - Self.dividerHeight * CGFloat(max(items.count - 1, 0)))
            let current = fractions
            let h = heights(current, available: available)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    item.view
                        .frame(width: geo.size.width, height: h[i])
                        .clipped()
                    if i < items.count - 1 {
                        PaneDivider()
                            .gesture(
                                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                    .onChanged { value in
                                        let start = dragStart ?? current
                                        if dragStart == nil { dragStart = current }
                                        drag(index: i, by: value.translation.height, from: start, available: available)
                                    }
                                    .onEnded { _ in dragStart = nil }
                            )
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }

    /// Moves the divider below pane `index`, trading height with the pane
    /// below it.
    private func drag(index i: Int, by dy: CGFloat, from start: [CGFloat], available: CGFloat) {
        guard available > 0, i + 1 < items.count else { return }
        var heightsNow = start.map { $0 * available }
        let pair = heightsNow[i] + heightsNow[i + 1]
        let top = min(max(heightsNow[i] + dy, items[i].minHeight), pair - items[i + 1].minHeight)
        heightsNow[i] = top
        heightsNow[i + 1] = pair - top
        stored = heightsNow.map { String(format: "%.4f", $0 / available) }.joined(separator: ",")
    }
}

/// A thin line with a taller grab area and the up-down resize cursor.
struct PaneDivider: View {
    @State private var hovering = false

    var body: some View {
        ZStack {
            Color.clear
            Divider()
        }
        .frame(height: PaneStack.dividerHeight)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside && !hovering { NSCursor.resizeUpDown.push() }
            if !inside && hovering { NSCursor.pop() }
            hovering = inside
        }
        .onDisappear { if hovering { NSCursor.pop() } }
    }
}
