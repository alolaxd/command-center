import AppKit
import SwiftTerm
import SwiftUI

/// A real PTY running the user's login shell, rendered by SwiftTerm (full VT/ANSI/256-color/truecolor).
/// Sessions outlive the views that show them, so terminals persist across workspace switches.
@MainActor @Observable
final class TerminalSession: NSObject, Identifiable, LocalProcessTerminalViewDelegate {
    let id = UUID()
    var title: String = "zsh"
    var cwd: String?
    var isRunning = false
    @ObservationIgnored let view: CCTerminalView

    init(cwd: String? = nil, fontSize: CGFloat = 12) {
        view = CCTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
        super.init()
        view.cwdProvider = { [weak self] in self?.cwd }
        view.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        // Fixed terminal palette: readable in both light and dark mode, and immune to appearance changes
        // (SwiftTerm resolves colours once, so dynamic system colours could end up white-on-white).
        view.nativeBackgroundColor = NSColor(srgbRed: 0.075, green: 0.08, blue: 0.09, alpha: 1)
        view.nativeForegroundColor = NSColor(srgbRed: 0.88, green: 0.89, blue: 0.9, alpha: 1)
        view.caretColor = NSColor(srgbRed: 0.88, green: 0.89, blue: 0.9, alpha: 0.8)
        view.processDelegate = self
        view.linkReporting = .implicit
        start(cwd: cwd)
    }

    func start(cwd: String? = nil) {
        var shell = Shell.userShell
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        env.append("COLORTERM=truecolor")
        env.append("TERM_PROGRAM=CommandCenter")
        var dir = cwd ?? FileManager.default.homeDirectoryForCurrentUser.path
        if AppPaths.demoMode {
            // Neutral prompt, no personal shell config or history.
            let demo = FileManager.default.temporaryDirectory.appendingPathComponent("cc-demo-shell")
            try? FileManager.default.createDirectory(at: demo.appendingPathComponent("acme-api/src"), withIntermediateDirectories: true)
            try? "PROMPT='%F{green}➜%f %F{cyan}%1~%f '\nunsetopt PROMPT_SP\nHISTFILE=/dev/null\n".write(to: demo.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)
            env.append("ZDOTDIR=\(demo.path)")
            shell = "/bin/zsh"
            dir = demo.appendingPathComponent("acme-api").path
        }
        self.cwd = dir
        title = (shell as NSString).lastPathComponent
        view.startProcess(executable: shell, args: ["-l"], environment: env,
                          execName: "-" + (shell as NSString).lastPathComponent, currentDirectory: dir)
        isRunning = true
    }

    func send(_ text: String) { view.send(txt: text) }

    func runLine(_ line: String) { send(line + "\r") }

    func terminate() {
        view.terminate()
        isRunning = false
    }

    func showFind() {
        view.window?.makeFirstResponder(view)
        let item = NSMenuItem()
        item.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        view.performFindPanelAction(item)
    }

    @discardableResult
    func find(_ term: String, backwards: Bool = false) -> Bool {
        backwards ? view.findPrevious(term) : view.findNext(term)
    }

    func clear() { send("clear\r") }

    // MARK: LocalProcessTerminalViewDelegate
    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        Task { @MainActor in self.title = title.isEmpty ? self.title : title }
    }
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        Task { @MainActor in self.cwd = directory.flatMap { URL(string: $0)?.path ?? $0 } ?? self.cwd }
    }
    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor in self.isRunning = false; self.title += " (exited)" }
    }
}

/// Keeps sessions alive independently of SwiftUI view lifetimes.
@MainActor
final class TerminalManager {
    static let shared = TerminalManager()
    private(set) var sessions: [UUID: TerminalSession] = [:]

    lazy var quick: TerminalSession = TerminalSession(fontSize: 12)

    func session(_ id: UUID) -> TerminalSession? { sessions[id] }

    func create(cwd: String? = nil) -> TerminalSession {
        let s = TerminalSession(cwd: cwd)
        sessions[s.id] = s
        return s
    }

    /// Restores a session for a persisted ID, creating a fresh shell under that ID's slot.
    func session(for key: UUID, cwd: String? = nil) -> TerminalSession {
        if let s = sessions[key] { return s }
        let s = TerminalSession(cwd: cwd)
        sessions[key] = s
        return s
    }

    func close(_ key: UUID) {
        sessions[key]?.terminate()
        sessions[key] = nil
    }
}

/// Hosts a session's NSView inside SwiftUI. A session has exactly one NSView, so when several
/// hosts exist (e.g. the hidden drop-down panel and the visible notch island) only a host in a
/// visible window may claim it; hosts re-claim when their window becomes key or visible again.
struct TerminalHostView: NSViewRepresentable {
    let session: TerminalSession
    var focusOnAppear = false

    func makeNSView(context: Context) -> TerminalContainerView {
        let c = TerminalContainerView()
        c.session = session
        c.focusOnAppear = focusOnAppear
        return c
    }

    func updateNSView(_ container: TerminalContainerView, context: Context) {
        container.session = session
        container.claimIfVisible()
    }
}

final class TerminalContainerView: NSView {
    var session: TerminalSession?
    var focusOnAppear = false
    private var observers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        guard let window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didChangeOcclusionStateNotification, NSWindow.didUpdateNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.claimIfVisible() }
            })
        }
        claimIfVisible()
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    @MainActor func claimIfVisible() {
        guard let session, let window, window.isVisible, session.view.superview !== self else { return }
        let v = session.view
        v.removeFromSuperview()
        v.translatesAutoresizingMaskIntoConstraints = false
        addSubview(v)
        NSLayoutConstraint.activate([
            v.leadingAnchor.constraint(equalTo: leadingAnchor), v.trailingAnchor.constraint(equalTo: trailingAnchor),
            v.topAnchor.constraint(equalTo: topAnchor), v.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        if focusOnAppear { DispatchQueue.main.async { v.window?.makeFirstResponder(v) } }
    }
}

/// SwiftTerm view with Command Center extras: clickable file paths (resolved against the shell's cwd)
/// and drag & drop of text / files into the shell.
final class CCTerminalView: LocalProcessTerminalView {
    var cwdProvider: (() -> String?)?
    /// Plain text of the scrollback + screen (copied snapshot; safe from any thread).
    var transcriptText: String { String(decoding: getBufferAsData(kind: .active, encoding: .utf8), as: UTF8.self) }

    /// Screen contents re-encoded with ANSI attributes (colours preserved).
    var ansiTranscript: String { terminalContentSnapshot(region: .all)?.ansiRepresentation() ?? "" }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.string, .fileURL])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func requestOpenLink(source: TerminalView, request: TerminalLinkRequest) {
        let link = request.link.trimmingCharacters(in: .whitespaces)
        if link.hasPrefix("/") || link.hasPrefix("~") || link.hasPrefix("./") || link.hasPrefix("../") {
            // Strip :line:col suffixes from compiler output.
            let pathPart = link.split(separator: ":").first.map(String.init) ?? link
            var path = (pathPart as NSString).expandingTildeInPath
            if !path.hasPrefix("/"), let cwd = cwdProvider?() { path = (cwd as NSString).appendingPathComponent(path) }
            if FileManager.default.fileExists(atPath: path) {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
                return
            }
        }
        super.requestOpenLink(source: source, request: request)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            send(txt: urls.map { "'" + $0.path.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ") + " ")
            return true
        }
        if let text = pb.string(forType: .string) {
            send(txt: text)
            window?.makeFirstResponder(self)
            return true
        }
        return false
    }
}
