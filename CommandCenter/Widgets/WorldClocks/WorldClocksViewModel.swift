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

    func offset(_ z: WorldClocksStore.Zone) -> String {
        let diff = (z.tz.secondsFromGMT(for: now) - TimeZone.current.secondsFromGMT(for: now)) / 60
        if diff == 0 { return "local" }
        let h = Double(diff) / 60
        return (h > 0 ? "+" : "") + (h.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(h))h" : String(format: "%.1fh", h))
    }
}
