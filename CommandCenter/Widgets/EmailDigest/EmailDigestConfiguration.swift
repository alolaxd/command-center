import SwiftUI

struct EmailDigestConfiguration: WidgetConfiguration {
    var vips: [String] = []
    var vipOnly = false
    var unreadOnly = false
    var count = 10

    static func editor(_ config: Binding<Self>) -> some View {
        Form {
            Stepper("Show \(config.wrappedValue.count) messages", value: config.count, in: 5...30)
            Toggle("Unread only", isOn: config.unreadOnly)
            Toggle("VIP senders only", isOn: config.vipOnly)
            TextField("VIP senders (emails or names, comma separated)", text: Binding(
                get: { config.wrappedValue.vips.joined(separator: ", ") },
                set: { config.wrappedValue.vips = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }),
                      axis: .vertical)
            Text("Uses Apple Mail. IMAP accounts should be added to Mail.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
