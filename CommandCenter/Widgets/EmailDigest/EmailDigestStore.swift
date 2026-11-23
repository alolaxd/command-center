import AppKit
import Foundation

struct MailMessage: Identifiable, Hashable, Sendable {
    let id: Int
    let sender: String
    let subject: String
    let date: Date
    let read: Bool
    let flagged: Bool
    var senderName: String { sender.components(separatedBy: " <").first?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? sender }
    var senderEmail: String {
        guard let a = sender.firstIndex(of: "<"), let b = sender.firstIndex(of: ">") else { return sender }
        return String(sender[sender.index(after: a)..<b])
    }
}

/// Apple Mail via AppleScript (requires the Automation permission prompt on first use).
enum EmailDigestStore {
    static var mailRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").isEmpty }

    static func unreadCount() async -> Int? {
        let (out, _) = await AppleScriptRunner.run("tell application \"Mail\" to get unread count of inbox")
        return out.flatMap(Int.init)
    }

    static func latest(limit: Int = 40) async -> ([MailMessage], String?) {
        let script = """
        tell application "Mail"
            set out to ""
            set n to count of messages of inbox
            if n > \(limit) then set n to \(limit)
            repeat with i from 1 to n
                set m to message i of inbox
                set out to out & (id of m) & tab & (sender of m) & tab & (subject of m) & tab & ((date received of m) as «class isot» as string) & tab & (read status of m) & tab & (flagged status of m) & linefeed
            end repeat
            return out
        end tell
        """
        let (out, err) = await AppleScriptRunner.run(script)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let msgs = (out ?? "").split(separator: "\n").compactMap { line -> MailMessage? in
            let f = line.components(separatedBy: "\t")
            guard f.count >= 6, let id = Int(f[0]) else { return nil }
            return MailMessage(id: id, sender: f[1], subject: f[2], date: fmt.date(from: f[3]) ?? .distantPast,
                               read: f[4] == "true", flagged: f[5] == "true")
        }
        return (msgs.sorted { $0.date > $1.date }, err)
    }

    private static func act(_ id: Int, _ body: String) async -> String? {
        let script = """
        tell application "Mail"
            set m to first message of inbox whose id is \(id)
            \(body)
        end tell
        """
        return await AppleScriptRunner.run(script).1
    }

    static func markRead(_ id: Int, _ read: Bool = true) async -> String? { await act(id, "set read status of m to \(read)") }
    static func flag(_ id: Int, _ on: Bool) async -> String? { await act(id, "set flagged status of m to \(on)") }
    static func archive(_ id: Int) async -> String? {
        await act(id, """
            set acct to account of mailbox of m
            try
                move m to mailbox "Archive" of acct
            on error
                move m to mailbox "All Mail" of acct
            end try
            """)
    }
    static func open(_ id: Int) async { _ = await act(id, "open m\nactivate") }
}
