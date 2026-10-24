#!/usr/bin/env swift
// Masks full-bleed square artwork into the macOS icon squircle (824pt body on
// a 1024pt canvas, with the standard drop shadow) and writes every size the
// asset catalog needs.
//
//   swift Scripts/mask-icon.swift artwork.png App/CodeFactory/Resources/Assets.xcassets/AppIcon.appiconset
import AppKit

let args = CommandLine.arguments
guard args.count >= 3, let art = NSImage(contentsOfFile: args[1]) else {
    print("usage: mask-icon.swift <artwork.png> <out-dir>")
    exit(1)
}
let outDir = URL(fileURLWithPath: args[2])

func bitmap(_ px: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
}

let master = bitmap(1024)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: master)
NSGraphicsContext.current?.imageInterpolation = .high
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
NSColor.black.setFill()
squircle.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
squircle.addClip()
art.draw(in: body, from: .zero, operation: .sourceOver, fraction: 1)
// Glass rim.
NSColor.white.withAlphaComponent(0.18).setStroke()
let rim = NSBezierPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), xRadius: 184, yRadius: 184)
rim.lineWidth = 3
rim.stroke()
NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.restoreGraphicsState()

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let sizes: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var entries: [String] = []
for (points, scale) in sizes {
    let px = points * scale
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    let rep = bitmap(px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    master.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(name))
    entries.append("    { \"filename\": \"\(name)\", \"idiom\": \"mac\", \"scale\": \"\(scale)x\", \"size\": \"\(points)x\(points)\" }")
}
let json = "{\n  \"images\": [\n" + entries.joined(separator: ",\n") + "\n  ],\n  \"info\": { \"author\": \"xcode\", \"version\": 1 }\n}\n"
try json.write(to: outDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("Wrote \(sizes.count) icons to \(outDir.path)")
