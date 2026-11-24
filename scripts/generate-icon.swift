#!/usr/bin/env swift
import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift scripts/generate-icon.swift <output.iconset>")
}
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(size: Int) throws -> Data {
    let pixels = CGFloat(size)
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot create icon bitmap") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: pixels / 1024, y: pixels / 1024)
    let frame = NSRect(x: 84, y: 84, width: 856, height: 856)
    let shape = NSBezierPath(roundedRect: frame, xRadius: 194, yRadius: 194)
    NSShadow().set()
    NSGradient(colors: [
        NSColor(calibratedRed: 0.08, green: 0.18, blue: 0.27, alpha: 1),
        NSColor(calibratedRed: 0.07, green: 0.46, blue: 0.49, alpha: 1)
    ])!.draw(in: shape, angle: -50)
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    let glow = NSBezierPath(ovalIn: NSRect(x: 380, y: 580, width: 650, height: 500))
    NSGradient(starting: NSColor.white.withAlphaComponent(0.22), ending: NSColor.white.withAlphaComponent(0))!
        .draw(in: glow, angle: -90)
    for (index, width) in [470.0, 350.0, 235.0].enumerated() {
        let y = CGFloat(625 - index * 156)
        let track = NSBezierPath(roundedRect: NSRect(x: 238, y: y, width: 548, height: 73), xRadius: 36, yRadius: 36)
        NSColor.white.withAlphaComponent(0.13).setFill()
        track.fill()
        let bar = NSBezierPath(roundedRect: NSRect(x: 238, y: y, width: width, height: 73), xRadius: 36, yRadius: 36)
        NSGradient(starting: NSColor(calibratedRed: 0.46, green: 0.98, blue: 0.85, alpha: 1),
                   ending: NSColor(calibratedRed: 0.8, green: 1, blue: 0.96, alpha: 1))!.draw(in: bar, angle: 0)
    }
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.33).setStroke()
    shape.lineWidth = 3
    shape.stroke()
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode icon") }
    return data
}

for size in [16, 32, 128, 256, 512] {
    try render(size: size).write(to: output.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size: size * 2).write(to: output.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
