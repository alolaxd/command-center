import Darwin
import Foundation
import GRDB

/// Incrementally parses local agent logs into the agent_session / agent_usage tables.
/// Claude Code: ~/.claude/projects/**/*.jsonl · OpenCode: ~/.local/share/opencode/opencode.db
/// Codex: ~/.codex/sessions/**/*.jsonl · Aider: <repo>/.aider.chat.history.md
actor AgentScanner {
    static let shared = AgentScanner()

    struct AgentProcess: Identifiable, Hashable, Sendable {
        var id: pid_t { pid }
        let pid: pid_t
        let name: String
        let cwd: String
        let provider: AgentProvider
    }

    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var db: DatabasePool { AppDatabase.shared.pool }
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    func scanAll(aiderRepos: [String]) {
        scanClaude()
        scanCodex()
        scanOpenCode()
        for repo in aiderRepos { scanAider(repo: (repo as NSString).expandingTildeInPath) }
    }

    // MARK: Session accumulation

    private struct Delta {
        var provider: AgentProvider
        var title: String?
        var cwd: String?
        var model: String?
        var first: Date?
        var last: Date?
        var input = 0, output = 0, cache = 0
        var cost = 0.0
        var lastEvent: String?
        var byDay: [String: (cost: Double, tokens: Int)] = [:]
    }

    private func commit(_ deltas: [String: Delta]) {
        guard !deltas.isEmpty else { return }
        try? db.write { db in
            for (id, d) in deltas {
                var s = try AgentSession.fetchOne(db, key: id) ?? AgentSession(
                    id: id, provider: d.provider, title: "", cwd: "", model: "", startedAt: d.first ?? Date(), lastActivity: d.last ?? Date())
                if let t = d.title, !t.isEmpty, s.title.isEmpty || d.provider != .claudeCode || t != s.title { s.title = t }
                if let c = d.cwd, !c.isEmpty { s.cwd = c }
                if let m = d.model, !m.isEmpty, m != "<synthetic>" { s.model = m }
                if let f = d.first, f < s.startedAt { s.startedAt = f }
                if let l = d.last, l > s.lastActivity { s.lastActivity = l }
                if let e = d.lastEvent { s.lastEvent = e }
                s.inputTokens += d.input; s.outputTokens += d.output; s.cacheTokens += d.cache; s.cost += d.cost
                if s.title.isEmpty { s.title = (s.cwd as NSString).lastPathComponent }
                try s.save(db)
                for (day, u) in d.byDay {
                    try db.execute(sql: """
                        INSERT INTO agent_usage (sessionId, provider, day, cost, tokens) VALUES (?, ?, ?, ?, ?)
                        ON CONFLICT(sessionId, day) DO UPDATE SET cost = cost + excluded.cost, tokens = tokens + excluded.tokens
                        """, arguments: [id, d.provider.rawValue, day, u.cost, u.tokens])
                }
            }
        }
    }

    // MARK: Incremental file reading

    private func scanState(_ path: String) -> (offset: Int, state: [String: String]) {
        let row = try? db.read { try Row.fetchOne($0, sql: "SELECT offset, state FROM agent_scan WHERE path = ?", arguments: [path]) }
        let offset: Int = row?["offset"] ?? 0
        let stateJSON: String? = row?["state"]
        let state = stateJSON.flatMap { try? JSONDecoder().decode([String: String].self, from: Data($0.utf8)) } ?? [:]
        return (offset, state)
    }

    private func saveState(_ path: String, offset: Int, state: [String: String]) {
        let json = (try? String(data: JSONEncoder().encode(state), encoding: .utf8)) ?? "{}"
        try? db.write {
            try $0.execute(sql: "INSERT INTO agent_scan (path, offset, state) VALUES (?, ?, ?) ON CONFLICT(path) DO UPDATE SET offset = excluded.offset, state = excluded.state",
                           arguments: [path, offset, json])
        }
    }

    /// Returns complete new lines since the stored offset (and the new offset).
    private func newLines(_ url: URL, from offset: Int) -> ([Substring], Int)? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attrs[.size] as? NSNumber)?.intValue else { return nil }
        var start = offset
        if size < offset { start = 0 }   // file truncated/rotated
        guard size > start, let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        try? fh.seek(toOffset: UInt64(start))
        guard let data = try? fh.readToEnd(), let lastNL = data.lastIndex(of: UInt8(ascii: "\n")) else { return nil }
        let chunk = data[data.startIndex...lastNL]
        let text = String(decoding: chunk, as: UTF8.self)
        return (text.split(separator: "\n", omittingEmptySubsequences: true), start + chunk.count)
    }

    private func files(under dir: URL, ext: String, prefix: String? = nil) -> [URL] {
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        return e.compactMap { $0 as? URL }.filter { url in url.pathExtension == ext && (prefix.map { url.lastPathComponent.hasPrefix($0) } ?? true) }
    }

    private func date(_ s: Any?) -> Date? {
        guard let s = s as? String else { return nil }
        return Self.iso.date(from: s) ?? Self.isoPlain.date(from: s)
    }

    // MARK: Claude Code

    private func scanClaude() {
        let root = home.appendingPathComponent(".claude/projects")
        for url in files(under: root, ext: "jsonl") {
            let (offset, oldState) = scanState(url.path)
            guard let (lines, newOffset) = newLines(url, from: offset) else { continue }
            var state = oldState
            var deltas: [String: Delta] = [:]
            for line in lines {
                guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let sid = obj["sessionId"] as? String else { continue }
                let key = "claude:" + sid
                var d = deltas[key] ?? Delta(provider: .claudeCode)
                let ts = date(obj["timestamp"])
                if let ts { d.first = min(d.first ?? ts, ts); d.last = max(d.last ?? ts, ts) }
                if let cwd = obj["cwd"] as? String { d.cwd = cwd }
                switch obj["type"] as? String {
                case "ai-title":
                    if let t = obj["aiTitle"] as? String { d.title = t; state["title:" + sid] = t }
                case "user":
                    let msg = obj["message"] as? [String: Any]
                    if let text = msg?["content"] as? String, !text.hasPrefix("<"), obj["isSidechain"] as? Bool != true {
                        if state["title:" + sid] == nil { d.title = String(text.prefix(120)); state["title:" + sid] = d.title }
                        d.lastEvent = "You: " + text.prefix(100)
                    }
                case "assistant":
                    guard let msg = obj["message"] as? [String: Any] else { break }
                    let mid = msg["id"] as? String ?? ""
                    if let content = msg["content"] as? [[String: Any]] {
                        if let tool = content.first(where: { $0["type"] as? String == "tool_use" }) {
                            d.lastEvent = "Tool: \(tool["name"] as? String ?? "")"
                        } else if let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String {
                            d.lastEvent = String(text.prefix(100))
                        }
                    }
                    guard !mid.isEmpty, state["last:" + sid] != mid, let usage = msg["usage"] as? [String: Any] else { break }
                    state["last:" + sid] = mid
                    let model = msg["model"] as? String ?? ""
                    d.model = model
                    let input = usage["input_tokens"] as? Int ?? 0
                    let output = usage["output_tokens"] as? Int ?? 0
                    let read = usage["cache_read_input_tokens"] as? Int ?? 0
                    let creation = usage["cache_creation"] as? [String: Any]
                    let w1h = creation?["ephemeral_1h_input_tokens"] as? Int ?? 0
                    let w5m = creation?["ephemeral_5m_input_tokens"] as? Int ?? max(0, (usage["cache_creation_input_tokens"] as? Int ?? 0) - w1h)
                    let cost = AgentPricing.cost(model: model, input: input, output: output, cacheRead: read, cacheWrite5m: w5m, cacheWrite1h: w1h)
                    d.input += input; d.output += output; d.cache += read + w5m + w1h; d.cost += cost
                    let day = (ts ?? Date()).dayKey
                    let prev = d.byDay[day] ?? (0, 0)
                    d.byDay[day] = (prev.cost + cost, prev.tokens + input + output + read + w5m + w1h)
                default: break
                }
                deltas[key] = d
            }
            commit(deltas)
            saveState(url.path, offset: newOffset, state: state.filter { $0.key.hasPrefix("last:") || $0.key.hasPrefix("title:") })
        }
    }

    // MARK: Codex

    private func scanCodex() {
        let root = home.appendingPathComponent(".codex/sessions")
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        for url in files(under: root, ext: "jsonl", prefix: "rollout-") {
            let (offset, oldState) = scanState(url.path)
            guard let (lines, newOffset) = newLines(url, from: offset) else { continue }
            var state = oldState
            let key = "codex:" + (state["id"] ?? url.deletingPathExtension().lastPathComponent)
            var d = Delta(provider: .codex)
            d.model = state["model"]
            for line in lines {
                guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
                let ts = date(obj["timestamp"])
                if let ts { d.first = min(d.first ?? ts, ts); d.last = max(d.last ?? ts, ts) }
                let payload = obj["payload"] as? [String: Any] ?? [:]
                switch obj["type"] as? String {
                case "session_meta":
                    if let cwd = payload["cwd"] as? String { d.cwd = cwd }
                case "turn_context":
                    if let m = payload["model"] as? String { d.model = m; state["model"] = m }
                    if let cwd = payload["cwd"] as? String { d.cwd = cwd }
                case "response_item":
                    if payload["type"] as? String == "message", payload["role"] as? String == "user",
                       let content = payload["content"] as? [[String: Any]], let text = content.first?["text"] as? String,
                       !text.hasPrefix("<") {
                        if state["titled"] == nil { d.title = String(text.prefix(120)); state["titled"] = "1" }
                        d.lastEvent = "You: " + text.prefix(100)
                    } else if payload["type"] as? String == "function_call" {
                        d.lastEvent = "Tool: \(payload["name"] as? String ?? "")"
                    }
                case "event_msg":
                    if payload["type"] as? String == "token_count",
                       let info = payload["info"] as? [String: Any], let last = info["last_token_usage"] as? [String: Any] {
                        let cached = last["cached_input_tokens"] as? Int ?? 0
                        let input = max(0, (last["input_tokens"] as? Int ?? 0) - cached)
                        let output = last["output_tokens"] as? Int ?? 0
                        let p = AgentPricing.price(for: d.model ?? "")
                        let cost = p.map { (Double(input) * $0.input + Double(cached) * ($0.cacheRead ?? $0.input * 0.1) + Double(output) * $0.output) / 1e6 } ?? 0
                        d.input += input; d.output += output; d.cache += cached; d.cost += cost
                        let day = (ts ?? Date()).dayKey
                        let prev = d.byDay[day] ?? (0, 0)
                        d.byDay[day] = (prev.cost + cost, prev.tokens + input + output + cached)
                    }
                default: break
                }
            }
            commit([key: d])
            saveState(url.path, offset: newOffset, state: state)
        }
    }

    // MARK: OpenCode (SQLite)

    private func scanOpenCode() {
        let path = home.appendingPathComponent(".local/share/opencode/opencode.db").path
        guard FileManager.default.fileExists(atPath: path) else { return }
        var config = Configuration()
        config.readonly = true
        guard let q = try? DatabaseQueue(path: path, configuration: config),
              let rows = try? q.read({ try Row.fetchAll($0, sql: """
                SELECT id, title, directory, cost, tokens_input, tokens_output, tokens_reasoning, tokens_cache_read, tokens_cache_write,
                       model, time_created, time_updated FROM session WHERE parent_id IS NULL ORDER BY time_updated DESC LIMIT 500
                """) }) else { return }
        try? db.write { db in
            for row in rows {
                let id = "opencode:" + (row["id"] as String)
                let modelJSON: String = row["model"] ?? ""
                let model = (try? JSONSerialization.jsonObject(with: Data(modelJSON.utf8)) as? [String: Any])?["id"] as? String ?? modelJSON
                let created = Date(timeIntervalSince1970: Double(row["time_created"] as Int64) / 1000)
                let updated = Date(timeIntervalSince1970: Double(row["time_updated"] as Int64) / 1000)
                let input: Int = row["tokens_input"] ?? 0
                let output: Int = (row["tokens_output"] ?? 0) + (row["tokens_reasoning"] ?? 0)
                let cache: Int = (row["tokens_cache_read"] ?? 0) + (row["tokens_cache_write"] ?? 0)
                let cost: Double = row["cost"] ?? 0
                let s = AgentSession(id: id, provider: .openCode, title: row["title"] ?? "", cwd: row["directory"] ?? "", model: model,
                                     startedAt: created, lastActivity: updated, inputTokens: input, outputTokens: output,
                                     cacheTokens: cache, cost: cost, lastEvent: "")
                try s.save(db)
                // OpenCode only exposes per-session totals; attribute them to the last active day.
                try db.execute(sql: "DELETE FROM agent_usage WHERE sessionId = ?", arguments: [id])
                try AgentUsage(sessionId: id, provider: .openCode, day: updated.dayKey, cost: cost, tokens: input + output + cache).insert(db)
            }
        }
    }

    // MARK: Aider

    private func scanAider(repo: String) {
        let url = URL(fileURLWithPath: repo).appendingPathComponent(".aider.chat.history.md")
        let (offset, oldState) = scanState(url.path)
        guard let (lines, newOffset) = newLines(url, from: offset) else { return }
        var state = oldState
        var deltas: [String: Delta] = [:]
        var current = state["session"]
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("# aider chat started at ") {
                let stamp = String(line.dropFirst("# aider chat started at ".count))
                current = "aider:\(repo):\(stamp)"
                var d = Delta(provider: .aider)
                d.cwd = repo
                d.first = fmt.date(from: stamp); d.last = d.first
                deltas[current!] = d
                state["session"] = current
                continue
            }
            guard let key = current else { continue }
            var d = deltas[key] ?? Delta(provider: .aider)
            if line.hasPrefix("#### ") {
                let text = String(line.dropFirst(5))
                if d.title == nil && state["titled:" + key] == nil { d.title = String(text.prefix(120)); state["titled:" + key] = "1" }
                d.lastEvent = "You: " + text.prefix(100)
                d.last = Date()
            } else if line.hasPrefix("> Main model:") || line.hasPrefix("> Model:") {
                d.model = line.components(separatedBy: ":").dropFirst().joined(separator: ":").components(separatedBy: " with ").first?
                    .trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("> Tokens:") {
                // > Tokens: 2.3k sent, 512 received. Cost: $0.01 message, $0.05 session.
                func num(_ s: String) -> Int {
                    let t = s.trimmingCharacters(in: .whitespaces).lowercased()
                    if t.hasSuffix("k") { return Int((Double(t.dropLast()) ?? 0) * 1000) }
                    if t.hasSuffix("m") { return Int((Double(t.dropLast()) ?? 0) * 1_000_000) }
                    return Int(Double(t) ?? 0)
                }
                let parts = line.dropFirst("> Tokens:".count).components(separatedBy: ",")
                let sent = parts.first.map { num($0.replacingOccurrences(of: "sent", with: "")) } ?? 0
                let recv = parts.count > 1 ? num(parts[1].components(separatedBy: "received").first ?? "") : 0
                var cost = 0.0
                if let r = line.range(of: #"\$([0-9.]+) message"#, options: .regularExpression) {
                    cost = Double(line[r].dropFirst().components(separatedBy: " ").first ?? "") ?? 0
                }
                d.input += sent; d.output += recv; d.cost += cost
                let day = (d.last ?? Date()).dayKey
                let prev = d.byDay[day] ?? (0, 0)
                d.byDay[day] = (prev.cost + cost, prev.tokens + sent + recv)
            }
            deltas[key] = d
        }
        commit(deltas)
        saveState(url.path, offset: newOffset, state: state)
    }

    // MARK: Processes

    func agentProcesses() -> [AgentProcess] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        let me = getuid()
        var out: [AgentProcess] = []
        for pid in pids.prefix(Int(max(0, n))) where pid > 0 {
            var info = proc_bsdshortinfo()
            guard proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdshortinfo>.size)) > 0,
                  info.pbsi_uid == me else { continue }
            let name = SystemSampler.processName(pid)
            let path = SystemSampler.processPath(pid) ?? ""
            guard let provider = Self.identify(name: name, path: path, args: { Self.arguments(of: pid) }) else { continue }
            out.append(AgentProcess(pid: pid, name: name, cwd: Self.cwd(of: pid) ?? "", provider: provider))
        }
        return out
    }

    /// Identifies an agent from its process name, executable path and (lazily) argv.
    /// Claude Code's native binary is ~/.local/share/claude/versions/<version>, so its
    /// kernel process name is the version number — the path is what identifies it.
    static func identify(name: String, path: String, args: () -> [String]) -> AgentProvider? {
        let lname = name.lowercased(), lpath = path.lowercased()
        let base = (lpath as NSString).lastPathComponent
        if lname == "claude" || base == "claude" || lpath.contains("/claude/versions/") || lpath.contains("/claude-code/") { return .claudeCode }
        if lname == "opencode" || base == "opencode" || lpath.contains("/opencode/") { return .openCode }
        if lname == "codex" || base == "codex" || lpath.contains("/@openai/codex/") { return .codex }
        if lname == "aider" || base == "aider" { return .aider }
        if lpath.contains("/cursor.app/contents/macos/") { return .cursor }
        if lpath.contains("/windsurf.app/contents/macos/") { return .windsurf }
        // Script-hosted CLIs (npm / pip installs): inspect argv.
        guard ["node", "bun", "deno"].contains(lname) || lname.hasPrefix("python") else { return nil }
        let joined = args().prefix(4).joined(separator: " ").lowercased()
        if joined.contains("@anthropic-ai/claude-code") || joined.hasSuffix("/claude") || joined.contains("/bin/claude ") { return .claudeCode }
        if joined.contains("@openai/codex") || joined.contains("/bin/codex") { return .codex }
        if joined.contains("opencode") { return .openCode }
        if joined.contains("/bin/aider") || joined.contains(" -m aider") { return .aider }
        return nil
    }

    /// argv via sysctl(KERN_PROCARGS2).
    static func arguments(of pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        let argc = buf.withUnsafeBytes { $0.load(as: Int32.self) }
        var i = MemoryLayout<Int32>.size
        while i < size && buf[i] != 0 { i += 1 }        // exec path
        while i < size && buf[i] == 0 { i += 1 }        // padding
        var args: [String] = []
        while i < size && args.count < Int(argc) {
            let start = i
            while i < size && buf[i] != 0 { i += 1 }
            args.append(String(decoding: buf[start..<i], as: UTF8.self))
            i += 1
        }
        return args
    }

    static func cwd(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return withUnsafeBytes(of: info.pvi_cdir.vip_path) { raw in
            String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
        }
    }
}

