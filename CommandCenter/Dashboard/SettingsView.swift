import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            HotkeySettings().tabItem { Label("Hotkeys", systemImage: "keyboard") }
            AISettings().tabItem { Label("AI", systemImage: "sparkles") }
            IntegrationSettings().tabItem { Label("Integrations", systemImage: "link") }
            DataSettings().tabItem { Label("Data", systemImage: "externaldrive") }
        }
        .frame(width: 540, height: 420)
    }
}

private struct GeneralSettings: View {
    @AppStorage(SettingsKey.theme) private var theme = ThemeMode.auto.rawValue
    @AppStorage(SettingsKey.accent) private var accent = AccentChoice.system.rawValue
    @AppStorage(SettingsKey.textScale) private var textScale = TextScale.standard.rawValue
    @AppStorage(SettingsKey.rowHeight) private var rowHeight: Double = 84
    @AppStorage(SettingsKey.showSidebar) private var showSidebar = false
    @AppStorage(SettingsKey.appLock) private var appLock = false

    var body: some View {
        Form {
            Picker("Appearance", selection: $theme) { ForEach(ThemeMode.allCases) { Text($0.rawValue).tag($0.rawValue) } }
                .pickerStyle(.segmented)
            Picker("Accent color", selection: $accent) {
                ForEach(AccentChoice.allCases) { c in
                    HStack { Circle().fill(c.color ?? .accentColor).frame(width: 10, height: 10); Text(c.rawValue.capitalized) }.tag(c.rawValue)
                }
            }
            Picker("Text size", selection: $textScale) { ForEach(TextScale.allCases) { Text($0.rawValue).tag($0.rawValue) } }
            Slider(value: $rowHeight, in: 60...140, step: 4) { Text("Grid row height") }
            Picker("Columns (current workspace)", selection: Binding(
                get: { WorkspaceStore.shared.current?.columns ?? 12 },
                set: { WorkspaceStore.shared.setColumns($0) })) {
                ForEach([6, 8, 10, 12, 16], id: \.self) { Text("\($0)").tag($0) }
            }
            Toggle("Show widget list sidebar", isOn: $showSidebar)
            Toggle("Require Touch ID to open", isOn: $appLock)
        }
        .formStyle(.grouped)
    }
}

private struct HotkeySettings: View {
    @State private var refresh = 0
    var body: some View {
        Form {
            Section("Global (work in any app)") {
                ForEach(GlobalHotkeys.Action.allCases, id: \.rawValue) { action in
                    Toggle(isOn: Binding(get: { _ = refresh; return GlobalHotkeys.shared.isEnabled(action) },
                                         set: { GlobalHotkeys.shared.setEnabled(action, $0); refresh += 1 })) {
                        HStack { Text(action.label); Spacer(); Text(action.display).foregroundStyle(.secondary).monospaced() }
                    }
                }
            }
            Section("In app") {
                LabeledContent("Switch workspace", value: "⌘1 – ⌘9")
                LabeledContent("Zen mode", value: "⌘⇧Z")
                LabeledContent("New terminal tab", value: "⌘⇧T")
                LabeledContent("Add widget", value: "⌘⇧W")
                LabeledContent("Move focus between widgets", value: "← → ↑ ↓")
                LabeledContent("Move / resize focused widget", value: "⌥ arrows / ⌥⇧ arrows")
            }
        }
        .formStyle(.grouped)
    }
}

private struct AISettings: View {
    @AppStorage(SettingsKey.aiProvider) private var providerRaw = AIProvider.anthropic.rawValue
    @AppStorage(SettingsKey.ollamaURL) private var ollamaURL = "http://localhost:11434"
    @State private var keys: [AIProvider: String] = [:]
    @State private var models: [AIProvider: String] = [:]
    @State private var saved: [AIProvider: Bool] = [:]
    @State private var testResult = ""

