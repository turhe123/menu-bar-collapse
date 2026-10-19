import AppKit
import UserNotifications

/// Forwards mouse-entered events from an `NSTrackingArea` on the chevron button to a closure.
final class HoverTracker: NSResponder {
    private let onEnter: () -> Void

    init(onEnter: @escaping () -> Void) {
        self.onEnter = onEnter
        super.init()
    }

    required init?(coder: NSCoder) { nil }

    override func mouseEntered(with event: NSEvent) { onEnter() }
}

/// Owns the chevron and divider status items and implements collapse/expand, auto-hide,
/// hover expansion, ordering checks, display-change handling and the quick menu.
@MainActor
final class StatusBarController: NSObject {
    var onOpenSettings: (() -> Void)?
    var onOpenWelcome: (() -> Void)?

    private(set) var isCollapsed = false

    private let chevronItem: NSStatusItem
    private let dividerItem: NSStatusItem
    private let collapsedLength: CGFloat = 10_000
    private var expandedLength: CGFloat = 10
    private var autoHideTimer: Timer?
    private var hoverTracker: HoverTracker?
    private var observers: [NSObjectProtocol] = []
    private var lastSettings: SettingsSnapshot?
    private var didWarnNoSpace = false

    /// The subset of preferences the controller reacts to; compared to skip unrelated defaults writes.
    private struct SettingsSnapshot: Equatable {
        var style: String
        var keyCode: Int
        var modifiers: Int
        var hideChevron: Bool

        static func current() -> SettingsSnapshot {
            let d = UserDefaults.standard
            return SettingsSnapshot(style: d.string(forKey: Prefs.dividerStyle) ?? DividerStyle.line.rawValue,
                                    keyCode: d.integer(forKey: Prefs.hotKeyCode),
                                    modifiers: d.integer(forKey: Prefs.hotKeyModifiers),
                                    hideChevron: d.bool(forKey: Prefs.hideChevronWhenExpanded))
        }
    }

    override init() {
        // Items created later sit further left, so the divider ends up left of the chevron by default.
        chevronItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        dividerItem = NSStatusBar.system.statusItem(withLength: 10)
        super.init()
        chevronItem.autosaveName = "MenuBarCollapse.chevron"
        dividerItem.autosaveName = "MenuBarCollapse.divider"
        chevronItem.behavior = []
        dividerItem.behavior = []
        configureButtons()
        applySettings()
        HotKeyManager.shared.onPress = { [weak self] in self?.toggle() }
        installObservers()
        updateChevronImage()
    }

    // MARK: - Public actions

    func toggle() {
        isCollapsed ? expand() : collapse(userInitiated: true)
    }

    /// Pushes everything left of the divider off-screen by making the divider enormous.
    func collapse(userInitiated: Bool = false) {
        guard !isCollapsed else { return }
        guard isOrderedCorrectly else {
            // Collapsing now would hide the chevron itself; surface the warning instead.
            if userInitiated {
                NSSound.beep()
                showMenu()
            }
            return
        }
        autoHideTimer?.invalidate()
        isCollapsed = true
        chevronItem.isVisible = true
        dividerItem.length = collapsedLength
        updateChevronImage()
    }

    /// Restores the divider to its normal width so hidden icons reappear, then restarts auto-hide.
    func expand() {
        if isCollapsed {
            isCollapsed = false
            dividerItem.length = expandedLength
            if UserDefaults.standard.bool(forKey: Prefs.hideChevronWhenExpanded) {
                chevronItem.isVisible = false
            }
            updateChevronImage()
        }
        scheduleAutoHide()
    }

