import Foundation

/// How the divider status item is drawn while the bar is expanded.
enum DividerStyle: String, CaseIterable, Identifiable {
    case line
    case dot

    var id: String { rawValue }
    var title: String { self == .line ? "Thin line" : "Dot" }
}

/// Central list of UserDefaults keys and defaults shared by SwiftUI `@AppStorage` and the AppKit controllers.
enum Prefs {
    static let autoHideDelay = "autoHideDelay"            // seconds, 0 = off
    static let hotKeyCode = "hotKeyCode"                  // virtual key code, -1 = no shortcut
    static let hotKeyModifiers = "hotKeyModifiers"        // Carbon modifier mask
    static let hotKeyDisplay = "hotKeyDisplay"            // human-readable shortcut, e.g. "⌥⌘B"
    static let dividerStyle = "dividerStyle"
    static let expandOnHover = "expandOnHover"
    static let hideChevronWhenExpanded = "hideChevronWhenExpanded"
    static let hasSeenWelcome = "hasSeenWelcome"

    static let defaultAutoHideDelay = 15.0
    static let defaultKeyCode = 11                        // "B"
    static let defaultModifiers = 256 | 2048              // cmdKey | optionKey
    static let defaultDisplay = "⌥⌘B"

    /// Registers fallback values so first-launch reads behave like the Settings UI defaults.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            autoHideDelay: defaultAutoHideDelay,
            hotKeyCode: defaultKeyCode,
            hotKeyModifiers: defaultModifiers,
            hotKeyDisplay: defaultDisplay,
            dividerStyle: DividerStyle.line.rawValue,
            expandOnHover: false,
            hideChevronWhenExpanded: false,
            hasSeenWelcome: false,
        ])
    }
}
