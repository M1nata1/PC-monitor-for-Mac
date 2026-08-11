#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

// Draws the app icon (a gauge ring over a saturated squircle) and packs it into an .icns.
// Run: swift Scripts/GenerateIcon.swift Resources/AppIcon.icns

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources/AppIcon.icns"

// MARK: - Palette

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha)
}

let backgroundTop = rgb(0x3B82F6)      // bright blue
let backgroundBottom = rgb(0x7C3AED)   // violet
let gaugeStops: [(CGFloat, CGColor)] = [
    (0.00, rgb(0x34D399)),   // green
    (0.40, rgb(0xFACC15)),   // yellow
    (0.72, rgb(0xFB923C)),   // orange
    (1.00, rgb(0xEF4444))    // red
]

func interpolate(_ position: CGFloat) -> CGColor {
    let clamped = min(max(position, 0), 1)
    for index in 1..<gaugeStops.count {
        let (end, endColor) = gaugeStops[index]
        let (start, startColor) = gaugeStops[index - 1]
        guard clamped <= end else { continue }
        let t = (clamped - start) / (end - start)
        let a = startColor.components ?? [0, 0, 0, 1]
        let b = endColor.components ?? [0, 0, 0, 1]
        return CGColor(red: a[0] + (b[0] - a[0]) * t,
                       green: a[1] + (b[1] - a[1]) * t,
                       blue: a[2] + (b[2] - a[2]) * t,
                       alpha: 1)
    }
    return gaugeStops.last!.1
}

// MARK: - Drawing

func drawIcon(into context: CGContext, size: CGFloat) {
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    // macOS icons sit inside a transparent margin.
    let inset = size * 0.055
    let body = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let corner = body.width * 0.2237
    let squircle = CGPath(roundedRect: body, cornerWidth: corner, cornerHeight: corner, transform: nil)

    // Drop shadow under the tile.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -size * 0.012),
                      blur: size * 0.03,
                      color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
    context.addPath(squircle)
    context.setFillColor(backgroundBottom)
    context.fillPath()
    context.restoreGState()

    // Background gradient.
    context.saveGState()
    context.addPath(squircle)
    context.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [backgroundTop, backgroundBottom] as CFArray,
                              locations: [0, 1])!
    context.drawLinearGradient(gradient,
                               start: CGPoint(x: body.minX, y: body.maxY),
                               end: CGPoint(x: body.maxX, y: body.minY),
                               options: [])

    // Soft highlight in the top-left corner.
    let highlight = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 0.28),
                                        CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray,
                               locations: [0, 1])!
    context.drawRadialGradient(highlight,
                               startCenter: CGPoint(x: body.minX + body.width * 0.22,
                                                    y: body.maxY - body.height * 0.18),
                               startRadius: 0,
                               endCenter: CGPoint(x: body.minX + body.width * 0.22,
                                                  y: body.maxY - body.height * 0.18),
                               endRadius: body.width * 0.62,
                               options: [])
    context.restoreGState()

    // Gauge ring: 270° arc, open at the bottom.
    let center = CGPoint(x: body.midX, y: body.midY + body.height * 0.03)
    let radius = body.width * 0.29
    let lineWidth = body.width * 0.115
    let startAngle = CGFloat.pi * 1.25      // 225°, lower-left
    let sweep = CGFloat.pi * 1.5            // 270° clockwise

    context.saveGState()
    context.setLineCap(.round)
    context.setLineWidth(lineWidth)

    // Track.
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.22))
    context.addArc(center: center, radius: radius,
                   startAngle: startAngle, endAngle: startAngle - sweep,
                   clockwise: true)
    context.strokePath()

    // Coloured value arc, drawn as short segments to fake an angular gradient.
    let filled: CGFloat = 0.78
    let segments = 160
    for index in 0..<segments {
        let t0 = CGFloat(index) / CGFloat(segments)
        let t1 = CGFloat(index + 1) / CGFloat(segments)
        guard t0 < filled else { break }
        context.setStrokeColor(interpolate(t0 / filled))
        context.addArc(center: center, radius: radius,
                       startAngle: startAngle - sweep * t0,
                       endAngle: startAngle - sweep * min(t1 + 0.004, filled),
                       clockwise: true)
        context.strokePath()
    }
    context.restoreGState()

    // Heartbeat trace across the middle of the ring.
    let traceWidth = body.width * 0.05
    let x0 = center.x - radius * 0.64
    let span = radius * 1.28
    let baseline = center.y - body.height * 0.01
    let points: [CGPoint] = [
        CGPoint(x: x0, y: baseline),
        CGPoint(x: x0 + span * 0.26, y: baseline),
        CGPoint(x: x0 + span * 0.38, y: baseline + radius * 0.52),
        CGPoint(x: x0 + span * 0.52, y: baseline - radius * 0.46),
        CGPoint(x: x0 + span * 0.64, y: baseline),
        CGPoint(x: x0 + span, y: baseline)
    ]

    context.saveGState()
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setLineWidth(traceWidth)
    context.setShadow(offset: .zero, blur: size * 0.02,
                      color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.addLines(between: points)
    context.strokePath()
    context.restoreGState()
}

func renderPNG(size: Int) -> Data {
    let scale = 1
    let pixels = size * scale
    let context = CGContext(data: nil,
                            width: pixels,
                            height: pixels,
                            bitsPerComponent: 8,
                            bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    drawIcon(into: context, size: CGFloat(pixels))
    let image = context.makeImage()!
    let representation = NSBitmapImageRep(cgImage: image)
    representation.size = NSSize(width: pixels, height: pixels)
    return representation.representation(using: .png, properties: [:])!
}

// MARK: - Iconset

let fileManager = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("PCHealth-\(UUID().uuidString).iconset")
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

for variant in variants {
    try renderPNG(size: variant.pixels).write(to: iconset.appendingPathComponent(variant.name))
}

// Keep a full-size preview next to the .icns for quick visual checks.
let output = URL(fileURLWithPath: outputPath)
try fileManager.createDirectory(at: output.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
try renderPNG(size: 1024).write(to: output.deletingPathExtension().appendingPathExtension("png"))

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try process.run()
process.waitUntilExit()
try? fileManager.removeItem(at: iconset)

guard process.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil failed\n".data(using: .utf8)!)
    exit(1)
}
print("wrote \(output.path)")
