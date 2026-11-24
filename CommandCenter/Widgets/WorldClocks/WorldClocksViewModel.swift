import Foundation

@MainActor @Observable
final class WorldClocksViewModel {
    var now = Date()
    var contacts: [String: [String]] = [:]

    func tick() { now = Date() }

    func loadContacts(_ config: WorldClocksConfiguration) async {
        contacts = config.showContacts ? await WorldClocksStore.contactsByZone(config.zones) : [:]
    }

    func hour(_ z: WorldClocksStore.Zone, at date: Date) -> Int {
        var c = Calendar(identifier: .gregorian); c.timeZone = z.tz
        return c.component(.hour, from: date)
    }

    /// "UTC−8", "UTC+5:30" (local zone labelled "Local").
    func offset(_ z: WorldClocksStore.Zone) -> String {
        let mins = z.tz.secondsFromGMT(for: now) / 60
        let sign = mins >= 0 ? "+" : "−"
        let base = "UTC" + sign + "\(abs(mins) / 60)" + (abs(mins) % 60 == 0 ? "" : String(format: ":%02d", abs(mins) % 60))
        return z.identifier == TimeZone.current.identifier ? "Local · " + base : base
    }
}
