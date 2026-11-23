import SwiftUI

struct HealthConfiguration: WidgetConfiguration {
    var moveGoal: Double = 500
    var exerciseGoal: Double = 30
    var standGoal: Double = 12
    var stepGoal: Double = 8000
    var waterGoal: Double = 2000
    var waterIncrement: Double = 250

    static func editor(_ config: Binding<Self>) -> some View {
        Form {
            Stepper("Move goal: \(Int(config.wrappedValue.moveGoal)) kcal", value: config.moveGoal, in: 100...2000, step: 50)
            Stepper("Exercise goal: \(Int(config.wrappedValue.exerciseGoal)) min", value: config.exerciseGoal, in: 10...120, step: 5)
            Stepper("Stand goal: \(Int(config.wrappedValue.standGoal)) h", value: config.standGoal, in: 4...16)
            Stepper("Step goal: \(Int(config.wrappedValue.stepGoal))", value: config.stepGoal, in: 1000...30000, step: 500)
            Stepper("Water goal: \(Int(config.wrappedValue.waterGoal)) ml", value: config.waterGoal, in: 500...5000, step: 250)
            Stepper("Water button: +\(Int(config.wrappedValue.waterIncrement)) ml", value: config.waterIncrement, in: 100...1000, step: 50)
        }
    }
}
