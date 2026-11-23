import Contacts
import Foundation

enum WorldClocksStore {
    struct Zone: Codable, Hashable, Identifiable {
        var id: String { identifier }
        var identifier: String
        var label: String
        var tz: TimeZone { TimeZone(identifier: identifier) ?? .current }
        var city: String { label.isEmpty ? (identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? identifier) : label }
    }

    static func search(_ q: String) -> [String] {
        guard !q.isEmpty else { return [] }
        return TimeZone.knownTimeZoneIdentifiers.filter { $0.localizedCaseInsensitiveContains(q.replacingOccurrences(of: " ", with: "_")) }.prefix(12).map { $0 }
    }

    /// Hours (0..<24, in `reference` zone) during which every zone is inside working hours.
    static func overlap(zones: [Zone], workStart: Int, workEnd: Int, reference: TimeZone, on day: Date = Date()) -> [Int] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = reference
        let start = cal.startOfDay(for: day)
        return (0..<24).filter { h in
            let instant = start.addingTimeInterval(Double(h) * 3600 + 1800)   // middle of the hour
            return zones.allSatisfy { z in
                var c = Calendar(identifier: .gregorian); c.timeZone = z.tz
                let local = c.component(.hour, from: instant)
                let weekday = c.component(.weekday, from: instant)
                return local >= workStart && local < workEnd && weekday != 1 && weekday != 7
            }
        }
    }

    /// Contacts whose postal address city matches each zone's city (optional, needs Contacts access).
    static func contactsByZone(_ zones: [Zone]) async -> [String: [String]] {
        let store = CNContactStore()
        guard (try? await store.requestAccess(for: .contacts)) == true else { return [:] }
        return await Task.detached {
            var out: [String: [String]] = [:]
            let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPostalAddressesKey] as [CNKeyDescriptor]
            try? store.enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { c, _ in
                for addr in c.postalAddresses {
                    let city = addr.value.city.lowercased()
                    guard !city.isEmpty else { continue }
                    for z in zones where z.city.lowercased() == city {
                        out[z.identifier, default: []].append("\(c.givenName) \(c.familyName)".trimmingCharacters(in: .whitespaces))
                    }
                }
            }
            return out
        }.value
    }
}
