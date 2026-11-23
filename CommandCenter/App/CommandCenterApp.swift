import SwiftUI

@main
struct CommandCenterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @AppStorage(SettingsKey.theme) private var theme = ThemeMode.auto.rawValue
    @AppStorage(SettingsKey.accent) private var accent = AccentChoice.system.rawValue
    @AppStorage(SettingsKey.textScale) private var textScale = TextScale.standard.rawValue

    var body: some Scene {
        Window("Command Center", id: "main") {
            MainView()
                .frame(minWidth: 900, minHeight: 560)
                .modifier(AppearanceModifier(theme: theme, accent: accent, textScale: textScale))
                .modifier(WindowOpenerCapture())
        }
        .defaultSize(width: 1400, height: 900)
        .commands { AppCommands() }

        Settings {
            SettingsView()
                .modifier(AppearanceModifier(theme: theme, accent: accent, textScale: textScale))
        }
    }
}

struct AppearanceModifier: ViewModifier {
    let theme: String
    let accent: String
    let textScale: String
    func body(content: Content) -> some View {
        content
            .preferredColorScheme(ThemeMode(rawValue: theme)?.colorScheme)
            .tint(AccentChoice(rawValue: accent)?.color)
            .dynamicTypeSize((TextScale(rawValue: textScale) ?? .standard).dynamicType)
    }
}

private struct WindowOpenerCapture: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    func body(content: Content) -> some View {
        content.onAppear {
            let open = openWindow
            AppState.openWindowAction = { open(id: $0) }
        }
    }
}

struct AppCommands: Commands {
    private var store: WorkspaceStore { .shared }

    var body: some Commands {
        CommandMenu("Workspace") {
            ForEach(0..<9, id: \.self) { i in
                Button(i < store.workspaces.count ? store.workspaces[i].name : "Workspace \(i + 1)") { store.select(index: i) }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                    .disabled(i >= store.workspaces.count)
            }
            Divider()
            Button("Next Workspace") { store.selectNext(1) }.keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            Button("Previous Workspace") { store.selectNext(-1) }.keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Button("New Workspace") { store.addWorkspace(name: "Workspace \(store.workspaces.count + 1)") }
            Button("Manage Workspaces…") { NotificationCenter.default.post(name: .manageWorkspaces, object: nil) }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Button("Delete Current Workspace…") { NotificationCenter.default.post(name: .deleteCurrentWorkspace, object: nil) }
                .disabled(store.workspaces.isEmpty)
            Divider()
            Button("Add Widget…") { NotificationCenter.default.post(name: .showWidgetGallery, object: nil) }
                .keyboardShortcut("w", modifiers: [.command, .shift])
            Button("Tidy Up Layout") { withAnimation(.spring(response: 0.35)) { store.tidyUp() } }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Button("Zen Mode") { withAnimation(.spring(response: 0.35)) { store.toggleZen() } }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            Button("New Terminal Tab") { TerminalPanesCommands.newTab() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .appTermination) {
            Button("Close to Menu Bar") { AppState.hideToMenuBar() }
                .keyboardShortcut("q", modifiers: .command)
            Button("Quit Completely") { AppState.quitCompletely() }
                .keyboardShortcut("q", modifiers: [.command, .option])
        }
        CommandGroup(after: .appSettings) {
            Button("Open Menu Bar Terminal") { StatusItemController.shared.toggle(tab: .terminal) }
            Button("Command Palette") { StatusItemController.shared.toggle(tab: .terminal, prefill: ">") }
        }
    }
}
