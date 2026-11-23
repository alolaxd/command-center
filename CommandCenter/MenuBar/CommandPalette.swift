import AppKit
import Foundation

/// Internal app commands, typed after ">" in the menu bar terminal (or via ⌘⇧P).
@MainActor
enum CommandPalette {
    struct Command {
        let name: String          // canonical prefix, e.g. "new reminder"
        let aliases: [String]
        let usage: String
        let run: @MainActor (String) async -> String
    }

    static let commands: [Command] = [
        Command(name: "new reminder", aliases: ["reminder", "remind"], usage: "new reminder Buy milk tomorrow 3pm") { arg in
            if !EventKitService.shared.remindersAuthorized { await EventKitService.shared.requestReminders() }
            guard let r = RemindersStore.add(arg) else { return "Couldn't create reminder (Reminders access?)" }
            return "Reminder “\(r.title ?? "")”" + (r.dueDate.map { " due \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "")
        },
        Command(name: "new event", aliases: ["event", "schedule"], usage: "new event Lunch with Sam friday 1pm") { arg in
            if !EventKitService.shared.eventsAuthorized { await EventKitService.shared.requestEvents() }
            guard let e = CalendarStore.create(fromText: arg) else { return "Couldn't create event (Calendar access?)" }
            return "Event “\(e.title ?? "")” on \(e.startDate.formatted(date: .abbreviated, time: .shortened))"
        },
        Command(name: "capture", aliases: ["inbox", "note to self"], usage: "capture idea for blog post") { arg in
            InboxCapture.capture(arg); return "Captured to Inbox"
        },
        Command(name: "new note", aliases: ["note"], usage: "new note Meeting notes") { arg in
            let n = NotesStore.create(title: arg); return "Created note “\(n.title)”"
        },
        Command(name: "new card", aliases: ["kanban", "card", "task"], usage: "new card Fix login bug #web") { arg in
            KanbanStore.addCard(title: arg); return "Added Kanban card “\(arg)”"
        },
        Command(name: "start pomodoro", aliases: ["pomodoro", "focus"], usage: "start pomodoro [task]") { arg in
            PomodoroEngine.shared.start(task: arg.isEmpty ? nil : arg)
            return "Pomodoro started\(arg.isEmpty ? "" : " on “\(arg)”") — \(PomodoroEngine.shared.config.focusMinutes) min"
        },
        Command(name: "stop pomodoro", aliases: ["pause pomodoro"], usage: "stop pomodoro") { _ in
            PomodoroEngine.shared.pause(); return "Pomodoro paused"
        },
        Command(name: "ask", aliases: ["ask claude", "ask ai", "ai"], usage: "ask claude \"summarize my day\"") { arg in
            let q = arg.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            do {
                return try await AIService.shared.complete(system: AIDataContext.systemPrompt + "\n\n" + (await AIDataContext.snapshot()),
                                                           [AIMessage(role: .user, content: q)])
            } catch { return "⚠️ " + error.localizedDescription }
        },
        Command(name: "switch workspace", aliases: ["workspace", "ws", "go"], usage: "switch workspace Dev") { arg in
            WorkspaceStore.shared.select(named: arg) ? "Switched to \(arg)" : "No workspace named “\(arg)”"
        },
        Command(name: "add widget", aliases: ["widget"], usage: "add widget weather") { arg in
            guard let d = WidgetRegistry.all.first(where: { $0.title.localizedCaseInsensitiveContains(arg) || $0.kind == arg.lowercased() }) else {
                return "Unknown widget “\(arg)”"
            }
            WorkspaceStore.shared.addWidget(kind: d.kind)
            return "Added \(d.title) to \(WorkspaceStore.shared.current?.name ?? "workspace")"
        },
        Command(name: "log habit", aliases: ["habit", "done"], usage: "log habit Exercise") { arg in
            guard let h = HabitStore.habits().first(where: { $0.name.localizedCaseInsensitiveCompare(arg) == .orderedSame }) else { return "No habit “\(arg)”" }
            HabitStore.mark(h.id); return "Logged \(h.name) for today"
        },
        Command(name: "run snippet", aliases: ["snippet"], usage: "run snippet deploy") { arg in
            guard let s = SnippetStore.search(arg).first else { return "No snippet matching “\(arg)”" }
            TerminalManager.shared.quick.runLine(s.code); SnippetStore.used(s)
            return "Ran “\(s.title)” in the quick terminal"
        },
        Command(name: "zen", aliases: ["zen mode"], usage: "zen") { _ in
            WorkspaceStore.shared.toggleZen(); return WorkspaceStore.shared.zenWidgetID == nil ? "Zen mode off" : "Zen mode on"
        },
        Command(name: "open dashboard", aliases: ["dashboard", "open"], usage: "open dashboard") { _ in
            StatusItemController.shared.openDashboard(); return "Opened dashboard"
        },
        Command(name: "theme", aliases: [], usage: "theme dark | light | auto") { arg in
            guard let t = ThemeMode.allCases.first(where: { $0.rawValue.lowercased() == arg.lowercased() }) else { return "Use: theme dark | light | auto" }
            UserDefaults.standard.set(t.rawValue, forKey: SettingsKey.theme); return "Theme set to \(t.rawValue)"
        },
        Command(name: "check apis", aliases: ["ping apis"], usage: "check apis") { _ in
            await APIHealthMonitor.tick(force: true); return "Checked \(APIHealthStore.endpoints.count) endpoint(s)"
        },
        Command(name: "help", aliases: ["?"], usage: "help") { _ in
            "Commands:\n" + commands.map { "  >" + $0.usage }.joined(separator: "\n")
        },
    ]

    /// All spellings, longest first so "new reminder" wins over "new".
    private static var spellings: [(String, Command)] {
        commands.flatMap { c in ([c.name] + c.aliases).map { ($0, c) } }.sorted { $0.0.count > $1.0.count }
    }

    static func match(_ input: String) -> (Command, String)? {
        let text = input.trimmingCharacters(in: .whitespaces)
        let lower = text.lowercased()
        for (spelling, cmd) in spellings where lower == spelling || lower.hasPrefix(spelling + " ") {
            return (cmd, String(text.dropFirst(spelling.count)).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    static func completions(for input: String) -> [String] {
        let q = input.drop { $0 == ">" }.lowercased().trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return commands.map { ">" + $0.name + " " } }
        return commands.filter { $0.name.hasPrefix(q) || $0.aliases.contains { $0.hasPrefix(q) } }.map { ">" + $0.name + " " }
    }

    static func execute(_ input: String) async -> String {
        if let (cmd, arg) = match(input) { return await cmd.run(arg) }
        // Natural-language fallback: let the AI map free text onto one command.
        guard AIService.shared.isConfigured else { return "Unknown command. Type >help" }
        let list = commands.map(\.usage).joined(separator: "\n")
        let prompt = "Map the user's request to exactly one of these commands and reply with only the command line, no '>' and no explanation. If none fit, reply NONE.\n\nCommands:\n\(list)\n\nRequest: \(input)"
        guard let mapped = try? await AIService.shared.complete([AIMessage(role: .user, content: prompt)], effort: "low"),
              let (cmd, arg) = match(mapped.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: ">"))) else {
            return "Unknown command. Type >help"
        }
        return "→ >\(cmd.name) \(arg)\n" + (await cmd.run(arg))
    }
}
