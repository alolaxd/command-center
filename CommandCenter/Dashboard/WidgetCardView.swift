import SwiftUI

/// Card chrome around every widget: header (drag handle + actions), frosted body, resize handle.
struct WidgetCardView: View {
    let instance: WidgetInstance
    let isFocused: Bool
    let isDragging: Bool
    var isZen = false
    let onMove: (DashboardView.DragPhase) -> Void
    let onResize: (DashboardView.DragPhase) -> Void

    @State private var showSettings = false
    @State private var hovering = false
    private var store: WorkspaceStore { .shared }

    var body: some View {
        let descriptor = WidgetRegistry.descriptor(instance.kind)
        VStack(spacing: 0) {
            header(descriptor)
            Divider().opacity(0.4)
            Group {
                if let descriptor {
                    WidgetContentHost(instance: instance, isZen: isZen, descriptor: descriptor).equatable()
                } else {
                    EmptyStateView(symbol: "questionmark.square.dashed", title: "Unknown widget", message: instance.kind)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isFocused ? Color.accentColor.opacity(0.9) : Color.primary.opacity(0.08), lineWidth: isFocused ? 1.5 : 1)
        )
        .overlay(alignment: .bottomTrailing) { if !isZen { resizeHandle } }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(isDragging ? 0.85 : 1)
        .scaleEffect(isDragging ? 1.01 : 1)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(descriptor?.title ?? "Widget")
        .accessibilityHint("Arrow keys move focus between widgets. Option-arrow moves, Option-Shift-arrow resizes, Return enters Zen mode.")
    }

    private func header(_ d: WidgetDescriptor?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: d?.symbol ?? "square").font(.caption).foregroundStyle(.secondary)
            Text(d?.title ?? instance.kind).font(.caption.weight(.semibold)).lineLimit(1)
            Spacer(minLength: 4)
            if hovering || isFocused || isZen {
                if d?.hasSettings == true {
                    headerButton("slider.horizontal.3", "Widget settings") { showSettings.toggle() }
                        .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                            if let d {
                                ScrollView {
                                    d.makeSettings(instance.config) { store.updateConfig(instance.id, $0) }
                                        .padding()
                                }
                                .frame(width: 340)
                                .frame(maxHeight: 480)
                            }
                        }
                }
                headerButton(isZen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                             isZen ? "Exit Zen mode" : "Zen mode") {
                    store.focusedWidgetID = instance.id
                    withAnimation(.spring(response: 0.35)) { store.toggleZen() }
                }
                Menu {
                    Button("Hide from Dashboard") { withAnimation { store.toggleHidden(instance.id) } }
                    Button("Remove Widget", role: .destructive) { withAnimation { store.removeWidget(instance.id) } }
                } label: { Image(systemName: "ellipsis").font(.caption) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("More actions")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .contentShape(Rectangle())
        .gesture(isZen ? nil : DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { onMove(.changed($0.translation)) }
            .onEnded { _ in onMove(.ended) })
        .onHover { inside in if inside && !isZen { NSCursor.openHand.set() } else { NSCursor.arrow.set() } }
        .accessibilityAddTraits(.isHeader)
    }

    private func headerButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.caption) }
            .buttonStyle(.borderless).help(label).accessibilityLabel(label)
    }

    private var resizeHandle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 8, weight: .semibold))
            .rotationEffect(.degrees(90))
            .foregroundStyle(.tertiary)
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
            .opacity(hovering || isDragging ? 1 : 0.35)
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { onResize(.changed($0.translation)) }
                .onEnded { _ in onResize(.ended) })
            .onHover { inside in if inside { NSCursor.crosshair.set() } else { NSCursor.arrow.set() } }
            .accessibilityLabel("Resize")
            .accessibilityIdentifier("resize-\(instance.id.uuidString)")
    }
}

/// Re-renders the widget only when its own instance data changes (not on every drag frame).
struct WidgetContentHost: View, Equatable {
    let instance: WidgetInstance
    let isZen: Bool
    let descriptor: WidgetDescriptor

    static func == (a: Self, b: Self) -> Bool {
        a.instance.id == b.instance.id && a.instance.config == b.instance.config
            && a.instance.frame.size == b.instance.frame.size && a.isZen == b.isZen
    }

    var body: some View {
        let id = instance.id
        descriptor.makeView(instance, isZen) { WorkspaceStore.shared.updateConfig(id, $0) }
            .id(instance.id)
    }
}