    /// Called shortly after launch once the status items have been laid out.
    func collapseAfterLaunch() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            MainActor.assumeIsolated {
                self?.collapse()
                self?.checkVisibility()
            }
        }
    }

    /// Ensures icons are visible again when the app quits.
    func restoreForQuit() {
        autoHideTimer?.invalidate()
        dividerItem.length = expandedLength
        chevronItem.isVisible = true
        isCollapsed = false
    }

    // MARK: - Setup

    private func configureButtons() {
        if let button = chevronItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "MenuBarCollapse — click to hide/show icons, Option-click for menu"
            let tracker = HoverTracker { [weak self] in self?.hoverEntered() }
            button.addTrackingArea(NSTrackingArea(rect: .zero,
                                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                                  owner: tracker, userInfo: nil))
            hoverTracker = tracker
        }
        if let button = dividerItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
            button.toolTip = "MenuBarCollapse divider — ⌘-drag icons to the left of this to make them hideable"
        }
    }

    private func installObservers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySettings() }
        })
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainActor.assumeIsolated { self?.recalculateAfterDisplayChange() }
            }
        })
    }

    /// Re-applies divider style, hotkey and chevron visibility when the relevant preferences change.
    private func applySettings() {
        let settings = SettingsSnapshot.current()
        guard settings != lastSettings else { return }
        let previous = lastSettings
        lastSettings = settings

        if previous?.style != settings.style {
            applyDividerStyle(DividerStyle(rawValue: settings.style) ?? .line)
        }
        if previous?.keyCode != settings.keyCode || previous?.modifiers != settings.modifiers {
            HotKeyManager.shared.registerFromDefaults()
        }
        if previous?.hideChevron != settings.hideChevron, !isCollapsed {
            chevronItem.isVisible = !settings.hideChevron
        }
    }

    private func applyDividerStyle(_ style: DividerStyle) {
        let size = style == .line ? NSSize(width: 2, height: 14) : NSSize(width: 6, height: 6)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            if style == .line {
                NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
            } else {
                NSBezierPath(ovalIn: rect).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Divider"
        dividerItem.button?.image = image
        expandedLength = style == .line ? 10 : 14
        if !isCollapsed { dividerItem.length = expandedLength }
    }

    private func updateChevronImage() {
        let name = isCollapsed ? "chevron.right" : "chevron.left"
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: isCollapsed ? "Show hidden icons" : "Hide icons")?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        chevronItem.button?.image = image
    }

    // MARK: - Events

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.option) == true {
            showMenu()
        } else {
            toggle()
        }
    }

    private func hoverEntered() {
        guard isCollapsed, UserDefaults.standard.bool(forKey: Prefs.expandOnHover) else { return }
        expand()
    }

    private func scheduleAutoHide() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        let delay = UserDefaults.standard.double(forKey: Prefs.autoHideDelay)
        guard delay > 0 else { return }
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.collapse() }
        }
    }

    private func recalculateAfterDisplayChange() {
        if isCollapsed {
            if isOrderedCorrectly {
                dividerItem.length = collapsedLength
            } else {
                expand()
            }
        }
        checkVisibility()
    }

    // MARK: - Ordering & visibility

    /// True when the divider sits to the left of the chevron (compared in screen coordinates).
    var isOrderedCorrectly: Bool {
        guard chevronItem.isVisible,
              let divider = dividerItem.button?.window?.frame,
              let chevron = chevronItem.button?.window?.frame else { return true }
        return divider.maxX <= chevron.minX + 1
    }

    private func isOnScreen(_ item: NSStatusItem) -> Bool {
        guard let window = item.button?.window, window.isVisible else { return false }
        return NSScreen.screens.contains { $0.frame.intersects(window.frame) }
    }

    /// Detects when macOS had no room for our items (crowded bar) and tells the user.
    private func checkVisibility() {
        guard chevronItem.isVisible, !isOnScreen(chevronItem) else { return }
        if isCollapsed { expand() } // Never leave the user without a way back.
        guard !isOnScreen(chevronItem), !isOnScreen(dividerItem), !didWarnNoSpace else { return }
        didWarnNoSpace = true
        notifyNoSpace()
    }

    private func notifyNoSpace() {
        let title = "MenuBarCollapse is hidden"
        let body = "The menu bar is too crowded to show the MenuBarCollapse icons. Quit or remove a few other menu bar apps."
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, _ in
            DispatchQueue.main.async {
                guard granted else {
                    let alert = NSAlert()
                    alert.messageText = title
                    alert.informativeText = body
                    NSApp.activate(ignoringOtherApps: true)
                    alert.runModal()
                    return
                }
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "no-space", content: content, trigger: nil))
            }
        }
    }

    // MARK: - Menu

    private func showMenu() {
        let item = chevronItem.isVisible ? chevronItem : dividerItem
        item.menu = buildMenu()
        item.button?.performClick(nil)
        item.menu = nil
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        if !isOrderedCorrectly {
            let warning = NSMenuItem(title: "⚠️ Move the divider to the left of the chevron", action: nil, keyEquivalent: "")
            warning.isEnabled = false
            menu.addItem(warning)
            menu.addItem(.separator())
        }
        menu.addItem(makeItem(isCollapsed ? "Show Hidden Icons" : "Hide Icons", #selector(menuToggle)))
        menu.addItem(.separator())

        let help = NSMenuItem(title: "How to Hide Icons", action: nil, keyEquivalent: "")
        let helpMenu = NSMenu()
        for line in ["Hold ⌘ and drag icons left of the divider.",
                     "Icons left of the divider hide on collapse.",
                     "Icons right of the chevron always stay visible."] {
            let entry = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            entry.isEnabled = false
            helpMenu.addItem(entry)
        }
        helpMenu.addItem(.separator())
        helpMenu.addItem(makeItem("Show Welcome Guide…", #selector(menuWelcome)))
        help.submenu = helpMenu
        menu.addItem(help)

        // Honest scope: listing items requires Screen Recording / private APIs, which we avoid.
        let notch = NSMenuItem(title: "Items Behind the Notch", action: nil, keyEquivalent: "")
        let notchMenu = NSMenu()
        for line in ["Nothing to list — MenuBarCollapse can't see other apps' icons.",
                     "On notch displays, keep fewer icons right of the divider."] {
            let entry = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            entry.isEnabled = false
            notchMenu.addItem(entry)
        }
        notch.submenu = notchMenu
        menu.addItem(notch)

        menu.addItem(makeItem("Settings…", #selector(menuSettings), key: ","))
        menu.addItem(makeItem("Support / Donate ❤️", #selector(menuDonate)))
        menu.addItem(.separator())
        menu.addItem(makeItem("Quit MenuBarCollapse", #selector(menuQuit), key: "q"))
        return menu
    }

    private func makeItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func menuToggle() { toggle() }
    @objc private func menuSettings() { onOpenSettings?() }
    @objc private func menuWelcome() { onOpenWelcome?() }
    @objc private func menuQuit() { NSApp.terminate(nil) }
    @objc private func menuDonate() {
        NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
    }
}
