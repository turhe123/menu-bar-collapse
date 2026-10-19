# MenuBarCollapse — specification

**Tagline:** A tiny divider that hides crowded menu bar icons behind a single click and re-hides them automatically.

**Category:** Menu Bar Utility

**Inspired by (paid):** Bartender ($16 one-time)

**Frameworks:** SwiftUI, AppKit, ServiceManagement

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

(1) What the paid app does. Bartender is the best-known menu bar organizer and has long sold at around 16 dollars one-time, with a trial. Its page advertises hiding items, triggers, profiles and notch handling. A crowded menu bar and the notch on newer MacBooks make this one of the most commonly recommended utilities in paid-app lists, and free alternatives are less polished. Our clean-room version intentionally avoids private APIs and Screen Recording and uses the classic divider technique.

(2) Feature set. The app adds two status items. One is a small toggle chevron and the other is an expandable divider whose length changes. The user Command-drags icons to the left of the divider to make them hideable. Clicking the chevron collapses the divider to a very large length, pushing every icon on its left off the visible bar, and clicking again expands it back. An optional auto-hide timer collapses the bar again after a configurable number of seconds. A global hotkey toggles the state. Option-clicking the chevron opens a quick menu.

(3) UI spec. The chevron status item shows a left-pointing symbol when expanded and a right-pointing symbol when collapsed. Right-click or Option-click opens a menu with Toggle, Settings, a short help item explaining how to Command-drag icons, and Quit. Settings fields: auto-hide delay stepper with an off value, hotkey recorder, show divider as thin line or dot picker, expand on hover toggle, hide chevron when expanded toggle, and launch at login toggle. First launch shows a tiny welcome window with a three-line instruction and an image-free diagram drawn with SwiftUI shapes. Empty state: if the divider is positioned to the right of the chevron, a warning in the menu says Move the divider to the left of the chevron.

(4) Technical approach. Use NSStatusBar system status bar to create status items with variable length and set a unique autosaveName on each so macOS preserves the user's ordering. Collapse by setting the divider's length to 10000 and expand by setting it to the normal length of a few points. Detect misordering by comparing the frames of the two status item button windows in screen coordinates. Hover expansion uses a tracking approach on the chevron button via an NSTrackingArea. Global hotkey uses Carbon RegisterEventHotKey. Auto-hide uses a one-shot Timer reset on every expansion. Persist options in AppStorage. Launch at login through SMAppService. No permissions are required, which makes it simple to install, and the app runs as an accessory with no Dock icon. The MenuBarExtra scene is not used because explicit control of status item length requires NSStatusItem objects owned by an app delegate adaptor.

(5) Edge cases. On notch displays the hidden items may spill under the notch even when expanded, so document this and offer an expand-to-menu option listing nothing, keeping scope honest. If the user quits with the bar collapsed, expansion must be restored so icons reappear, handled in the termination notification. Prevent the divider from being the leftmost item by showing the warning. Handle display changes by recalculating state. If the system hides both items due to lack of space, show a notification suggesting removing other icons.
