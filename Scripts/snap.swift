#!/usr/bin/env swift
// snap.swift — screenshot helper for AppFactory (uses only CoreGraphics/AppKit/ApplicationServices).
//
//   swift snap.swift perms                         -> {"screen_recording":bool,"accessibility":bool}
//   swift snap.swift windows <AppName>             -> JSON list of on-screen windows owned by the app (id,title,bounds,layer)
//   swift snap.swift status-item <AppName>         -> JSON frame of the app's menu-bar status item (via Accessibility)
//   swift snap.swift click-status-item <AppName>   -> presses the app's menu-bar status item (via Accessibility)
//   swift snap.swift menu-items <AppName>          -> opens the status-item menu and lists its item titles
//   swift snap.swift click-menu-item <AppName> <text> -> opens the menu and presses the item whose title contains <text>
//   swift snap.swift capture-window <windowID> <out.png> [--shadow]
//   swift snap.swift capture-rect <x> <y> <w> <h> <out.png>
//   swift snap.swift capture-app <AppName> <out.png>   -> composite of all the app's windows (incl. menus/popovers)
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

let args = CommandLine.arguments
func fail(_ msg: String) -> Never { FileHandle.standardError.write((msg + "\n").data(using: .utf8)!); exit(1) }
func json(_ obj: Any) { print(String(data: try! JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]), encoding: .utf8)!) }
guard args.count >= 2 else { fail("usage: snap.swift <perms|windows|status-item|click-status-item|capture-window|capture-rect|capture-app> …") }

func apps(named name: String) -> [NSRunningApplication] {
    NSWorkspace.shared.runningApplications.filter {
        ($0.localizedName ?? "").caseInsensitiveCompare(name) == .orderedSame ||
        ($0.bundleURL?.lastPathComponent ?? "").caseInsensitiveCompare(name + ".app") == .orderedSame
    }
}

func windowList(for name: String) -> [[String: Any]] {
    let pids = Set(apps(named: name).map { $0.processIdentifier })
    guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return [] }
    return info.compactMap { w in
        guard let pid = w[kCGWindowOwnerPID as String] as? Int32, pids.contains(pid) else { return nil }
        guard let b = w[kCGWindowBounds as String] as? [String: Any] else { return nil }
        let width = (b["Width"] as? Double) ?? 0, height = (b["Height"] as? Double) ?? 0
        if width < 8 || height < 8 { return nil }
        return ["id": w[kCGWindowNumber as String] as? Int ?? 0,
                "title": w[kCGWindowName as String] as? String ?? "",
                "layer": w[kCGWindowLayer as String] as? Int ?? 0,
                "x": b["X"] as? Double ?? 0, "y": b["Y"] as? Double ?? 0, "w": width, "h": height]
    }
}

@discardableResult
func screencapture(_ extra: [String], out: String) -> Bool {
    // `screencapture` is the supported capture path on macOS 15+ (CGWindowListCreateImage is obsolete).
    let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    task.arguments = ["-x", "-o", "-t", "png"] + extra + [out]
    do { try task.run() } catch { fail("could not run screencapture: \(error)") }
    task.waitUntilExit()
    let ok = task.terminationStatus == 0 && FileManager.default.fileExists(atPath: out)
    if ok, let img = NSImage(contentsOfFile: out) { print("saved \(out) (\(Int(img.size.width))x\(Int(img.size.height)) pt)") }
    else { fail("capture failed (is Screen Recording granted to the terminal app running this?)") }
    return ok
}

func statusItemElement(for name: String) -> AXUIElement? {
    guard let app = apps(named: name).first else { return nil }
    let appEl = AXUIElementCreateApplication(app.processIdentifier)
    var extras: AnyObject?
    guard AXUIElementCopyAttributeValue(appEl, "AXExtrasMenuBar" as CFString, &extras) == .success, let bar = extras else { return nil }
    var children: AnyObject?
    guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &children) == .success,
          let items = children as? [AXUIElement], let first = items.first else { return nil }
    return first
}

func frame(of el: AXUIElement) -> CGRect? {
    var posV: AnyObject?, sizeV: AnyObject?
    guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posV) == .success,
          AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeV) == .success else { return nil }
    var p = CGPoint.zero, s = CGSize.zero
    AXValueGetValue(posV as! AXValue, .cgPoint, &p); AXValueGetValue(sizeV as! AXValue, .cgSize, &s)
    return CGRect(origin: p, size: s)
}

