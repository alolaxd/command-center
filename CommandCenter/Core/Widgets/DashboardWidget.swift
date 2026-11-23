import SwiftUI

enum WidgetCategory: String, CaseIterable, Codable, Identifiable {
    case productivity = "Productivity"
    case aiDev = "AI & Development"
    case system = "System & Hardware"
    case information = "Communication & Information"
    case finance = "Finance & Data"
    case lifestyle = "Health & Lifestyle"
    case utility = "Meta & Utility"
    var id: String { rawValue }
}

/// User-editable settings for a widget instance. Persisted as JSON inside the workspace layout.
/// Each configuration supplies its own editor, which doubles as its configuration schema.
protocol WidgetConfiguration: Codable, Equatable {
    associatedtype Editor: View = EmptyView
    init()
    @MainActor @ViewBuilder static func editor(_ config: Binding<Self>) -> Editor
}

extension WidgetConfiguration where Editor == EmptyView {
    @MainActor static func editor(_ config: Binding<Self>) -> EmptyView { EmptyView() }
}

struct EmptyConfiguration: WidgetConfiguration {}

/// Everything a widget instance gets from its host.
struct WidgetContext<Configuration: WidgetConfiguration> {
    let instanceID: UUID
    let size: GridSize
    let config: Configuration
    let isZen: Bool
    let updateConfig: @MainActor (Configuration) -> Void
    var bus: WidgetBus { .shared }
}

/// The plugin contract. Every dashboard panel is a self-contained module conforming to this.
@MainActor
protocol DashboardWidget: View {
    associatedtype Configuration: WidgetConfiguration = EmptyConfiguration
    static var kind: String { get }
    static var title: String { get }
    static var symbol: String { get }
    static var summary: String { get }
    static var category: WidgetCategory { get }
    static var minSize: GridSize { get }
    static var defaultSize: GridSize { get }
    /// How often the widget wants `refresh` ticks while visible. `nil` = event driven only.
    static var refreshInterval: TimeInterval? { get }
    init(context: WidgetContext<Configuration>)
}

extension DashboardWidget {
    static var minSize: GridSize { GridSize(2, 2) }
    static var defaultSize: GridSize { GridSize(3, 3) }
    static var refreshInterval: TimeInterval? { nil }

    static var descriptor: WidgetDescriptor {
        WidgetDescriptor(
            kind: kind, title: title, symbol: symbol, summary: summary, category: category,
            minSize: minSize, defaultSize: defaultSize, refreshInterval: refreshInterval,
            defaultConfig: (try? JSONEncoder().encode(Configuration())) ?? Data("{}".utf8),
            hasSettings: Configuration.Editor.self != EmptyView.self,
            makeView: { instance, isZen, update in
                let ctx = WidgetContext<Configuration>(
                    instanceID: instance.id, size: instance.frame.size,
                    config: decodeConfig(instance.config), isZen: isZen,
                    updateConfig: { update((try? JSONEncoder().encode($0)) ?? instance.config) })
                return AnyView(Self(context: ctx))
            },
            makeSettings: { data, update in
                AnyView(ConfigurationEditorHost<Configuration>(initial: decodeConfig(data), onChange: {
                    update((try? JSONEncoder().encode($0)) ?? data)
                }))
            })
    }

    static func decodeConfig(_ data: Data) -> Configuration {
        (try? JSONDecoder().decode(Configuration.self, from: data)) ?? Configuration()
    }
}

/// Type-erased widget metadata + factories, used by the registry and the host.
struct WidgetDescriptor: Identifiable {
    let kind: String
    let title: String
    let symbol: String
    let summary: String
    let category: WidgetCategory
    let minSize: GridSize
    let defaultSize: GridSize
    let refreshInterval: TimeInterval?
    let defaultConfig: Data
    let hasSettings: Bool
    let makeView: @MainActor (WidgetInstance, Bool, @escaping @MainActor (Data) -> Void) -> AnyView
    let makeSettings: @MainActor (Data, @escaping @MainActor (Data) -> Void) -> AnyView
    var id: String { kind }
}

private struct ConfigurationEditorHost<C: WidgetConfiguration>: View {
    @State var config: C
    let onChange: @MainActor (C) -> Void
    init(initial: C, onChange: @escaping @MainActor (C) -> Void) {
        _config = State(initialValue: initial)
        self.onChange = onChange
    }
    var body: some View {
        C.editor($config)
            .onChange(of: config) { _, new in onChange(new) }
    }
}
