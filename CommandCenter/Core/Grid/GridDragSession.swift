import CoreGraphics
import Foundation

/// State of one in-progress move/resize gesture. Every preview is computed from the layout
/// as it was when the gesture began, so widgets pushed aside return to their original
/// spots as soon as the dragged widget moves away again.
struct GridDragSession {
    enum Mode { case move, resize }

    let id: UUID
    let mode: Mode
    let origin: GridRect
    let baseline: [LayoutItem]
    let columns: Int
    let minSize: GridSize
    private(set) var translation: CGSize = .zero
    private(set) var target: GridRect
    private(set) var preview: [LayoutItem]

    init(id: UUID, mode: Mode, baseline: [LayoutItem], columns: Int) {
        let item = baseline.first { $0.id == id }
        self.id = id
        self.mode = mode
        self.baseline = baseline
        self.columns = columns
        self.origin = item?.rect ?? GridRect(x: 0, y: 0, w: 1, h: 1)
        self.minSize = item?.minSize ?? GridSize(1, 1)
        self.target = origin
        self.preview = baseline
    }

    /// Feeds a new gesture translation (points). Returns true when the snapped target changed.
    @discardableResult
    mutating func update(translation t: CGSize, cellWidth: CGFloat, rowHeight: CGFloat, gap: CGFloat) -> Bool {
        translation = t
        let d = GridLayoutEngine.cellDelta(translation: t, cellWidth: cellWidth, rowHeight: rowHeight, gap: gap)
        var next = origin
        switch mode {
        case .move:
            next.x += d.dx; next.y += d.dy
        case .resize:
            // Resizing grows/shrinks from the top-left corner; the origin never moves.
            next.w = min(columns - origin.x, max(minSize.w, origin.w + d.dx))
            next.h = max(minSize.h, origin.h + d.dy)
        }
        next = GridLayoutEngine.clamp(next, minSize: minSize, columns: columns)
        guard next != target else { return false }
        target = next
        preview = GridLayoutEngine.place(baseline, id: id, at: next, columns: columns)
        return true
    }

    func rect(for itemID: UUID) -> GridRect? { preview.first { $0.id == itemID }?.rect }
}
