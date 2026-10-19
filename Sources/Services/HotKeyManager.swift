import AppKit
import Carbon.HIToolbox

/// Registers the single system-wide toggle shortcut through Carbon's `RegisterEventHotKey`.
/// No Accessibility permission is needed for this API.
@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()

    /// Called on the main thread whenever the registered shortcut is pressed.
    var onPress: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private init() {}

    /// (Re)registers the shortcut stored in UserDefaults; a key code of -1 means "no shortcut".
    func registerFromDefaults() {
        unregister()
        let defaults = UserDefaults.standard
        let keyCode = defaults.integer(forKey: Prefs.hotKeyCode)
        let modifiers = defaults.integer(forKey: Prefs.hotKeyModifiers)
        guard keyCode >= 0, modifiers > 0 else { return }

        installHandlerIfNeeded()
        let hotKeyID = EventHotKeyID(signature: OSType(0x4D42_4343), id: 1) // "MBCC"
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            NSLog("MenuBarCollapse: could not register hotkey (OSStatus \(status)); it may be in use by another app.")
            hotKeyRef = nil
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { HotKeyManager.shared.onPress?() }
            }
            return noErr
        }, 1, &spec, nil, &handlerRef)
        if status != noErr {
            NSLog("MenuBarCollapse: could not install hotkey handler (OSStatus \(status)).")
        }
    }

    // MARK: - Conversion helpers

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var mask = 0
        if flags.contains(.command) { mask |= cmdKey }
        if flags.contains(.option) { mask |= optionKey }
        if flags.contains(.control) { mask |= controlKey }
        if flags.contains(.shift) { mask |= shiftKey }
        return mask
    }

    static func symbols(for flags: NSEvent.ModifierFlags) -> String {
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text
    }

    private static let specialKeys: [UInt16: String] = [
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    static func keyName(for event: NSEvent) -> String {
        if let name = specialKeys[event.keyCode] { return name }
        let chars = event.charactersIgnoringModifiers?.uppercased() ?? ""
        return chars.isEmpty ? "Key \(event.keyCode)" : chars
    }
}
