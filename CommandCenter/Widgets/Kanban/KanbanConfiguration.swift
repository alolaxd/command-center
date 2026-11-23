import SwiftUI

struct KanbanConfiguration: WidgetConfiguration {
    enum Swimlanes: String, Codable, CaseIterable { case none = "None", lane = "By Project/Tag" }
    var wipLimits: [String: Int] = [KanbanColumn.inProgress.rawValue: 3, KanbanColumn.review.rawValue: 2]
    var swimlanes: Swimlanes = .none
    var hiddenColumns: [String] = []

    static func editor(_ config: Binding<Self>) -> some View {
        Form {
            Picker("Swimlanes", selection: config.swimlanes) { ForEach(Swimlanes.allCases, id: \.self) { Text($0.rawValue) } }
            Section("WIP limits (0 = none)") {
                ForEach(KanbanColumn.allCases) { col in
                    Stepper("\(col.rawValue): \(config.wrappedValue.wipLimits[col.rawValue] ?? 0)",
                            value: Binding(get: { config.wrappedValue.wipLimits[col.rawValue] ?? 0 },
                                           set: { config.wrappedValue.wipLimits[col.rawValue] = $0 == 0 ? nil : $0 }),
                            in: 0...20)
                }
            }
            Section("Visible columns") {
                ForEach(KanbanColumn.allCases) { col in
                    Toggle(col.rawValue, isOn: Binding(
                        get: { !config.wrappedValue.hiddenColumns.contains(col.rawValue) },
                        set: { on in
                            config.wrappedValue.hiddenColumns.removeAll { $0 == col.rawValue }
                            if !on { config.wrappedValue.hiddenColumns.append(col.rawValue) }
                        }))
                }
            }
        }
    }
}
