import Foundation

/// Runs short-lived helper processes (git, shortcuts, lsof, ping) off the main thread.
enum Shell {
    struct Result { let status: Int32; let stdout: String; let stderr: String; var ok: Bool { status == 0 } }

    static func run(_ executable: String, _ args: [String], cwd: URL? = nil, timeout: TimeInterval = 30) async -> Result {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: runSync(executable, args, cwd: cwd, timeout: timeout))
            }
        }
    }

    static func runSync(_ executable: String, _ args: [String], cwd: URL? = nil, timeout: TimeInterval = 30) -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (env["PATH"] ?? "") + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["GIT_TERMINAL_PROMPT"] = "0"
        p.environment = env
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        do { try p.run() } catch { return Result(status: -1, stdout: "", stderr: error.localizedDescription) }
        let deadline = DispatchTime.now() + timeout
        let group = DispatchGroup()
        var outData = Data(), errData = Data()
        group.enter(); DispatchQueue.global().async { outData = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter(); DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        if group.wait(timeout: deadline) == .timedOut { p.terminate() }
        p.waitUntilExit()
        return Result(status: p.terminationStatus,
                      stdout: String(decoding: outData, as: UTF8.self),
                      stderr: String(decoding: errData, as: UTF8.self))
    }

    /// Runs a command line through the user's login shell.
    static func runLine(_ line: String, cwd: URL? = nil) async -> Result {
        await run(userShell, ["-lc", line], cwd: cwd, timeout: 120)
    }

    static var userShell: String {
        if let pw = getpwuid(getuid()), let sh = pw.pointee.pw_shell { return String(cString: sh) }
        return "/bin/zsh"
    }
}

/// Executes AppleScript for apps without a Swift API (Music, Spotify, Mail, Finder).
enum AppleScriptRunner {
    static func run(_ source: String) async -> (String?, String?) {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                cont.resume(returning: (result?.stringValue, error?[NSAppleScript.errorMessage] as? String))
            }
        }
    }

    static func descriptor(_ source: String) async -> NSAppleEventDescriptor? {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                cont.resume(returning: NSAppleScript(source: source)?.executeAndReturnError(&error))
            }
        }
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
