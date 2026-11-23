import SwiftUI

struct PomodoroConfiguration: WidgetConfiguration {
    var focusMinutes = 25
    var shortBreak = 5
    var longBreak = 15
    var longBreakEvery = 4
    var autoStartBreaks = true
    var blockApps = false
    var blockedBundleIDs: [String] = ["com.tinyspeck.slackmacgap", "com.hnc.Discord", "com.apple.MobileSMS"]
    var habitName = "Focus"

    static func editor(_ config: Binding<Self>) -> some View {
        Form {
            Stepper("Focus: \(config.wrappedValue.focusMinutes) min", value: config.focusMinutes, in: 5...90, step: 5)
            Stepper("Short break: \(config.wrappedValue.shortBreak) min", value: config.shortBreak, in: 1...30)
            Stepper("Long break: \(config.wrappedValue.longBreak) min", value: config.longBreak, in: 5...60, step: 5)
            Stepper("Long break every \(config.wrappedValue.longBreakEvery)", value: config.longBreakEvery, in: 2...8)
            Toggle("Auto-start breaks", isOn: config.autoStartBreaks)
            TextField("Log to habit", text: config.habitName)
            Section("Distraction blocking") {
                Toggle("Hide distracting apps during focus", isOn: config.blockApps)
                TextField("Bundle IDs (comma separated)", text: Binding(
                    get: { config.wrappedValue.blockedBundleIDs.joined(separator: ", ") },
                    set: { config.wrappedValue.blockedBundleIDs = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }),
                          axis: .vertical)
            }
        }
    }
}