    var body: some View {
        Form {
            Picker("Provider", selection: $providerRaw) { ForEach(AIProvider.allCases) { Text($0.rawValue).tag($0.rawValue) } }
            ForEach(AIProvider.allCases) { p in
                Section(p.rawValue) {
                    if let account = p.keychainKey {
                        SecretField(label: "API key", account: account)
                    } else {
                        TextField("Server URL", text: $ollamaURL)
                        Text(AIService.shared.ollamaDetected ? "Ollama detected" : "Ollama not detected")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    TextField("Model", text: Binding(get: { models[p] ?? "" }, set: {
                        models[p] = $0
                        UserDefaults.standard.set($0, forKey: SettingsKey.aiModel(p))
                    }), prompt: Text(p.defaultModel))
                }
            }
            HStack {
                Button("Test connection") { test() }
                Text(testResult).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            for p in AIProvider.allCases { models[p] = UserDefaults.standard.string(forKey: SettingsKey.aiModel(p)) ?? "" }
            Task { await AIService.shared.detectOllama() }
        }
    }

    private func test() {
        testResult = "Testing…"
        Task {
            do { testResult = "OK: " + (try await AIService.shared.ask("Reply with the single word: ready")).prefix(60) }
            catch { testResult = error.localizedDescription }
        }
    }
}

/// Secure field that loads from and saves to the Keychain as you type, with visible confirmation.
struct SecretField: View {
    let label: String
    let account: String
    @State private var value = ""
    @State private var status: Status = .idle
    @State private var saveTask: Task<Void, Never>?
    @State private var reveal = false

    enum Status: Equatable { case idle, saving, saved, failed(OSStatus) }

    var body: some View {
        HStack {
            Group {
                if reveal { TextField(label, text: $value) } else { SecureField(label, text: $value) }
            }
            .onSubmit { save() }
            Button { reveal.toggle() } label: { Image(systemName: reveal ? "eye.slash" : "eye") }
                .buttonStyle(.borderless).help(reveal ? "Hide" : "Show").accessibilityLabel(reveal ? "Hide" : "Show")
            switch status {
            case .idle: EmptyView()
            case .saving: ProgressView().controlSize(.small)
            case .saved: Label("Saved", systemImage: "checkmark.circle.fill").labelStyle(.titleAndIcon).font(.caption).foregroundStyle(.green)
            case .failed(let code): Label("Not saved (\(code))", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.red)
            }
        }
        .onAppear { value = Keychain.get(account) ?? "" }
        .onChange(of: value) {
            status = .saving
            saveTask?.cancel()
            saveTask = Task { try? await Task.sleep(for: .milliseconds(400)); if !Task.isCancelled { save() } }
        }
        .onDisappear { saveTask?.cancel(); save() }
    }

    private func save() {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (Keychain.get(account) ?? "") else { if status == .saving { status = .saved }; return }
        Keychain.set(trimmed.isEmpty ? nil : trimmed, for: account)
        let ok = trimmed.isEmpty ? Keychain.get(account) == nil : Keychain.get(account) == trimmed
        status = ok ? .saved : .failed(Keychain.lastStatus)
    }
}

private struct IntegrationSettings: View {
    @AppStorage(SettingsKey.publicIPLookup) private var publicIP = false
    @State private var githubCheck = ""
    var body: some View {
        Form {
            Section("Git hosting (for pull request status)") {
                SecretField(label: "GitHub personal access token", account: KeychainKey.github)
                SecretField(label: "GitLab personal access token", account: KeychainKey.gitlab)
                HStack {
                    Button("Verify GitHub Token") { verify() }
                    Text(githubCheck).font(.caption).foregroundStyle(.secondary)
                }
                Text("Tokens are stored in your macOS Keychain and saved as you type. GitHub: a fine-grained token with read access to pull requests is enough.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Network") {
                Toggle("Look up public IP (api.ipify.org)", isOn: $publicIP)
            }
            Section("Privacy") {
                Text("No telemetry or analytics. The app only contacts services you configure: AI providers, weather (Open-Meteo, RainViewer), market data (Yahoo Finance, CoinGecko), RSS feeds, monitored endpoints, and Git hosts.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func verify() {
        guard let token = Keychain.get(KeychainKey.github) else { githubCheck = "No token saved"; return }
        githubCheck = "Checking…"
        Task {
            var req = URLRequest(url: URL(string: "https://api.github.com/user")!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            guard let (data, resp) = try? await URLSession.shared.data(for: req) else { githubCheck = "Network error"; return }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let login = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["login"] as? String
            githubCheck = code == 200 ? "Valid — signed in as \(login ?? "?")" : "GitHub rejected the token (HTTP \(code))"
        }
    }
}

private struct DataSettings: View {
    @State private var message = ""
    var body: some View {
        Form {
            Section("Layouts") {
                HStack {
                    Button("Export Layouts…") { exportLayouts() }
                    Button("Import Layouts…") { importLayouts() }
                }
                Menu("Add Layout Preset") {
                    ForEach(WorkspacePresets.presets, id: \.0) { name, ws in
                        Button(name) { WorkspaceStore.shared.applyPreset(ws) }
                    }
                }
            }
            Section("Storage") {
                LabeledContent("Data folder", value: AppPaths.root.path).textSelection(.enabled)
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([AppPaths.root]) }
            }
            if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
        .formStyle(.grouped)
    }

    private func exportLayouts() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "CommandCenter-Layouts.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try WorkspaceStore.shared.exportJSON().write(to: url); message = "Exported to \(url.lastPathComponent)" }
        catch { message = error.localizedDescription }
    }

    private func importLayouts() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try WorkspaceStore.shared.importJSON(Data(contentsOf: url), replace: false); message = "Imported \(url.lastPathComponent)" }
        catch { message = error.localizedDescription }
    }
}

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Welcome to Command Center").font(.title.bold())
            Text("A modular dashboard that lives in a window and in your menu bar.").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                row("square.grid.3x3", "Widgets on a grid", "Drag a widget's header to move it; drag its bottom-right corner to resize. Add more with +.")
                row("rectangle.stack", "Workspaces", "Home, Dev, Finance and Health are ready. Switch with ⌘1–⌘9 or swipe.")
                row("menubar.rectangle", "Menu bar terminal", "⌘⇧Space opens a real shell anywhere. Type > for app commands.")
                row("tray.and.arrow.down", "Quick capture", "⌘⇧N sends a thought to your Inbox.")
                row("sparkles", "AI", "Add a Claude, OpenAI or OpenRouter key in Settings, or run Ollama locally.")
                row("lock.shield", "Local-first", "Everything is stored in ~/Library/Application Support/CommandCenter. No telemetry.")
            }
            HStack {
                Spacer()
                Button("Get Started") { Notifier.requestAuthorization(); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 520)
    }

    private func row(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title3).frame(width: 28)
            VStack(alignment: .leading) { Text(title).font(.headline); Text(text).font(.callout).foregroundStyle(.secondary) }
        }
    }
}
