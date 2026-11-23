import Foundation

/// Size of a widget in grid cells.
struct GridSize: Codable, Hashable, Sendable {
    var w: Int
    var h: Int
    init(_ w: Int, _ h: Int) { self.w = w; self.h = h }
}

/// Position + size of a widget in grid cells. Origin is top-left.
struct GridRect: Codable, Hashable, Sendable {
    var x: Int
    var y: Int
    var w: Int
    var h: Int

    var maxX: Int { x + w }
    var maxY: Int { y + h }
    var size: GridSize { GridSize(w, h) }

    func intersects(_ other: GridRect) -> Bool {
        x < other.maxX && other.x < maxX && y < other.maxY && other.y < maxY
    }
}

/// A placed item the layout engine can reason about.
struct LayoutItem: Hashable, Sendable {
    var id: UUID
    var rect: GridRect
    var minSize: GridSize
}
