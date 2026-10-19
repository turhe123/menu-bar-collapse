#!/usr/bin/env swift
// make_icon.swift — programmatic macOS squircle AppIcon generator (no external assets).
//
// Usage:
//   swift Scripts/make_icon.swift <appiconset-dir> <AppName> <sf-symbol-name> <hexColorTop> <hexColorBottom>
// Example:
//   swift Scripts/make_icon.swift Sources/Assets.xcassets/AppIcon.appiconset NotchDock "tray.full.fill" 5B8DEF 2D3A8C
//
// Produces the full macOS icon set (16..1024 px) + Contents.json using only AppKit/CoreGraphics.
// If the SF Symbol is unavailable, the first letter of the app name is used as the glyph.

import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: make_icon.swift <appiconset-dir> <AppName> [symbol] [hexTop] [hexBottom]\n".data(using: .utf8)!)
    exit(2)
}
let outDir = URL(fileURLWithPath: args[1])
let appName = args[2]
let symbolName = args.count > 3 ? args[3] : "sparkles"
let hexTop = args.count > 4 ? args[4] : "5B8DEF"
let hexBottom = args.count > 5 ? args[5] : "2D3A8C"

func color(_ hex: String) -> NSColor {
    var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if h.hasPrefix("#") { h.removeFirst() }
    guard h.count == 6, let v = UInt32(h, radix: 16) else { return NSColor.systemBlue }
    return NSColor(calibratedRed: CGFloat((v >> 16) & 0xFF) / 255.0,
                   green: CGFloat((v >> 8) & 0xFF) / 255.0,
                   blue: CGFloat(v & 0xFF) / 255.0, alpha: 1)
}

/// Apple-style squircle (superellipse) path.
func squirclePath(in rect: NSRect, exponent n: CGFloat = 4.6) -> NSBezierPath {
    let path = NSBezierPath()
    let cx = rect.midX, cy = rect.midY
    let a = rect.width / 2, b = rect.height / 2
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = cx + a * (ct < 0 ? -1 : 1) * pow(abs(ct), 2 / n)
        let y = cy + b * (st < 0 ? -1 : 1) * pow(abs(st), 2 / n)
        if i == 0 { path.move(to: NSPoint(x: x, y: y)) } else { path.line(to: NSPoint(x: x, y: y)) }
    }
    path.close()
    return path
}

func renderMaster(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    // macOS icon grid: the squircle occupies ~80% of the canvas, centered.
    let inset = size * 0.10
    let body = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)

    // Soft drop shadow
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = size * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
    shadow.set()
    NSColor.black.setFill()
    squirclePath(in: body).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Gradient body
    let body_path = squirclePath(in: body)
    let gradient = NSGradient(starting: color(hexTop), ending: color(hexBottom))!
    gradient.draw(in: body_path, angle: -90)

    // Subtle top highlight
    NSGraphicsContext.saveGraphicsState()
    body_path.addClip()
    let hl = NSGradient(starting: NSColor.white.withAlphaComponent(0.22), ending: NSColor.white.withAlphaComponent(0.0))!
    hl.draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: 90)
    NSGraphicsContext.restoreGraphicsState()

    // Glyph
    let glyphBox = body.insetBy(dx: body.width * 0.24, dy: body.height * 0.24)
    NSGraphicsContext.saveGraphicsState()
    let gShadow = NSShadow()
    gShadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    gShadow.shadowBlurRadius = size * 0.012
    gShadow.shadowOffset = NSSize(width: 0, height: -size * 0.006)
    gShadow.set()

    var drewSymbol = false
    if let sym = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
        let cfg = NSImage.SymbolConfiguration(pointSize: glyphBox.height * 0.8, weight: .medium)
        if let configured = sym.withSymbolConfiguration(cfg) {
            let tinted = NSImage(size: configured.size, flipped: false) { rect in
                configured.draw(in: rect)
                NSColor.white.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            // Fit into glyphBox preserving aspect ratio
            let s = min(glyphBox.width / tinted.size.width, glyphBox.height / tinted.size.height)
            let w = tinted.size.width * s, h = tinted.size.height * s
            let r = NSRect(x: glyphBox.midX - w / 2, y: glyphBox.midY - h / 2, width: w, height: h)
            tinted.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1.0)
            drewSymbol = true
        }
    }
    if !drewSymbol {
        let letter = String(appName.prefix(1)).uppercased()
        let font = NSFont.systemFont(ofSize: glyphBox.height * 0.95, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let str = NSAttributedString(string: letter, attributes: attrs)
        let sz = str.size()
        str.draw(at: NSPoint(x: glyphBox.midX - sz.width / 2, y: glyphBox.midY - sz.height / 2))
    }
    NSGraphicsContext.restoreGraphicsState()
    image.unlockFocus()
    return image
}

func pngData(_ image: NSImage, pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let master = renderMaster(size: 1024)

let entries: [(Int, Int)] = [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)]
var images: [[String: String]] = []
for (pt, scale) in entries {
    let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
    try pngData(master, pixels: pt * scale).write(to: outDir.appendingPathComponent(name))
    images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(pt)x\(pt)"])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outDir.appendingPathComponent("Contents.json"))
print("AppIcon written to \(outDir.path) (\(images.count) images)")
