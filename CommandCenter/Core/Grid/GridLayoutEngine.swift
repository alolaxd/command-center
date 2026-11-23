import Foundation

/// Pure layout logic for the dashboard grid. Behaves like a vertically compacting
/// grid: the item being manipulated wins its target cell, colliding items are pushed
/// down, then everything floats up to fill gaps.
enum GridLayoutEngine {

    static func clamp(_ rect: GridRect, minSize: GridSize, columns: Int) -> GridRect {
        var r = rect
        r.w = max(minSize.w, min(r.w, columns))
        r.h = max(minSize.h, r.h)
        r.x = max(0, min(r.x, columns - r.w))
        r.y = max(0, r.y)
        return r
    }

    /// Places `id` at `target`. Only widgets that actually collide are pushed straight down
    /// (cascading as needed); every other widget keeps its exact position. No auto-compaction,
    /// so moving or resizing one widget never reshuffles unrelated ones.
    static func place(_ items: [LayoutItem], id: UUID, at target: GridRect, columns: Int) -> [LayoutItem] {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return items }
        var moving = items[idx]
        moving.rect = clamp(target, minSize: moving.minSize, columns: columns)

        var placed: [LayoutItem] = [moving]
        let others = items.enumerated()
            .filter { $0.offset != idx }
            .map(\.element)
            .sorted { ($0.rect.y, $0.rect.x) < ($1.rect.y, $1.rect.x) }

        for var item in others {
            item.rect = clamp(item.rect, minSize: item.minSize, columns: columns)
            while let blocker = placed.first(where: { $0.rect.intersects(item.rect) }) {
                item.rect.y = blocker.rect.maxY
            }
            placed.append(item)
        }
        let order = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.id, $0.offset) })
        return placed.sorted { order[$0.id, default: 0] < order[$1.id, default: 0] }
    }

    /// Floats every item up as far as it can go. `pinned` is compacted first so it keeps priority.
    static func compact(_ items: [LayoutItem], pinned: UUID? = nil) -> [LayoutItem] {
        let ordered = items.sorted { a, b in
            if a.id == pinned { return b.id != pinned ? true : false }
            if b.id == pinned { return false }
            return (a.rect.y, a.rect.x) < (b.rect.y, b.rect.x)
        }
        var result: [LayoutItem] = []
        for var item in ordered {
            while item.rect.y > 0 {
                var probe = item.rect
                probe.y -= 1
                if result.contains(where: { $0.rect.intersects(probe) }) { break }
                item.rect = probe
            }
            // An item compacted earlier may sit below a pinned item that floated over it.
            while let blocker = result.first(where: { $0.rect.intersects(item.rect) }) {
                item.rect.y = blocker.rect.maxY
            }
            result.append(item)
        }
        // Preserve original ordering for stable identity.
        let order = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.id, $0.offset) })
        return result.sorted { order[$0.id, default: 0] < order[$1.id, default: 0] }
    }

    /// First free top-left slot that fits `size`, scanning rows top to bottom.
    static func firstFreeSlot(for size: GridSize, in items: [LayoutItem], columns: Int) -> GridRect {
        let w = min(size.w, columns)
        var y = 0
        while true {
            for x in 0...(columns - w) {
                let candidate = GridRect(x: x, y: y, w: w, h: size.h)
                if !items.contains(where: { $0.rect.intersects(candidate) }) { return candidate }
            }
            y += 1
        }
    }

    static func hasOverlaps(_ items: [LayoutItem]) -> Bool {
        for (i, a) in items.enumerated() { for b in items[(i + 1)...] where a.rect.intersects(b.rect) { return true } }
        return false
    }

    /// Converts a point offset (in points) to a snapped cell delta.
    static func cellDelta(translation: CGSize, cellWidth: CGFloat, rowHeight: CGFloat, gap: CGFloat) -> (dx: Int, dy: Int) {
        let dx = Int((translation.width / (cellWidth + gap)).rounded())
        let dy = Int((translation.height / (rowHeight + gap)).rounded())
        return (dx, dy)
    }

    /// Nearest neighbour in a direction, for keyboard navigation.
    enum Direction { case left, right, up, down }

    static func neighbor(of id: UUID, direction: Direction, in items: [LayoutItem]) -> UUID? {
        guard let from = items.first(where: { $0.id == id })?.rect else { return nil }
        let cx = Double(from.x) + Double(from.w) / 2, cy = Double(from.y) + Double(from.h) / 2
        let candidates = items.filter { $0.id != id }.compactMap { item -> (UUID, Double)? in
            let r = item.rect
            let x = Double(r.x) + Double(r.w) / 2, y = Double(r.y) + Double(r.h) / 2
            let dx = x - cx, dy = y - cy
            switch direction {
            case .left where dx < 0 && abs(dy) <= abs(dx) + Double(from.h): break
            case .right where dx > 0 && abs(dy) <= abs(dx) + Double(from.h): break
            case .up where dy < 0 && abs(dx) <= abs(dy) + Double(from.w): break
            case .down where dy > 0 && abs(dx) <= abs(dy) + Double(from.w): break
            default: return nil
            }
            return (item.id, dx * dx + dy * dy)
        }
        return candidates.min { $0.1 < $1.1 }?.0
    }
}