/// Feeds the menu bar activity ring and keeps agent tables fresh in the background.
@MainActor
enum AgentActivity {
    private(set) static var running = 0
    private(set) static var processes: [AgentScanner.AgentProcess] = []
    private(set) static var lastScan: Date?
    private static var inFlight = false
    static func runningCount() -> Int { running }

    static func start() {
        _ = TickScheduler.shared.subscribe(every: 15) { Task { await refresh() } }
    }

    static func refresh() async {
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false; lastScan = Date() }
        let repos = AgentMonitorConfiguration.sharedAiderRepos
        await AgentScanner.shared.scanAll(aiderRepos: repos)
        processes = await AgentScanner.shared.agentProcesses()
        let recent = AgentMonitorStore.sessions(limit: 30)
        running = max(recent.filter { AgentStatus.of($0, processes: processes) == .running }.count,
                      processes.filter { $0.provider != .cursor && $0.provider != .windsurf }.isEmpty ? 0 : 1)
        WidgetBus.shared.publish(.dataChanged("agents"))
    }
}

enum AgentStatus: String {
    case running = "Running", waiting = "Waiting", idle = "Idle"

    @MainActor static func of(_ s: AgentSession, processes: [AgentScanner.AgentProcess]) -> AgentStatus {
        let alive = processes.contains { $0.provider == s.provider && ($0.cwd.isEmpty || $0.cwd == s.cwd) }
        if s.lastActivity > Date().addingTimeInterval(-60) && (alive || s.provider == .openCode) { return .running }
        if s.lastActivity > Date().addingTimeInterval(-45) { return .running }
        return alive ? .waiting : .idle
    }
}
