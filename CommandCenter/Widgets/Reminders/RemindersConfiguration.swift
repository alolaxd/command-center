import EventKit
import SwiftUI

struct RemindersConfiguration: WidgetConfiguration {
    var listIDs: [String] = []
    var upcomingHours = 48
    var showUndated = true

    static func editor(_ config: Binding<Self>) -> some View {
        Form {
            Section("Lists (none selected = all)") {
                ForEach(RemindersStore.lists(), id: \.calendarIdentifier) { cal in
                    Toggle(cal.title, isOn: Binding(
                        get: { config.wrappedValue.listIDs.contains(cal.calendarIdentifier) },
                        set: { on in
                            config.wrappedValue.listIDs.removeAll { $0 == cal.calendarIdentifier }
                            if on { config.wrappedValue.listIDs.append(cal.calendarIdentifier) }
                        }))
                }
            }
            Stepper("Upcoming window: \(config.wrappedValue.upcomingHours)h", value: config.upcomingHours, in: 12...168, step: 12)
            Toggle("Show reminders without a date", isOn: config.showUndated)
        }
    }
}
