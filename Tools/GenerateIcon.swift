#!/usr/bin/env swift
// Renders the BMS Manager app icon to a 1024×1024 PNG.
//
// Usage:
//   swift Tools/GenerateIcon.swift Sources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
//
// Design: flat-style battery silhouette on a deep teal gradient, with a
// glowing green heartbeat trace running through the battery interior and a
// Bluetooth glyph tucked into the upper-left of the battery.

import Foundation
import AppKit
import CoreGraphics

// MARK: - Args

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("Usage: GenerateIcon.swift <output.png>\n".utf8))
    exit(1)
}
let outputPath = CommandLine.arguments[1]
let outputURL = URL(fileURLWithPath: outputPath)

// Make sure the parent dir exists.
try? FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

// MARK: - Canvas

let side: CGFloat = 1024
let size = CGSize(width: side, height: side)

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(side),
    pixelsHigh: Int(side),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 4 * Int(side),
    bitsPerPixel: 32
) else {
    fatalError("Failed to allocate bitmap")
}

guard let nsCtx = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Failed to create NSGraphicsContext")
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = nsCtx
let cg = nsCtx.cgContext

// Flip to top-left origin so we can think in iOS coordinates.
cg.translateBy(x: 0, y: side)
cg.scaleBy(x: 1, y: -1)

// MARK: - Palette

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

let bgTop      = rgb(0.04, 0.18, 0.24)      // deep teal
let bgBottom   = rgb(0.06, 0.30, 0.28)      // forest dark
let batteryStroke   = rgb(0.91, 0.96, 0.95) // off-white
let batteryInner    = rgb(0.03, 0.13, 0.17) // near-black teal
let waveGlow        = rgb(0.24, 0.91, 0.46) // bright green
let waveCore        = rgb(0.45, 1.00, 0.65) // brighter highlight

// MARK: - Background gradient

let colorSpace = CGColorSpaceCreateDeviceRGB()
let bg = CGGradient(
    colorsSpace: colorSpace,
    colors: [bgTop, bgBottom] as CFArray,
    locations: [0, 1]
)!
cg.drawLinearGradient(
    bg,
    start: CGPoint(x: 0, y: 0),
    end: CGPoint(x: side, y: side),
    options: []
)

// MARK: - Battery body

let batteryRect = CGRect(x: 142, y: 312, width: 680, height: 400)
let batteryPath = CGPath(roundedRect: batteryRect, cornerWidth: 56, cornerHeight: 56, transform: nil)

// Stroke
cg.setLineWidth(22)
cg.setStrokeColor(batteryStroke)
cg.setLineJoin(.round)
cg.addPath(batteryPath)
cg.strokePath()

// Inner fill (slightly inset, so the stroke shows on the outside)
let innerRect = batteryRect.insetBy(dx: 11, dy: 11)
let innerPath = CGPath(roundedRect: innerRect, cornerWidth: 46, cornerHeight: 46, transform: nil)
cg.setFillColor(batteryInner)
cg.addPath(innerPath)
cg.fillPath()

// Terminal nub (right side)
let terminalRect = CGRect(x: 822, y: 462, width: 56, height: 100)
let terminalPath = CGPath(roundedRect: terminalRect, cornerWidth: 16, cornerHeight: 16, transform: nil)
cg.setFillColor(batteryStroke)
cg.addPath(terminalPath)
cg.fillPath()

// MARK: - Heartbeat / ECG wave

// Drawn twice: a thick soft "glow" underneath and a thinner crisp line on top.
let baseY: CGFloat = 528    // ECG baseline (centered vertically in battery)
let startX = innerRect.minX + 32
let endX   = innerRect.maxX - 32

let wave = CGMutablePath()
wave.move(to: CGPoint(x: startX, y: baseY))
wave.addLine(to: CGPoint(x: 260, y: baseY))
wave.addLine(to: CGPoint(x: 300, y: baseY + 18))   // tiny dip (Q)
wave.addLine(to: CGPoint(x: 340, y: baseY - 120))  // R spike up
wave.addLine(to: CGPoint(x: 380, y: baseY + 90))   // S dip down
wave.addLine(to: CGPoint(x: 430, y: baseY))
wave.addLine(to: CGPoint(x: 490, y: baseY - 60))   // T wave (rounded peak, but linearized)
wave.addLine(to: CGPoint(x: 560, y: baseY))
wave.addLine(to: CGPoint(x: 640, y: baseY))
wave.addLine(to: CGPoint(x: 680, y: baseY - 40))
wave.addLine(to: CGPoint(x: 720, y: baseY))
wave.addLine(to: CGPoint(x: endX, y: baseY))

// Soft outer stroke (glow)
cg.saveGState()
cg.setLineCap(.round)
cg.setLineJoin(.round)
cg.setStrokeColor(waveGlow.copy(alpha: 0.55)!)
cg.setLineWidth(38)
cg.setShadow(offset: .zero, blur: 28, color: waveGlow.copy(alpha: 0.9))
cg.addPath(wave)
cg.strokePath()
cg.restoreGState()

// Crisp inner stroke
cg.saveGState()
cg.setLineCap(.round)
cg.setLineJoin(.round)
cg.setStrokeColor(waveCore)
cg.setLineWidth(20)
cg.addPath(wave)
cg.strokePath()
cg.restoreGState()

// MARK: - Save

NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Failed to encode PNG")
}
do {
    try pngData.write(to: outputURL)
} catch {
    FileHandle.standardError.write(Data("Write failed: \(error)\n".utf8))
    exit(1)
}
print("Wrote \(outputURL.path) (\(pngData.count / 1024) KB)")