switch args[1] {
case "perms":
    json(["screen_recording": CGPreflightScreenCaptureAccess(), "accessibility": AXIsProcessTrusted()])
case "windows":
    guard args.count >= 3 else { fail("windows <AppName>") }
    json(windowList(for: args[2]))
case "status-item":
    guard args.count >= 3, let el = statusItemElement(for: args[2]), let f = frame(of: el) else { fail("status item not found (is Accessibility granted? is the app running?)") }
    json(["x": f.origin.x, "y": f.origin.y, "w": f.width, "h": f.height])
case "click-status-item":
    guard args.count >= 3, let el = statusItemElement(for: args[2]) else { fail("status item not found (is Accessibility granted? is the app running?)") }
    let r = AXUIElementPerformAction(el, kAXPressAction as CFString)
    print(r == .success ? "pressed" : "press failed: \(r.rawValue)")
case "click-menu-item":
    // Opens the status-item menu (if needed) and presses the first menu item whose title contains <text>.
    guard args.count >= 4, let item = statusItemElement(for: args[2]) else { fail("click-menu-item <AppName> <title-substring>") }
    let needle = args[3].lowercased()
    func findMenu(_ el: AXUIElement, depth: Int = 0) -> AXUIElement? {
        var kids: AnyObject?
        guard depth < 4, AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &kids) == .success,
              let children = kids as? [AXUIElement] else { return nil }
        for c in children {
            var role: AnyObject?
            AXUIElementCopyAttributeValue(c, kAXRoleAttribute as CFString, &role)
            if (role as? String) == "AXMenu" { return c }
            if let m = findMenu(c, depth: depth + 1) { return m }
        }
        return nil
    }
    if findMenu(item) == nil {  // menu closed -> open it (AXPress returns an error while the menu is open; ignore)
        DispatchQueue.global().async { AXUIElementPerformAction(item, kAXPressAction as CFString) }
        Thread.sleep(forTimeInterval: 1.0)
    }
    guard let menu = findMenu(item) else { fail("menu did not open") }
    var kids: AnyObject?
    AXUIElementCopyAttributeValue(menu, kAXChildrenAttribute as CFString, &kids)
    for c in (kids as? [AXUIElement]) ?? [] {
        var t: AnyObject?
        AXUIElementCopyAttributeValue(c, kAXTitleAttribute as CFString, &t)
        if let title = t as? String, title.lowercased().contains(needle) {
            let r = AXUIElementPerformAction(c, kAXPressAction as CFString)
            print(r == .success ? "pressed \"\(title)\"" : "press failed on \"\(title)\": \(r.rawValue)")
            exit(r == .success ? 0 : 1)
        }
    }
    fail("no menu item containing \"\(args[3])\"")
case "menu-items":
    guard args.count >= 3, let item = statusItemElement(for: args[2]) else { fail("menu-items <AppName>") }
    DispatchQueue.global().async { AXUIElementPerformAction(item, kAXPressAction as CFString) }
    Thread.sleep(forTimeInterval: 1.0)
    var titles: [String] = []
    func walk(_ el: AXUIElement, depth: Int) {
        var kids: AnyObject?
        guard depth < 5, AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &kids) == .success,
              let children = kids as? [AXUIElement] else { return }
        for c in children {
            var t: AnyObject?; AXUIElementCopyAttributeValue(c, kAXTitleAttribute as CFString, &t)
            if let title = t as? String, !title.isEmpty { titles.append(title) }
            walk(c, depth: depth + 1)
        }
    }
    walk(item, depth: 0)
    json(titles)
case "capture-window":
    guard args.count >= 4, let wid = UInt32(args[2]) else { fail("capture-window <windowID> <out.png> [--shadow]") }
    screencapture(["-l", String(wid)] + (args.contains("--shadow") ? [] : []), out: args[3])
case "capture-rect":
    guard args.count >= 7, let x = Double(args[2]), let y = Double(args[3]), let w = Double(args[4]), let h = Double(args[5]) else { fail("capture-rect x y w h out.png") }
    screencapture(["-R", "\(Int(x)),\(Int(y)),\(Int(w)),\(Int(h))"], out: args[6])
case "capture-app":
    // One PNG per on-screen window of the app (menus, popovers, panels, settings), captured by window ID so it
    // works on any display (screencapture -R cannot address secondary displays with negative coordinates).
    // Output: <out>.png for the largest window, <out>-2.png, <out>-3.png … for the rest.
    guard args.count >= 4 else { fail("capture-app <AppName> <out.png>") }
    let wins = windowList(for: args[2]).sorted { ($0["w"] as! Double) * ($0["h"] as! Double) > ($1["w"] as! Double) * ($1["h"] as! Double) }
    guard !wins.isEmpty else { fail("no on-screen windows for \(args[2])") }
    let base = args[3].hasSuffix(".png") ? String(args[3].dropLast(4)) : args[3]
    for (i, w) in wins.enumerated() {
        let out = i == 0 ? base + ".png" : base + "-\(i + 1).png"
        screencapture(["-l", String(w["id"] as! Int)], out: out)
    }
default:
    fail("unknown command \(args[1])")
}
