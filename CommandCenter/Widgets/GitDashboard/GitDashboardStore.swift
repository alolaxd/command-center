import Foundation

struct GitRepoStatus: Identifiable, Hashable, Sendable {
    var id: String { path }
    var path: String
    var name: String { (path as NSString).lastPathComponent }
    var branch = "?"
    var upstream: String?
    var ahead = 0
    var behind = 0
    var staged = 0
    var unstaged = 0
    var untracked = 0
    var conflicts = 0
    var commits: [GitCommit] = []
    var branches: [String] = []
    var remoteURL: String?
    var error: String?
    var isClean: Bool { staged + unstaged + untracked + conflicts == 0 }
}

struct GitCommit: Identifiable, Hashable, Sendable {
    var id: String { hash }
    let hash: String
    let subject: String
    let author: String
    let date: Date
}

struct PullRequest: Identifiable, Hashable, Sendable {
    let id: Int
    let number: Int
    let title: String
    let author: String
    let branch: String
    let draft: Bool
    let url: URL
    let updated: Date?
}

/// Local repository inspection via the git CLI plus GitHub/GitLab PR status via their REST APIs.
enum GitDashboardStore {
    static func git(_ repo: String, _ args: [String]) async -> Shell.Result {
        await Shell.run("/usr/bin/git", ["-C", repo] + args, timeout: 60)
    }

    static func status(_ repo: String, commits: Int = 6) async -> GitRepoStatus {
        var s = GitRepoStatus(path: repo)
        let st = await git(repo, ["status", "--porcelain=v2", "--branch"])
        guard st.ok else { s.error = st.stderr.trimmingCharacters(in: .whitespacesAndNewlines); return s }
        for line in st.stdout.split(separator: "\n") {
            if line.hasPrefix("# branch.head ") { s.branch = String(line.dropFirst(14)) }
            else if line.hasPrefix("# branch.upstream ") { s.upstream = String(line.dropFirst(18)) }
            else if line.hasPrefix("# branch.ab ") {
                let parts = line.dropFirst(12).split(separator: " ")
                s.ahead = Int(parts.first?.dropFirst() ?? "") ?? 0
                s.behind = Int(parts.last?.dropFirst() ?? "") ?? 0
            } else if line.hasPrefix("1 ") || line.hasPrefix("2 ") {
                let xy = line.split(separator: " ")[1]
                if xy.first != "." { s.staged += 1 }
                if xy.last != "." { s.unstaged += 1 }
            } else if line.hasPrefix("u ") { s.conflicts += 1 }
            else if line.hasPrefix("? ") { s.untracked += 1 }
        }
        let log = await git(repo, ["log", "-n", "\(commits)", "--pretty=format:%h%x1f%s%x1f%an%x1f%ct"])
        s.commits = log.stdout.split(separator: "\n").compactMap { line in
            let f = line.components(separatedBy: "\u{1f}")
            guard f.count == 4, let t = Double(f[3]) else { return nil }
            return GitCommit(hash: f[0], subject: f[1], author: f[2], date: Date(timeIntervalSince1970: t))
        }
        s.branches = (await git(repo, ["branch", "--format=%(refname:short)"])).stdout.split(separator: "\n").map(String.init)
        let remote = (await git(repo, ["remote", "get-url", "origin"])).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        s.remoteURL = remote.isEmpty ? nil : remote
        return s
    }

    /// Commit timestamps for the last year, for the heatmap (only the user's own commits when user.email is set).
    static func commitDays(_ repo: String) async -> [String: Int] {
        let email = (await git(repo, ["config", "user.email"])).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        var args = ["log", "--all", "--since=1.year", "--format=%ct"]
        if !email.isEmpty { args.append("--author=\(email)") }
        let out = await git(repo, args)
        return out.stdout.split(separator: "\n").reduce(into: [:]) { acc, line in
            if let t = Double(line) { acc[Date(timeIntervalSince1970: t).dayKey, default: 0] += 1 }
        }
    }

    enum Action: String { case fetch = "Fetch", pull = "Pull", push = "Push", stash = "Stash", stashPop = "Pop Stash" }

