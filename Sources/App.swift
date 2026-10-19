import AppKit
import SwiftUI

/// Entry point. The status items need explicit length control, so they live in an
/// `NSApplicationDelegate` rather than a `MenuBarExtra` scene.
@main
struct MenuBarCollapseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

/// Creates the status bar controller, presents the Settings and Welcome windows,
/// and restores hidden icons when the app terminates.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusBarController?
    private var settingsWindow: NSWindow?
    private var welcomeWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
        NSApp.setActivationPolicy(.accessory)

        let controller = StatusBarController()
        controller.onOpenSettings = { [weak self] in self?.showSettings() }
        controller.onOpenWelcome = { [weak self] in self?.showWelcome() }
        self.controller = controller

        if UserDefaults.standard.bool(forKey: Prefs.hasSeenWelcome) {
            controller.collapseAfterLaunch()
        } else {
            UserDefaults.standard.set(true, forKey: Prefs.hasSeenWelcome)
            showWelcome()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // If the user quits while collapsed, shrink the divider so every icon comes back.
        controller?.restoreForQuit()
    }

    func showSettings() {
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "MenuBarCollapse Settings", root: SettingsView())
        }
        present(settingsWindow)
    }

    func showWelcome() {
        if welcomeWindow == nil {
            let view = WelcomeView(
                onOpenSettings: { [weak self] in
                    self?.welcomeWindow?.close()
                    self?.showSettings()
                },
                onDone: { [weak self] in self?.welcomeWindow?.close() }
            )
            welcomeWindow = makeWindow(title: "Welcome to MenuBarCollapse", root: view)
        }
        present(welcomeWindow)
    }

    private func makeWindow<Content: View>(title: String, root: Content) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = title
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func present(_ window: NSWindow?) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
