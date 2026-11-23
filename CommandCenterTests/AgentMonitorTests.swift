import XCTest
@testable import Command_Center

@MainActor
final class AgentMonitorTests: XCTestCase {
    func testDetectsRunningClaudeCodeProcess() async throws {
        let running = Shell.runSync("/bin/ps", ["-axo", "comm"]).stdout.split(separator: "\n").contains { $0.trimmingCharacters(in: .whitespaces) == "claude" }
        try XCTSkipUnless(running, "Claude Code is not running on this machine")
        let procs = await AgentScanner.shared.agentProcesses()
        XCTAssertTrue(procs.contains { $0.provider == .claudeCode }, "claude process not detected: \(procs)")
        XCTAssertTrue(procs.allSatisfy { !$0.cwd.isEmpty }, "cwd should resolve for own processes")
    }

    func testScansClaudeLogsIntoSessionsWithCost() async throws {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: root.path), "no Claude Code logs")
        await AgentActivity.refresh()
        let sessions = AgentMonitorStore.sessions()
        XCTAssertFalse(sessions.isEmpty)
        let claude = sessions.filter { $0.provider == .claudeCode }
        XCTAssertFalse(claude.isEmpty)
        XCTAssertTrue(claude.contains { $0.totalTokens > 0 && $0.cost > 0 && !$0.model.isEmpty })
        XCTAssertTrue(claude.allSatisfy { !$0.title.isEmpty })
        XCTAssertGreaterThan(AgentMonitorStore.costs(since: nil).map(\.cost).reduce(0, +), 0)
    }

    func testActiveClaudeSessionShowsAsActive() async throws {
        let running = Shell.runSync("/bin/ps", ["-axo", "comm"]).stdout.split(separator: "\n").contains { $0.trimmingCharacters(in: .whitespaces) == "claude" }
        try XCTSkipUnless(running, "Claude Code is not running")
        await AgentActivity.refresh()
        let vm = AgentMonitorViewModel()
        vm.load(AgentMonitorConfiguration())
        XCTAssertTrue(vm.sessions.contains { $0.provider == .claudeCode }, "running Claude Code should appear under Active")
        XCTAssertGreaterThan(AgentActivity.runningCount(), 0, "menu bar ring should reflect the running agent")
    }

    func testIncrementalScanDoesNotDoubleCount() async throws {
        await AgentActivity.refresh()
        let before = AgentMonitorStore.costs(since: nil).map(\.cost).reduce(0, +)
        await AgentScanner.shared.scanAll(aiderRepos: [])
        let after = AgentMonitorStore.costs(since: nil).map(\.cost).reduce(0, +)
        // Only new log lines written between the two scans may add cost.
        XCTAssertLessThan(after - before, 5.0)
    }

    func testPricingTable() {
        XCTAssertEqual(AgentPricing.cost(model: "claude-opus-5-5", input: 1_000_000, output: 0, cacheRead: 0, cacheWrite5m: 0, cacheWrite1h: 0), 4, accuracy: 0.001)
        XCTAssertEqual(AgentPricing.cost(model: "claude-sonnet-5-5", input: 0, output: 1_000_000, cacheRead: 0, cacheWrite5m: 0, cacheWrite1h: 0), 10, accuracy: 0.001)
        XCTAssertEqual(AgentPricing.cost(model: "unknown-model", input: 1000, output: 1000, cacheRead: 0, cacheWrite5m: 0, cacheWrite1h: 0), 0)
    }
}

final class AgentIdentifyTests: XCTestCase {
    func testIdentifiesNativeClaudeBinaryByPath() {
        XCTAssertEqual(AgentScanner.identify(name: "2.1.330", path: "/Users/x/.local/share/claude/versions/2.1.330", args: { [] }), .claudeCode)
    }
    func testIdentifiesNpmClaude() {
        XCTAssertEqual(AgentScanner.identify(name: "node", path: "/opt/homebrew/bin/node",
                                             args: { ["node", "/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/cli.js"] }), .claudeCode)
    }
    func testIdentifiesOthers() {
        XCTAssertEqual(AgentScanner.identify(name: "opencode", path: "/opt/homebrew/bin/opencode", args: { [] }), .openCode)
        XCTAssertEqual(AgentScanner.identify(name: "node", path: "/usr/local/bin/node", args: { ["node", "/usr/local/bin/codex"] }), .codex)
        XCTAssertEqual(AgentScanner.identify(name: "python3.12", path: "/usr/bin/python3", args: { ["python3", "/Users/x/.local/bin/aider"] }), .aider)
        XCTAssertNil(AgentScanner.identify(name: "node", path: "/usr/local/bin/node", args: { ["node", "server.js"] }))
        XCTAssertNil(AgentScanner.identify(name: "Safari", path: "/Applications/Safari.app/Contents/MacOS/Safari", args: { [] }))
    }
}
