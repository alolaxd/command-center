import SwiftUI

enum ThemeMode: String, CaseIterable, Identifiable {
    case auto = "Auto", light = "Light", dark = "Dark"
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self { case .auto: nil; case .light: .light; case .dark: .dark }
    }
}

enum AccentChoice: String, CaseIterable, Identifiable {
    case system, blue, purple, pink, red, orange, yellow, green, teal, graphite
    var id: String { rawValue }
    var color: Color? {
        switch self {
        case .system: nil
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .graphite: .gray
        }
    }
}

/// UserDefaults keys used with @AppStorage across the app.
enum SettingsKey {
    static let theme = "theme"
    static let accent = "accent"
    static let rowHeight = "grid.rowHeight"
    static let showSidebar = "ui.showSidebar"
    static let textScale = "ui.textScale"
    static let appLock = "security.appLock"
    static let hotkeysEnabled = "hotkeys.enabled"
    static let onboarded = "ui.onboarded"
    static let aiProvider = "ai.provider"
    static func aiModel(_ p: AIProvider) -> String { "ai.model.\(p.rawValue)" }
    static let ollamaURL = "ai.ollamaURL"
    static let publicIPLookup = "net.publicIP"
}

enum TextScale: String, CaseIterable, Identifiable {
    case small = "Small", standard = "Default", large = "Large", xLarge = "Extra Large"
    var id: String { rawValue }
    var dynamicType: DynamicTypeSize {
        switch self { case .small: .small; case .standard: .large; case .large: .xLarge; case .xLarge: .xxLarge }
    }
}
