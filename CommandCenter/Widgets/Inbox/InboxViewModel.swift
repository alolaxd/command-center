import AVFoundation
import Foundation

@MainActor @Observable
final class InboxViewModel {
    var items: [InboxItem] = []
    var triaged: [InboxItem] = []
    var recording = false
    var suggestion: [String: String] = [:]
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var recordingName: String?
    @ObservationIgnored var player: AVAudioPlayer?

    func load(_ config: InboxConfiguration) {
        items = InboxStore.untriaged()
        triaged = config.showTriaged ? InboxStore.recentTriaged() : []
    }

    func isStale(_ item: InboxItem, _ config: InboxConfiguration) -> Bool {
        item.triagedAt == nil && item.createdAt < Date().addingTimeInterval(-Double(config.staleDays) * 86400)
    }

    // MARK: Triage
    func toReminder(_ item: InboxItem) {
        if RemindersStore.add(item.text) != nil { InboxStore.markTriaged(item, to: "reminder") }
        else { WidgetBus.shared.toast("Grant Reminders access in the Reminders widget first") }
    }

    func toEvent(_ item: InboxItem) {
        if CalendarStore.create(fromText: item.text) != nil { InboxStore.markTriaged(item, to: "calendar") }
        else { WidgetBus.shared.toast("Grant Calendar access in the Calendar widget first") }
    }

    func toNote(_ item: InboxItem) {
        let title = String(item.text.split(separator: "\n").first?.prefix(60) ?? "Inbox note")
        var body = "# \(title)\n\n\(item.text)\n"
        if let att = item.attachment { body += "\nAttachment: \(AppPaths.attachments.appendingPathComponent(att).path)\n" }
        _ = NotesStore.create(title: title, body: body)
        InboxStore.markTriaged(item, to: "note")
    }

    func toKanban(_ item: InboxItem) {
        KanbanStore.addCard(title: item.text, column: .backlog, link: item.kind == .link ? .url(item.text) : nil)
        InboxStore.markTriaged(item, to: "kanban")
    }

    func suggest(_ item: InboxItem) async {
        suggestion[item.id] = "…"
        let prompt = """
        Classify this captured inbox item into exactly one destination: reminder, calendar, note, kanban, or delete.
        Reply as: <destination> — <one short reason>.
        Item: \(item.text)
        """
        do { suggestion[item.id] = try await AIService.shared.complete([AIMessage(role: .user, content: prompt)], effort: "low") }
        catch { suggestion[item.id] = error.localizedDescription }
    }

    // MARK: Voice memos
    func toggleRecording(_ config: InboxConfiguration) {
        if recording {
            recorder?.stop()
            recording = false
            if let name = recordingName { InboxStore.add("Voice memo \(Date().formatted(date: .omitted, time: .shortened))", kind: .audio, attachment: name) }
            load(config)
            return
        }
        AVCaptureDevice.requestAccess(for: .audio) { ok in
            Task { @MainActor in
                guard ok else { WidgetBus.shared.toast("Microphone access denied"); return }
                let name = UUID().uuidString + ".m4a"
                let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1]
                self.recorder = try? AVAudioRecorder(url: AppPaths.attachments.appendingPathComponent(name), settings: settings)
                self.recordingName = name
                self.recording = self.recorder?.record() ?? false
            }
        }
    }

    func play(_ item: InboxItem) {
        guard let url = item.attachmentURL else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }
}
