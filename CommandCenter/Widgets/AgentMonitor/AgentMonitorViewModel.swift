import Foundation

@MainActor @Observable
final class AgentMonitorViewModel {
    var sessions: [AgentSession] = []
    var history: [AgentSession] = []
    var processes: [AgentScanner.AgentProcess] = []
    var costToday: [AgentMonitorStore.CostRow] = []
    var costWeek: [AgentMonitorStore.CostRow] = []
    var costMonth: [AgentMonitorStore.CostRow] = []
    var costAll: [AgentMonitorStore.CostRow] = []
    var query = ""
    var scanning = false

    struct CustomStatus: Identifiable { let id: UUID; let name: String; let alive: Bool; let task: String; let pid: Int32? }
    var custom: [CustomStatus] = []

    func load(_ config: AgentMonitorConfiguration) {
        UserDefaults.standard.set(config.aiderRepos, forKey: "agents.aiderRepos")
        processes = AgentActivity.processes
        let recent = AgentMonitorStore.sessions(limit: 40)
        // Active = running/waiting sessions; only the newest session per (provider, cwd) can be "waiting".
        var seen = Set<String>()
        sessions = recent.filter { s in
            let key = "\(s.provider.rawValue)|\(s.cwd)"
            defer { seen.insert(key) }
            let st = AgentStatus.of(s, processes: processes)
            return st == .running || (st == .waiting && !seen.contains(key))
        }
        // Agent processes with no matching session yet (e.g. a fresh Claude Code launch) still show up.
        for p in processes where p.provider != .custom && !sessions.contains(where: { $0.provider == p.provider && (p.cwd.isEmpty || $0.cwd == p.cwd) }) {
            if let latest = recent.first(where: { $0.provider == p.provider && $0.cwd == p.cwd }) { sessions.append(latest); continue }
            sessions.append(AgentSession(id: "proc:\(p.pid)", provider: p.provider, title: "\(p.provider.rawValue) (pid \(p.pid))",
                                         cwd: p.cwd, model: "", startedAt: Date(), lastActivity: Date().addingTimeInterval(-120),
                                         lastEvent: "Process running in \((p.cwd as NSString).abbreviatingWithTildeInPath)"))
        }
        history = AgentMonitorStore.sessions(limit: 200, query: query)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        costToday = AgentMonitorStore.costs(since: today)
        costWeek = AgentMonitorStore.costs(since: cal.dateInterval(of: .weekOfYear, for: Date())?.start)
        costMonth = AgentMonitorStore.costs(since: cal.dateInterval(of: .month, for: Date())?.start)
        costAll = AgentMonitorStore.costs(since: nil)
        custom = config.customAgents.map { a in
            var alive = false
            if let pid = a.pid { alive = kill(pid, 0) == 0 }
            var task = ""
            if !a.logPath.isEmpty {
                let path = (a.logPath as NSString).expandingTildeInPath
                if let mod = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date {
                    alive = alive || mod > Date().addingTimeInterval(-60)
                }
                if let text = try? String(contentsOfFile: path, encoding: .utf8) {
                    task = text.split(separator: "\n").last.map(String.init) ?? ""
                }
            }
            return CustomStatus(id: a.id, name: a.name, alive: alive, task: String(task.prefix(120)), pid: a.pid)
        }
    }

    func rescan(_ config: AgentMonitorConfiguration) async {
        scanning = true
        await AgentActivity.refresh()
        load(config)
        scanning = false
    }

    func process(for s: AgentSession) -> AgentScanner.AgentProcess? {
        if s.id.hasPrefix("proc:"), let pid = Int32(s.id.dropFirst(5)) { return processes.first { $0.pid == pid } }
        return processes.first { $0.provider == s.provider && $0.cwd == s.cwd }
    }

    func total(_ rows: [AgentMonitorStore.CostRow]) -> Double { rows.map(\.cost).reduce(0, +) }
}
