import SwiftUI

/// Reference implementation of the widget protocol: configuration, view model, refresh.
struct PlaceholderWidget: DashboardWidget {
    static let kind = "placeholder"
    static let title = "Placeholder"
    static let symbol = "square.dashed"
    static let summary = "A template widget demonstrating the DashboardWidget protocol."
    static let category = WidgetCategory.utility
    static let minSize = GridSize(1, 1)
    static let defaultSize = GridSize(2, 2)
    static let refreshInterval: TimeInterval? = 1

    let context: WidgetContext<PlaceholderConfiguration>
    @State private var vm = PlaceholderViewModel()

    init(context: WidgetContext<PlaceholderConfiguration>) { self.context = context }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(context.config.message).font(.headline)
            Text(vm.now.formatted(date: .omitted, time: .standard)).font(.title2.monospacedDigit())
            Text("\(context.size.w)×\(context.size.h) cells · ticks: \(vm.ticks)").font(.caption).foregroundStyle(.secondary)
        }
        .refreshing(every: Self.refreshInterval) { vm.tick() }
    }
}

struct PlaceholderConfiguration: WidgetConfiguration {
    var message = "Hello, Command Center"
    static func editor(_ config: Binding<Self>) -> some View {
        Form { TextField("Message", text: config.message) }
    }
}

@MainActor @Observable
final class PlaceholderViewModel {
    var now = Date()
    var ticks = 0
    func tick() { now = Date(); ticks += 1 }
}
