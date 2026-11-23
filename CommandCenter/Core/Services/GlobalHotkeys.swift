import Carbon.HIToolbox
import Foundation

/// System-wide hotkeys via Carbon `RegisterEventHotKey` (no Accessibility permission needed).
@MainActor
final class GlobalHotkeys {
    static let shared = GlobalHotkeys()

    enum Action: UInt32, CaseIterable {
        case toggleTerminal = 1, quickCapture, askAI, commandPalette

        var label: String {
            switch self {
            case .toggleTerminal: "Toggle menu bar terminal"
            case .quickCapture: "Quick capture to Inbox"
            case .askAI: "Ask AI"
            case .commandPalette: "Command palette"
            }
        }
        var display: String {
            switch self {
            case .toggleTerminal: "⌘⇧Space"
            case .quickCapture: "⌘⇧N"
            case .askAI: "⌘⇧A"
            case .commandPalette: "⌘⇧P"
            }
        }
        var keyCode: UInt32 {
            switch self {
            case .toggleTerminal: UInt32(kVK_Space)
            case .quickCapture: UInt32(kVK_ANSI_N)
            case .askAI: UInt32(kVK_ANSI_A)
            case .commandPalette: UInt32(kVK_ANSI_P)
            }
        }
        var defaultsKey: String { "hotkey.\(rawValue).enabled" }
    }

    private var refs: [Action: EventHotKeyRef] = [:]
    private var handlerInstalled = false
    var handler: ((Action) -> Void)?

    func registerAll() {
        installHandler()
        for action in Action.allCases {
            let enabled = UserDefaults.standard.object(forKey: action.defaultsKey) as? Bool ?? true
            setEnabled(action, enabled)
        }
    }

    func setEnabled(_ action: Action, _ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: action.defaultsKey)
        if let ref = refs[action] { UnregisterEventHotKey(ref); refs[action] = nil }
        guard enabled else { return }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x43434E54), id: action.rawValue) // 'CCNT'
        let status = RegisterEventHotKey(action.keyCode, UInt32(cmdKey | shiftKey), id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { refs[action] = ref }
    }

    func isEnabled(_ action: Action) -> Bool { refs[action] != nil }

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            if let action = GlobalHotkeys.Action(rawValue: hk.id) {
                DispatchQueue.main.async { GlobalHotkeys.shared.handler?(action) }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
