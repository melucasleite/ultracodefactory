#!/usr/bin/env swift
// Draws the Code Factory app icon from code (no third-party artwork) and
// writes every size the asset catalog needs.
//
//   swift Scripts/make-icon.swift App/CodeFactory/Resources/Assets.xcassets/AppIcon.appiconset
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
let canvas: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func gearPath(center: CGPoint, outer: CGFloat, inner: CGFloat, teeth: Int) -> NSBezierPath {
    let path = NSBezierPath()
    let step = .pi * 2 / CGFloat(teeth)
    for i in 0..<teeth {
        let a = CGFloat(i) * step
        let pts: [(CGFloat, CGFloat)] = [
            (inner, a - step * 0.30), (outer, a - step * 0.17), (outer, a + step * 0.17), (inner, a + step * 0.30),
        ]
        for (j, (r, ang)) in pts.enumerated() {
            let p = CGPoint(x: center.x + cos(ang) * r, y: center.y + sin(ang) * r)
            if i == 0 && j == 0 { path.move(to: p) } else { path.line(to: p) }
        }
        let next = a + step - step * 0.30
        let mid = (a + step * 0.30 + next) / 2
        path.line(to: CGPoint(x: center.x + cos(mid) * inner, y: center.y + sin(mid) * inner))
    }
    path.close()
    return path
}

func render() -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Squircle body on Apple's 824pt icon grid.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, 0.45)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    color(0x1C1F24).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [color(0x2E333B), color(0x14161A)])!.draw(in: body, angle: -90)

    // Blueprint grid.
    color(0xFFFFFF, 0.045).setStroke()
    let grid = NSBezierPath()
    grid.lineWidth = 3
    var g: CGFloat = body.minX
    while g < body.maxX { grid.move(to: CGPoint(x: g, y: body.minY)); grid.line(to: CGPoint(x: g, y: body.maxY)); g += 64 }
    g = body.minY
    while g < body.maxY { grid.move(to: CGPoint(x: body.minX, y: g)); grid.line(to: CGPoint(x: body.maxX, y: g)); g += 64 }
    grid.stroke()

    // Hazard band along the bottom.
    let band = NSRect(x: body.minX, y: body.minY, width: body.width, height: 120)
    color(0xFFC400).setFill()
    band.fill()
    color(0x15171B).setFill()
    var x = band.minX - band.height
    while x < band.maxX {
        let stripe = NSBezierPath()
        stripe.move(to: CGPoint(x: x, y: band.minY))
        stripe.line(to: CGPoint(x: x + 48, y: band.minY))
        stripe.line(to: CGPoint(x: x + 48 + band.height, y: band.maxY))
        stripe.line(to: CGPoint(x: x + band.height, y: band.maxY))
        stripe.close()
        stripe.fill()
        x += 96
    }
    color(0x000000, 0.35).setFill()
    NSRect(x: band.minX, y: band.maxY - 6, width: band.width, height: 6).fill()
    NSGraphicsContext.restoreGraphicsState()

    // The gear, glowing safety orange.
    let center = CGPoint(x: 512, y: 560)
    let gear = gearPath(center: center, outer: 300, inner: 238, teeth: 10)
    let hole = NSBezierPath(ovalIn: NSRect(x: center.x - 150, y: center.y - 150, width: 300, height: 300))
    gear.append(hole.reversed)

    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = color(0xFF8500, 0.55)
    glow.shadowBlurRadius = 60
    glow.set()
    color(0xFF8500).setFill()
    gear.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    gear.addClip()
    NSGradient(colors: [color(0xFFB13B), color(0xFF7A00), color(0xE25E00)])!
        .draw(in: NSRect(x: center.x - 300, y: center.y - 300, width: 600, height: 600), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // A terminal prompt in the hub: the factory builds code.
    let prompt = NSBezierPath()
    prompt.lineWidth = 34
    prompt.lineCapStyle = .round
    prompt.lineJoinStyle = .round
    prompt.move(to: CGPoint(x: center.x - 82, y: center.y + 62))
    prompt.line(to: CGPoint(x: center.x - 12, y: center.y))
    prompt.line(to: CGPoint(x: center.x - 82, y: center.y - 62))
    prompt.move(to: CGPoint(x: center.x + 22, y: center.y - 66))
    prompt.line(to: CGPoint(x: center.x + 92, y: center.y - 66))
    color(0xF4F5F7).setStroke()
    prompt.stroke()

    // Rim highlight.
    color(0xFFFFFF, 0.10).setStroke()
    let rim = NSBezierPath(roundedRect: body.insetBy(dx: 2, dy: 2), xRadius: 183, yRadius: 183)
    rim.lineWidth = 4
    rim.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let master = render()
let sizes: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [String] = []
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
for (points, scale) in sizes {
    let pixels = points * scale
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.addRepresentation(master)
    let resized = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: resized)
    NSGraphicsContext.current?.imageInterpolation = .high
    master.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    try resized.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(name))
    images.append("""
        { "filename" : "\(name)", "idiom" : "mac", "scale" : "\(scale)x", "size" : "\(points)x\(points)" }
    """)
}
let contents = "{\n  \"images\" : [\n" + images.joined(separator: ",\n") + "\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
try contents.write(to: outDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("Wrote \(sizes.count) icons to \(outDir.path)")
