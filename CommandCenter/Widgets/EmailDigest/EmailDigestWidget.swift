import SwiftUI

struct EmailDigestWidget: DashboardWidget {
    static let kind = "email"
    static let title = "Email"
    static let symbol = "envelope"
    static let summary = "Unread count and latest messages from Apple Mail with archive / read / flag and a VIP filter."
    static let category = WidgetCategory.information
    static let defaultSize = GridSize(4, 3)
    static let refreshInterval: TimeInterval? = 120

    let context: WidgetContext<EmailDigestConfiguration>
    @State private var vm = EmailDigestViewModel()

    init(context: WidgetContext<EmailDigestConfiguration>) { self.context = context }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !vm.running {
                EmptyStateView(symbol: "envelope", title: "Mail isn't running", message: "Command Center reads Apple Mail while it's open.",
                               action: ("Open Mail", {
                                   NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Mail.app"), configuration: .init())
                                   Task { try? await Task.sleep(for: .seconds(3)); await vm.refresh(context.config) }
                               }))
            } else {
                HStack {
                    Text("\(vm.unread ?? 0)").font(.title2.monospacedDigit().weight(.semibold))
                    Text("unread").foregroundStyle(.secondary)
                    Spacer()
                    Toggle("VIP", isOn: Binding(get: { context.config.vipOnly }, set: { var c = context.config; c.vipOnly = $0; context.updateConfig(c) }))
                        .toggleStyle(.button).controlSize(.small)
                    Button { Task { await vm.refresh(context.config) } } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless).accessibilityLabel("Refresh")
                }
                if let e = vm.error { Text(e).font(.caption).foregroundStyle(.red).lineLimit(2) }
                List(vm.visible(context.config)) { m in row(m) }
                    .listStyle(.plain).scrollContentBackground(.hidden)
            }
        }
        .refreshing(every: Self.refreshInterval) { await vm.refresh(context.config) }
    }

    private func row(_ m: MailMessage) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Circle().fill(m.read ? Color.clear : Color.accentColor).frame(width: 7, height: 7).padding(.top, 5)
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    if vm.isVIP(m, context.config) { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                    Text(m.senderName).font(.callout.weight(m.read ? .regular : .semibold)).lineLimit(1)
                    Spacer()
                    Text(m.date.formatted(Calendar.current.isDateInToday(m.date) ? .dateTime.hour().minute() : .dateTime.month().day()))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text(m.subject).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            if m.flagged { Image(systemName: "flag.fill").font(.caption).foregroundStyle(.orange) }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { Task { await EmailDigestStore.open(m.id) } }
        .contextMenu {
            Button("Open in Mail") { Task { await EmailDigestStore.open(m.id) } }
            Button(m.read ? "Mark as Unread" : "Mark as Read") { Task { await vm.perform({ await EmailDigestStore.markRead(m.id, !m.read) }, context.config) } }
            Button(m.flagged ? "Unflag" : "Flag") { Task { await vm.perform({ await EmailDigestStore.flag(m.id, !m.flagged) }, context.config) } }
            Button("Archive") { Task { await vm.perform({ await EmailDigestStore.archive(m.id) }, context.config) } }
            Divider()
            Button("Send to Inbox Widget") { InboxCapture.capture("Email from \(m.senderName): \(m.subject)") }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(m.read ? "" : "Unread, ")\(m.senderName): \(m.subject)")
    }
}