    static func run(_ action: Action, repo: String) async -> Shell.Result {
        switch action {
        case .fetch: await git(repo, ["fetch", "--all", "--prune"])
        case .pull: await git(repo, ["pull", "--ff-only"])
        case .push: await git(repo, ["push"])
        case .stash: await git(repo, ["stash", "push", "--include-untracked", "-m", "Command Center stash"])
        case .stashPop: await git(repo, ["stash", "pop"])
        }
    }

    static func switchBranch(_ branch: String, repo: String) async -> Shell.Result {
        await git(repo, ["switch", branch])
    }

    // MARK: Pull requests

    enum Host { case github(owner: String, repo: String), gitlab(path: String) }

    static func host(for remote: String) -> Host? {
        // git@github.com:owner/repo.git  |  https://github.com/owner/repo(.git)
        var r = remote.replacingOccurrences(of: ".git", with: "", options: [.anchored, .backwards])
        if r.hasPrefix("git@") { r = "https://" + r.dropFirst(4).replacingOccurrences(of: ":", with: "/") }
        guard let url = URL(string: r), let h = url.host else { return nil }
        let comps = url.path.split(separator: "/").map(String.init)
        if h.contains("github.com"), comps.count >= 2 { return .github(owner: comps[0], repo: comps[1]) }
        if h.contains("gitlab"), comps.count >= 2 { return .gitlab(path: comps.joined(separator: "/")) }
        return nil
    }

    static func pullRequests(remote: String) async -> [PullRequest]? {
        guard let host = host(for: remote) else { return nil }
        switch host {
        case .github(let owner, let repo):
            guard let token = await MainActor.run(body: { Keychain.get(KeychainKey.github) }) else { return nil }
            var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(owner)/\(repo)/pulls?state=open&per_page=10")!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            guard let (data, _) = try? await URLSession.shared.data(for: req),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
            return arr.compactMap { pr in
                guard let id = pr["id"] as? Int, let n = pr["number"] as? Int, let t = pr["title"] as? String,
                      let u = (pr["html_url"] as? String).flatMap(URL.init) else { return nil }
                return PullRequest(id: id, number: n, title: t, author: (pr["user"] as? [String: Any])?["login"] as? String ?? "",
                                   branch: (pr["head"] as? [String: Any])?["ref"] as? String ?? "", draft: pr["draft"] as? Bool ?? false,
                                   url: u, updated: ISO8601DateFormatter().date(from: pr["updated_at"] as? String ?? ""))
            }
        case .gitlab(let path):
            guard let token = await MainActor.run(body: { Keychain.get(KeychainKey.gitlab) }) else { return nil }
            let enc = path.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? path
            var req = URLRequest(url: URL(string: "https://gitlab.com/api/v4/projects/\(enc)/merge_requests?state=opened&per_page=10")!)
            req.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
            guard let (data, _) = try? await URLSession.shared.data(for: req),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
            return arr.compactMap { mr in
                guard let id = mr["id"] as? Int, let n = mr["iid"] as? Int, let t = mr["title"] as? String,
                      let u = (mr["web_url"] as? String).flatMap(URL.init) else { return nil }
                return PullRequest(id: id, number: n, title: t, author: (mr["author"] as? [String: Any])?["username"] as? String ?? "",
                                   branch: mr["source_branch"] as? String ?? "", draft: mr["draft"] as? Bool ?? false, url: u, updated: nil)
            }
        }
    }

    /// For "ask about my data": commits from today and yesterday across monitored repos.
    static func aiSummary() async -> String {
        let repos = UserDefaults.standard.stringArray(forKey: "git.repos") ?? []
        guard !repos.isEmpty else { return "" }
        var lines: [String] = []
        let since = Calendar.current.startOfDay(for: Date()).addingTimeInterval(-86400)
        for repo in repos {
            let out = await git(repo, ["log", "--all", "--since=\(Int(since.timeIntervalSince1970))", "--pretty=format:%h %ad %s", "--date=format:%a %H:%M"])
            let commits = out.stdout.split(separator: "\n")
            if !commits.isEmpty { lines.append("\((repo as NSString).lastPathComponent):\n" + commits.prefix(20).map { "  - \($0)" }.joined(separator: "\n")) }
        }
        return lines.isEmpty ? "Git: no commits since yesterday in monitored repos." : "Git commits since yesterday:\n" + lines.joined(separator: "\n")
    }
}
