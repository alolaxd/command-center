import XCTest
@testable import Command_Center

@MainActor
final class DevToolsTests: XCTestCase {
    // MARK: AI service wire format
    func testAnthropicRequestShape() throws {
        let req = try AIService.buildRequest(provider: .anthropic, model: "claude-opus-5-5", key: "sk-test", ollama: URL(string: "http://localhost:11434")!,
                                             system: "sys", messages: [AIMessage(role: .user, content: "hi")], effort: "low")
        XCTAssertEqual(req.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-api-key"), "sk-test")
        XCTAssertEqual(req.value(forHTTPHeaderField: "anthropic-version"), "2026-10-21")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "claude-opus-5-5")
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["system"] as? String, "sys")
        XCTAssertEqual((body["thinking"] as? [String: Any])?["type"] as? String, "adaptive")
        XCTAssertEqual((body["output_config"] as? [String: Any])?["effort"] as? String, "low")
        XCTAssertNil(body["temperature"])
    }

    func testOpenAICompatibleAndOllamaRequests() throws {
        let o = try AIService.buildRequest(provider: .openrouter, model: "openrouter/auto", key: "k", ollama: URL(string: "http://localhost:11434")!,
                                           system: "s", messages: [AIMessage(role: .user, content: "x")], effort: nil)
        XCTAssertEqual(o.url?.host, "openrouter.ai")
        let ob = try XCTUnwrap(JSONSerialization.jsonObject(with: o.httpBody!) as? [String: Any])
        XCTAssertEqual((ob["messages"] as? [[String: Any]])?.first?["role"] as? String, "system")
        let l = try AIService.buildRequest(provider: .ollama, model: "llama3.2", key: nil, ollama: URL(string: "http://localhost:11434")!,
                                           system: nil, messages: [AIMessage(role: .user, content: "x")], effort: nil)
        XCTAssertEqual(l.url?.absoluteString, "http://localhost:11434/api/chat")
    }

    func testStreamParsing() throws {
        XCTAssertEqual(try AIService.parse(line: #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hel"}}"#, provider: .anthropic), "Hel")
        XCTAssertNil(try AIService.parse(line: #"data: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":""}}"#, provider: .anthropic))
        XCTAssertThrowsError(try AIService.parse(line: #"data: {"type":"message_delta","delta":{"stop_reason":"refusal"}}"#, provider: .anthropic))
        XCTAssertEqual(try AIService.parse(line: #"data: {"choices":[{"delta":{"content":"yo"}}]}"#, provider: .openai), "yo")
        XCTAssertEqual(try AIService.parse(line: #"{"message":{"role":"assistant","content":"ol"},"done":false}"#, provider: .ollama), "ol")
    }

    func testAIChatShowsErrorWithoutProviderAndPersists() async throws {
        try XCTSkipIf(AIService.shared.isConfigured, "a provider is configured; skip the offline-path test")
        let vm = AIChatViewModel()
        let id = UUID()
        vm.load(id)
        vm.send(AIChatConfiguration(), text: "How many pomodoros this week?")
        let done = await waitUntilAsync(10) { !vm.isRunning }
        XCTAssertTrue(done)
        XCTAssertEqual(vm.messages.count, 2)
        XCTAssertTrue(vm.messages[1].content.contains("⚠️"))
        XCTAssertEqual(AIChatStore.messages(id.uuidString).count, 2, "conversation persisted")
        vm.clear()
        XCTAssertTrue(AIChatStore.messages(id.uuidString).isEmpty)
    }

    func testDataSnapshotIncludesWidgets() async {
        PomodoroStore.log(PomodoroSession(start: Date().addingTimeInterval(-1500), end: Date(), minutes: 25, task: "Snapshot"))
        BudgetStore.quickAdd("42 groceries")
        let snap = await AIDataContext.snapshot()
        XCTAssertTrue(snap.contains("Pomodoros: today"))
        XCTAssertTrue(snap.contains("Groceries"))
        XCTAssertTrue(snap.contains("AI coding agents"))
    }

    // MARK: Git
    func testGitDashboardAgainstTempRepo() async throws {
        let repo = tempDir().path
        func git(_ a: String...) { _ = Shell.runSync("/usr/bin/git", ["-C", repo] + a) }
        git("init", "-q", "-b", "main"); git("config", "user.email", "test@example.com"); git("config", "user.name", "Test")
        try "a".write(toFile: repo + "/a.txt", atomically: true, encoding: .utf8)
        git("add", "."); git("commit", "-qm", "first commit")
        git("branch", "feature")
        try "b".write(toFile: repo + "/a.txt", atomically: true, encoding: .utf8)          // modified
        try "new".write(toFile: repo + "/new.txt", atomically: true, encoding: .utf8)      // untracked
        try "s".write(toFile: repo + "/staged.txt", atomically: true, encoding: .utf8); git("add", "staged.txt")

        var s = await GitDashboardStore.status(repo)
        XCTAssertNil(s.error)
        XCTAssertEqual(s.branch, "main")
        XCTAssertEqual(s.staged, 1); XCTAssertEqual(s.unstaged, 1); XCTAssertEqual(s.untracked, 1)
        XCTAssertEqual(s.commits.first?.subject, "first commit")
        XCTAssertEqual(Set(s.branches), ["main", "feature"])
        let heat = await GitDashboardStore.commitDays(repo)
        XCTAssertEqual(heat[Date().dayKey], 1, "heatmap counts today's commit")

        let stash = await GitDashboardStore.run(.stash, repo: repo)
        XCTAssertTrue(stash.ok)
        s = await GitDashboardStore.status(repo)
        XCTAssertTrue(s.isClean, "stash includes untracked")
        let sw = await GitDashboardStore.switchBranch("feature", repo: repo)
        XCTAssertTrue(sw.ok)
        let onFeature = await GitDashboardStore.status(repo)
        XCTAssertEqual(onFeature.branch, "feature")
        _ = await GitDashboardStore.switchBranch("main", repo: repo)
        let pop = await GitDashboardStore.run(.stashPop, repo: repo)
        XCTAssertTrue(pop.ok)
        let dirty = await GitDashboardStore.status(repo)
        XCTAssertFalse(dirty.isClean)
        let pull = await GitDashboardStore.run(.pull, repo: repo)
        XCTAssertFalse(pull.ok, "pull without remote reports failure, no crash")
    }

    func testGitHostParsing() {
        guard case .github(let o, let r)? = GitDashboardStore.host(for: "git@github.com:apple/swift.git") else { return XCTFail() }
        XCTAssertEqual(o, "apple"); XCTAssertEqual(r, "swift")
        guard case .github(_, let r2)? = GitDashboardStore.host(for: "https://github.com/groue/GRDB.swift") else { return XCTFail() }
        XCTAssertEqual(r2, "GRDB.swift")
        guard case .gitlab(let p)? = GitDashboardStore.host(for: "https://gitlab.com/group/sub/proj.git") else { return XCTFail() }
        XCTAssertEqual(p, "group/sub/proj")
        XCTAssertNil(GitDashboardStore.host(for: "/local/path"))
    }

    // MARK: Terminal (real PTY)
    func testTerminalRunsShellCommandsWithColorAndSearch() {
        let s = TerminalSession(cwd: NSTemporaryDirectory())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = s.view
        XCTAssertTrue(s.isRunning)
        let marker = "cc-\(Int.random(in: 1000...9999))"
        s.runLine("printf '\\033[31m%s\\033[0m\\n' \(marker); echo $TERM; tty")
        // The marker appears once in the echoed command line and once as printf output.
        XCTAssertTrue(waitUntil(8) { s.view.transcriptText.components(separatedBy: marker).count >= 3 }, "command output arrives through the PTY")
        let out = s.view.transcriptText
        let ansi = s.view.ansiTranscript
        XCTAssertTrue(ansi.contains(marker) && (ansi.contains("[31m") || ansi.contains(";31m") || ansi.contains("38;5;1m")), "ANSI red is parsed into cell attributes")
        XCTAssertTrue(out.contains("xterm-256color"))
        XCTAssertTrue(out.contains("/dev/ttys"), "real pseudo-terminal")
        XCTAssertTrue(s.find(marker), "search within output")
        s.send("\u{03}")
        s.terminate()
        XCTAssertFalse(s.isRunning)
    }

    func testTerminalPanesTabsAndSplits() {
        let vm = TerminalPanesViewModel()
        var config = TerminalPanesConfiguration()
        let update: (TerminalPanesConfiguration) -> Void = { config = $0 }
        vm.newTab(config, update: update)
        XCTAssertEqual(config.tabs.count, 2)
        XCTAssertEqual(vm.selectedTab(config)?.id, config.tabs[1].id)
        vm.split(.horizontal, config, update: update)
        XCTAssertEqual(vm.selectedTab(config)?.panes.count, 2)
        XCTAssertEqual(vm.selectedTab(config)?.split, .horizontal)
        let pane = vm.selectedTab(config)!.panes[1]
        XCTAssertTrue(TerminalPanesStore.session(for: pane) === TerminalPanesStore.session(for: pane), "sessions persist per pane")
        vm.split(.none, config, update: update)
        XCTAssertEqual(vm.selectedTab(config)?.panes.count, 1)
        vm.closeTab(vm.selectedTab(config)!, config, update: update)
        XCTAssertEqual(config.tabs.count, 1)
        config.tabs.flatMap(\.panes).forEach(TerminalPanesStore.close)
    }

    // MARK: Snippets
    func testSnippetsDetectSearchHighlight() throws {
        XCTAssertEqual(LanguageDetector.detect("import SwiftUI\nstruct A: View {}\nlet x = 1"), "swift")
        XCTAssertEqual(LanguageDetector.detect("def f(x):\n    return x"), "python")
        XCTAssertEqual(LanguageDetector.detect("#!/bin/zsh\necho hi"), "shell")
        XCTAssertEqual(LanguageDetector.detect("{\"a\": 1}"), "json")
        XCTAssertEqual(LanguageDetector.detect("SELECT id FROM users WHERE x = 1"), "sql")
        XCTAssertEqual(LanguageDetector.detect("const f = (a) => a * 2"), "javascript")
        let s = SnippetStore.importText("git log --oneline | head -5 # recent", title: "Recent commits")
        XCTAssertEqual(s.language, "shell")
        var t = s; t.tags = "git, cli"; SnippetStore.save(t)
        XCTAssertTrue(SnippetStore.search("oneline").contains { $0.id == s.id }, "FTS on code")
        XCTAssertTrue(SnippetStore.search("cli").contains { $0.id == s.id }, "FTS on tags")
        SnippetStore.used(s)
        XCTAssertEqual(SnippetStore.all().first { $0.id == s.id }?.useCount, 1)
        let attr = SyntaxHighlighter.highlight("let x = \"hi\" // c", language: "swift")
        XCTAssertEqual(attr.runs.count > 2, true, "keywords, strings and comments are coloured")
        SnippetStore.delete(s)
        XCTAssertFalse(SnippetStore.search("oneline").contains { $0.id == s.id })
    }

    // MARK: API Health
    func testAPIHealthChecksAgainstLocalServer() async throws {
        let server = try LocalHTTPServer()
        let ok = APIEndpoint(name: "ok", url: server.url("/ok"))
        let bad = APIEndpoint(name: "bad", url: server.url("/fail"))
        let down = APIEndpoint(name: "down", url: "http://127.0.0.1:9/", timeout: 2)
        let c1 = await APIHealthMonitor.check(ok)
        XCTAssertTrue(c1.ok); XCTAssertEqual(c1.status, 200); XCTAssertGreaterThan(c1.latencyMs, 0)
        let c2 = await APIHealthMonitor.check(bad)
        XCTAssertFalse(c2.ok); XCTAssertEqual(c2.status, 500)
        let c3 = await APIHealthMonitor.check(down)
        XCTAssertFalse(c3.ok); XCTAssertEqual(c3.status, 0); XCTAssertNotNil(c3.error)
        var config = APIHealthConfiguration(); config.endpoints = [ok, bad]
        let vm = APIHealthViewModel()
        vm.sync(config)
        XCTAssertTrue(APIHealthStore.endpoints.contains { $0.id == ok.id }, "endpoints mirrored for the background monitor")
        await vm.checkNow(config)
        XCTAssertEqual(vm.history[ok.id]?.last?.ok, true)
        XCTAssertEqual(vm.history[bad.id]?.last?.ok, false)
        XCTAssertEqual(APIHealthStore.uptime(ok.id), 1)
        await APIHealthMonitor.tick(force: true)
        XCTAssertGreaterThanOrEqual(APIHealthStore.history(ok.id).count, 2)
        APIHealthStore.endpoints = []
    }
}
