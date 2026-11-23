import EventKit
import Foundation

/// Shared EventKit store + permission handling for Reminders and Calendar.
@MainActor @Observable
final class EventKitService {
    static let shared = EventKitService()
    let store = EKEventStore()
    var remindersAuthorized = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    var eventsAuthorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    /// Bumped whenever the store changes externally; views observe it to reload.
    var changeToken = 0

    private init() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            Task { @MainActor in EventKitService.shared.changeToken += 1 }
        }
    }

    func requestReminders() async {
        remindersAuthorized = (try? await store.requestFullAccessToReminders()) ?? false
    }

    func requestEvents() async {
        eventsAuthorized = (try? await store.requestFullAccessToEvents()) ?? false
    }
}

/// Parses "Buy milk tomorrow 3pm" into a title and a date using NSDataDetector.
enum NaturalDateParser {
    struct Result { var title: String; var date: Date?; var hasTime: Bool; var duration: TimeInterval? }

    static func parse(_ input: String) -> Result {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
              let match = detector.matches(in: input, range: NSRange(input.startIndex..., in: input)).first,
              let range = Range(match.range, in: input), let date = match.date else {
            return Result(title: input.trimmingCharacters(in: .whitespaces), date: nil, hasTime: false, duration: nil)
        }
        var title = input
        title.removeSubrange(range)
        title = title.replacingOccurrences(of: #"\s+(at|on|by|due)\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let matched = String(input[range]).lowercased()
        let hasTime = matched.range(of: #"\d(:\d\d)?\s*(am|pm)|\d:\d\d|noon|midnight|morning|evening|tonight"#, options: .regularExpression) != nil
        return Result(title: title.isEmpty ? input : title, date: date, hasTime: hasTime,
                      duration: match.duration > 0 ? match.duration : nil)
    }
}
