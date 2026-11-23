import Foundation

@MainActor @Observable
final class GitDashboardViewModel {
    var repos: [GitRepoStatus] = []
    var prs: [String: [PullRequest]] = [:]
    var heatmap: [String: Int] = [:]
    var busy: Set<String> = []
    var lastOutput: String?

    func load(_ config: GitDashboardConfiguration) async {
        UserDefaults.standard.set(config.repos, forKey: "git.repos")
        var result: [GitRepoStatus] = []
        await withTaskGroup(of: GitRepoStatus.self) { group in
            for r in config.repos { group.addTask { await GitDashboardStore.status(r, commits: config.commitCount) } }
            for await s in group { result.append(s) }
        }
        repos = config.repos.compactMap { path in result.first { $0.path == path } }
        if config.showPRs {
            for r in repos { if let remote = r.remoteURL { prs[r.path] = await GitDashboardStore.pullRequests(remote: remote) } }
        }
    }

    func loadHeatmap(_ config: GitDashboardConfiguration) async {
        var merged: [String: Int] = [:]
        for r in config.repos { for (k, v) in await GitDashboardStore.commitDays(r) { merged[k, default: 0] += v } }
        heatmap = merged
    }

    func run(_ action: GitDashboardStore.Action, _ repo: GitRepoStatus, config: GitDashboardConfiguration) async {
        busy.insert(repo.path)
        let r = await GitDashboardStore.run(action, repo: repo.path)
        report(r, "\(action.rawValue) \(repo.name)")
        busy.remove(repo.path)
        await load(config)
    }

    func switchBranch(_ branch: String, _ repo: GitRepoStatus, config: GitDashboardConfiguration) async {
        busy.insert(repo.path)
        report(await GitDashboardStore.switchBranch(branch, repo: repo.path), "Switch \(repo.name) → \(branch)")
        busy.remove(repo.path)
        await load(config)
    }

    private func report(_ r: Shell.Result, _ label: String) {
        let text = (r.stdout + r.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        lastOutput = "\(label): \(r.ok ? "done" : "failed")\(text.isEmpty ? "" : "\n" + text.prefix(400))"
        WidgetBus.shared.toast("\(label) \(r.ok ? "succeeded" : "failed")", symbol: r.ok ? "checkmark.circle" : "exclamationmark.triangle")
    }
}
