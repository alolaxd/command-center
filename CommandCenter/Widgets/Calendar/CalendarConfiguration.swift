import SwiftUI

struct CalendarConfiguration: WidgetConfiguration {
    enum Mode: String, Codable, CaseIterable { case day = "Day", threeDay = "3 Day", week = "Week" }
    var mode: Mode = .threeDay
    var calendarIDs: [String] = []
    var startHour = 7
    var hourHeight: Double = 40

    var days: Int { switch mode { case .day: 1; case .threeDay: 3; case .week: 7 } }

    static func editor(_ config: Binding<Self>) -> some View {
        Form {
            Picker("Default view", selection: config.mode) { ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) } }
            Stepper("Scroll to \(config.wrappedValue.startHour):00", value: config.startHour, in: 0...20)
            Slider(value: config.hourHeight, in: 24...80) { Text("Hour height") }
            Section("Calendars (none = all)") {
                ForEach(CalendarStore.calendars(), id: \.calendarIdentifier) { cal in
                    Toggle(cal.title, isOn: Binding(
                        get: { config.wrappedValue.calendarIDs.contains(cal.calendarIdentifier) },
                        set: { on in
                            config.wrappedValue.calendarIDs.removeAll { $0 == cal.calendarIdentifier }
                            if on { config.wrappedValue.calendarIDs.append(cal.calendarIdentifier) }
                        }))
                }
            }
        }
    }
}
