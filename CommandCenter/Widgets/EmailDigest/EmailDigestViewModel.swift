import Foundation

@MainActor @Observable
final class EmailDigestViewModel {
    var messages: [MailMessage] = []
    var unread: Int?
    var error: String?
    var running = EmailDigestStore.mailRunning

    func refresh(_ config: EmailDigestConfiguration) async {
        running = EmailDigestStore.mailRunning
        guard running else { return }   // never launch Mail implicitly
        unread = await EmailDigestStore.unreadCount()
        let (msgs, err) = await EmailDigestStore.latest()
        error = err
        messages = msgs
    }

    func isVIP(_ m: MailMessage, _ config: EmailDigestConfiguration) -> Bool {
        config.vips.contains { m.sender.localizedCaseInsensitiveContains($0) }
    }

    func visible(_ config: EmailDigestConfiguration) -> [MailMessage] {
        messages.filter { (!config.unreadOnly || !$0.read) && (!config.vipOnly || isVIP($0, config)) }.prefix(config.count).map { $0 }
    }

    func perform(_ op: () async -> String?, _ config: EmailDigestConfiguration) async {
        if let e = await op() { WidgetBus.shared.toast(e) }
        await refresh(config)
    }
}
