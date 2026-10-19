import AppKit
import ServiceManagement
import SwiftUI

/// The Settings window: auto-hide delay, hotkey, divider style, hover, chevron and login options.
struct SettingsView: View {
    @AppStorage(Prefs.autoHideDelay) private var autoHideDelay = Prefs.defaultAutoHideDelay
    @AppStorage(Prefs.dividerStyle) private var dividerStyle = DividerStyle.line.rawValue
    @AppStorage(Prefs.expandOnHover) private var expandOnHover = false
    @AppStorage(Prefs.hideChevronWhenExpanded) private var hideChevronWhenExpanded = false

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginMessage: String?

    var body: some View {
        Form {
            Section("Hiding") {
                Stepper(value: $autoHideDelay, in: 0...600, step: 5) {
                    LabeledContent("Auto-hide after",
                                   value: autoHideDelay == 0 ? "Off" : "\(Int(autoHideDelay)) s")
                }
                Toggle("Expand when hovering over the chevron", isOn: $expandOnHover)
                Toggle("Hide chevron when expanded", isOn: $hideChevronWhenExpanded)
                if hideChevronWhenExpanded {
                    Text("Click the divider or use the shortcut to collapse again.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Appearance") {
                Picker("Show divider as", selection: $dividerStyle) {
                    ForEach(DividerStyle.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
            }

            Section("Shortcut") {
                LabeledContent("Toggle hidden icons") { HotKeyRecorder() }
            }

            Section("General") {
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                if let loginMessage {
                    Text(loginMessage).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Notch displays") {
                Text("On MacBooks with a notch, icons right of the divider can still end up under the notch. Keep fewer icons there, or ⌘-drag them left of the divider.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("MenuBarCollapse is free and open source.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Support / Donate ❤️") {
                        NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginMessage = nil
        } catch {
            loginMessage = "Couldn't change login item: \(error.localizedDescription)"
        }
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        if status == .requiresApproval {
            loginMessage = "Approve MenuBarCollapse in System Settings › General › Login Items."
        }
    }
}

/// A button that captures the next key combination and stores it as the global toggle shortcut.
struct HotKeyRecorder: View {
    @AppStorage(Prefs.hotKeyCode) private var keyCode = Prefs.defaultKeyCode
    @AppStorage(Prefs.hotKeyModifiers) private var modifiers = Prefs.defaultModifiers
    @AppStorage(Prefs.hotKeyDisplay) private var display = Prefs.defaultDisplay

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var hint: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack {
                Button(isRecording ? "Type shortcut…" : (keyCode < 0 ? "Record Shortcut" : display)) {
                    isRecording ? stop() : start()
                }
                .frame(minWidth: 110)
                if keyCode >= 0 && !isRecording {
                    Button("Clear") {
                        keyCode = -1
                        display = ""
                    }
                }
            }
            if let hint {
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        isRecording = true
        hint = "Press a combination with ⌘, ⌥ or ⌃ (Esc cancels)."
        HotKeyManager.shared.unregister() // Let the current shortcut reach the recorder.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == 53 { // Esc
            stop()
            return
        }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.isEmpty, flags != .shift else {
            hint = "Include ⌘, ⌥ or ⌃ in the shortcut."
            return
        }
        keyCode = Int(event.keyCode)
        modifiers = HotKeyManager.carbonModifiers(from: flags)
        display = HotKeyManager.symbols(for: flags) + HotKeyManager.keyName(for: event)
        stop()
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if isRecording {
            isRecording = false
            hint = nil
            HotKeyManager.shared.registerFromDefaults()
        }
    }
}
