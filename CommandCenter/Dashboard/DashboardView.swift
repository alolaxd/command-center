import SwiftUI

/// The grid layout surface: absolute-positioned cards on a snapping grid with drag-to-move,
/// corner-resize, collision push-down + vertical compaction, and keyboard navigation.
struct DashboardView: View {
    let workspace: Workspace
    @AppStorage(SettingsKey.rowHeight) private var rowHeight: Double = 84
    @State private var drag: GridDragSession?
    @FocusState private var focused: UUID?
    private var store: WorkspaceStore { .shared }

    private let gap: CGFloat = 10
    private let pad: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let cols = workspace.columns
            let cellW = max(20, (geo.size.width - pad * 2 - gap * CGFloat(cols - 1)) / CGFloat(cols))
            let metrics = Metrics(cellW: cellW, rowH: rowHeight, gap: gap, pad: pad)
            let visible = workspace.widgets.filter { !$0.isHidden }
            let maxY = max(
                (drag?.preview.map(\.rect.maxY).max() ?? 0),
                visible.map(\.frame.maxY).max() ?? 0) + (drag != nil ? 2 : 0)

            ScrollView(.vertical) {
                ZStack(alignment: .topLeading) {
                    Color.clear.frame(width: geo.size.width, height: max(geo.size.height, metrics.y(maxY) + pad))

                    if let drag {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                            .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .frame(width: metrics.w(drag.target), height: metrics.h(drag.target))
                            .offset(x: metrics.x(drag.target), y: metrics.y(drag.target.y))
                            .accessibilityHidden(true)
                    }

                    ForEach(visible) { inst in
                        card(inst, metrics: metrics)
                    }
                }
                .animation(.spring(response: 0.32, dampingFraction: 0.82), value: animationKey)
            }
            .scrollIndicators(.automatic)
        }
        .onChange(of: focused) { _, new in if let new { store.focusedWidgetID = new } }
        .onChange(of: store.focusedWidgetID) { _, new in if focused != new { focused = new } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(workspace.name) dashboard")
    }

    /// Changes whenever any widget's displayed position changes (drives spring animation).
    private var animationKey: [GridRect] {
        if let drag { return drag.preview.filter { $0.id != drag.id }.map(\.rect) }
        return workspace.widgets.map(\.frame)
    }

    struct Metrics {
        let cellW: CGFloat, rowH: CGFloat, gap: CGFloat, pad: CGFloat
        func x(_ r: GridRect) -> CGFloat { pad + CGFloat(r.x) * (cellW + gap) }
        func y(_ row: Int) -> CGFloat { pad + CGFloat(row) * (rowH + gap) }
        func w(_ r: GridRect) -> CGFloat { CGFloat(r.w) * cellW + CGFloat(r.w - 1) * gap }
        func h(_ r: GridRect) -> CGFloat { CGFloat(r.h) * rowH + CGFloat(r.h - 1) * gap }
    }

    @ViewBuilder
    private func card(_ inst: WidgetInstance, metrics m: Metrics) -> some View {
        let isDragging = drag?.id == inst.id
        let rect: GridRect = {
            if let drag, !isDragging, let p = drag.preview.first(where: { $0.id == inst.id }) { return p.rect }
            return isDragging ? drag!.origin : inst.frame
        }()
        // While resizing, the card follows the pointer but never extends past the grid's right edge.
        let maxW = m.w(GridRect(x: rect.x, y: 0, w: workspace.columns - rect.x, h: 1))
        let width = isDragging && drag?.mode == .resize ? min(maxW, max(m.cellW, m.w(rect) + drag!.translation.width)) : m.w(rect)
        let height = isDragging && drag?.mode == .resize ? max(m.rowH, m.h(rect) + drag!.translation.height) : m.h(rect)
        let offset = isDragging && drag?.mode == .move ? drag!.translation : .zero

        WidgetCardView(
            instance: inst,
            isFocused: focused == inst.id,
            isDragging: isDragging,
            onMove: { phase in handleDrag(inst, mode: .move, phase: phase, metrics: m) },
            onResize: { phase in handleDrag(inst, mode: .resize, phase: phase, metrics: m) }
        )
        .frame(width: width, height: height)
        .offset(x: m.x(rect) + offset.width, y: m.y(rect.y) + offset.height)
        .zIndex(isDragging ? 10 : 0)
        // The dragged card tracks the pointer 1:1; only the other widgets spring into place.
        .transaction { if isDragging { $0.animation = nil } }
        // Clicking a card focuses it for arrow-key navigation (drags still start immediately).
        .focusable()
        .focusEffectDisabled()
        .focused($focused, equals: inst.id)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .return], phases: .down) { press in
            handleKey(press, id: inst.id)
        }
    }

    enum DragPhase { case changed(CGSize), ended }

    private func handleDrag(_ inst: WidgetInstance, mode: GridDragSession.Mode, phase: DragPhase, metrics m: Metrics) {
        switch phase {
        case .changed(let t):
            if drag == nil || drag?.id != inst.id {
                drag = GridDragSession(id: inst.id, mode: mode, baseline: store.gridItems(workspace), columns: workspace.columns)
                focused = inst.id
            }
            drag?.update(translation: t, cellWidth: m.cellW, rowHeight: m.rowH, gap: m.gap)
        case .ended:
            guard let d = drag else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                if d.target != d.origin { store.commit(d.preview) }
                drag = nil
            }
        }
    }

    private func handleKey(_ press: KeyPress, id: UUID) -> KeyPress.Result {
        if press.key == .return {
            store.focusedWidgetID = id
            withAnimation(.spring(response: 0.35)) { store.toggleZen() }
            return .handled
        }
        let dir: GridLayoutEngine.Direction
        switch press.key {
        case .leftArrow: dir = .left
        case .rightArrow: dir = .right
        case .upArrow: dir = .up
        default: dir = .down
        }
        let (dx, dy): (Int, Int) = switch dir { case .left: (-1, 0); case .right: (1, 0); case .up: (0, -1); case .down: (0, 1) }
        if press.modifiers.contains(.option) && press.modifiers.contains(.shift) {
            withAnimation(.spring(response: 0.3)) { store.nudge(id, dw: dx, dh: dy) }
            return .handled
        }
        if press.modifiers.contains(.option) {
            withAnimation(.spring(response: 0.3)) { store.nudge(id, dx: dx, dy: dy) }
            return .handled
        }
        if press.modifiers.isEmpty, let next = GridLayoutEngine.neighbor(of: id, direction: dir, in: store.gridItems(workspace)) {
            focused = next
            return .handled
        }
        return .ignored
    }
}
