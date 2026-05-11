#!/usr/bin/env swift
// Renders the BatteryScope app icon to a 1024×1024 PNG.
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

// MARK: - Battery body (automotive / marine style — two top posts, no side nub)

let batteryRect = CGRect(x: 162, y: 300, width: 700, height: 440)
let batteryPath = CGPath(roundedRect: batteryRect, cornerWidth: 40, cornerHeight: 40, transform: nil)

// Posts: stubby rounded rectangles sitting on top of the battery body.
let postWidth: CGFloat = 90
let postHeight: CGFloat = 58
let postLeftX  = batteryRect.minX + batteryRect.width * 0.20 - postWidth / 2
let postRightX = batteryRect.minX + batteryRect.width * 0.80 - postWidth / 2
let postY = batteryRect.minY - postHeight + 14  // tuck 14pt under the body so the stroke joins cleanly

let leftPost  = CGPath(roundedRect: CGRect(x: postLeftX,  y: postY, width: postWidth, height: postHeight),
                       cornerWidth: 10, cornerHeight: 10, transform: nil)
let rightPost = CGPath(roundedRect: CGRect(x: postRightX, y: postY, width: postWidth, height: postHeight),
                       cornerWidth: 10, cornerHeight: 10, transform: nil)

// Fill posts first so the body stroke overlaps and tucks the bottom seam.
cg.setFillColor(batteryStroke)
cg.addPath(leftPost)
cg.fillPath()
cg.addPath(rightPost)
cg.fillPath()

// Body stroke
cg.setLineWidth(22)
cg.setStrokeColor(batteryStroke)
cg.setLineJoin(.round)
cg.addPath(batteryPath)
cg.strokePath()

// Inner fill
let innerRect = batteryRect.insetBy(dx: 11, dy: 11)
let innerPath = CGPath(roundedRect: innerRect, cornerWidth: 30, cornerHeight: 30, transform: nil)
cg.setFillColor(batteryInner)
cg.addPath(innerPath)
cg.fillPath()

// MARK: - Polarity markings inside the battery, under each post

cg.saveGState()
cg.setStrokeColor(batteryStroke.copy(alpha: 0.55)!)
cg.setLineWidth(10)
cg.setLineCap(.round)

let markY: CGFloat = innerRect.minY + 50
let plusCenterX  = postRightX + postWidth / 2
let minusCenterX = postLeftX  + postWidth / 2
let markHalf: CGFloat = 18

// Minus on the left
let minusPath = CGMutablePath()
minusPath.move(to:    CGPoint(x: minusCenterX - markHalf, y: markY))
minusPath.addLine(to: CGPoint(x: minusCenterX + markHalf, y: markY))
cg.addPath(minusPath)
cg.strokePath()

// Plus on the right
let plusPath = CGMutablePath()
plusPath.move(to:    CGPoint(x: plusCenterX - markHalf, y: markY))
plusPath.addLine(to: CGPoint(x: plusCenterX + markHalf, y: markY))
plusPath.move(to:    CGPoint(x: plusCenterX, y: markY - markHalf))
plusPath.addLine(to: CGPoint(x: plusCenterX, y: markY + markHalf))
cg.addPath(plusPath)
cg.strokePath()
cg.restoreGState()

// MARK: - Heartbeat / ECG wave

// Drawn twice: a thick soft "glow" underneath and a thinner crisp line on top.
let baseY: CGFloat = batteryRect.minY + 250    // ECG baseline (below the polarity marks, centered in lower body)
let startX = innerRect.minX + 32
let endX   = innerRect.maxX - 32

let wave = CGMutablePath()
wave.move(to: CGPoint(x: startX, y: baseY))
wave.addLine(to: CGPoint(x: 280, y: baseY))
wave.addLine(to: CGPoint(x: 320, y: baseY + 18))   // tiny dip (Q)
wave.addLine(to: CGPoint(x: 360, y: baseY - 120))  // R spike up
wave.addLine(to: CGPoint(x: 400, y: baseY + 90))   // S dip down
wave.addLine(to: CGPoint(x: 450, y: baseY))
wave.addLine(to: CGPoint(x: 510, y: baseY - 60))   // T wave
wave.addLine(to: CGPoint(x: 580, y: baseY))
wave.addLine(to: CGPoint(x: 660, y: baseY))
wave.addLine(to: CGPoint(x: 700, y: baseY - 40))
wave.addLine(to: CGPoint(x: 740, y: baseY))
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
