#!/usr/bin/env swift

import AppKit
import Foundation

// Generates a modern, minimal macOS app icon (Caret + Wave).
//
// Usage:
//   scripts/generate_appicon.swift [output-dir]
//
// Default output directory:
//   apps/macos/AIVoiceKeyboard/AIVoiceKeyboard/Assets.xcassets/AppIcon.appiconset

struct IconPalette {
  // Background: deep graphite with a subtle diagonal gradient.
  static let bgTopLeft = NSColor(calibratedRed: 0.09, green: 0.11, blue: 0.14, alpha: 1.0)    // #171C24-ish
  static let bgBottomRight = NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.06, alpha: 1.0) // #0A0D10-ish

  // Foreground + accent.
  static let caret = NSColor(calibratedWhite: 0.97, alpha: 1.0)
  static let waveAccent = NSColor(calibratedRed: 0.04, green: 0.52, blue: 1.00, alpha: 1.0) // macOS-ish blue
  static let waveNeutral = NSColor(calibratedWhite: 0.78, alpha: 1.0)
}

struct IconGeometry {
  // All geometry is defined in a 1024x1024 design-space for consistency.
  static let base: CGFloat = 1024

  static let caretWidth: CGFloat = 96
  static let caretHeight: CGFloat = 560

  static let innerArcRadius: CGFloat = 300
  static let outerArcRadius: CGFloat = 392

  static let innerArcLineWidth: CGFloat = 56
  static let outerArcLineWidth: CGFloat = 46

  // Degrees. Right arc uses a wrap-around angle (290 -> 70) to avoid negative degrees.
  static let rightArcStart: CGFloat = 290
  static let rightArcEnd: CGFloat = 70
  static let leftArcStart: CGFloat = 110
  static let leftArcEnd: CGFloat = 250
}

func drawIcon(into rect: CGRect) {
  // Background gradient.
  let bg = NSGradient(colors: [IconPalette.bgTopLeft, IconPalette.bgBottomRight])!
  bg.draw(in: rect, angle: -45)

  // Subtle highlight (radial bloom) for a more "finished" macOS look.
  let highlightGradient = NSGradient(colors: [
    NSColor.white.withAlphaComponent(0.12),
    NSColor.white.withAlphaComponent(0.00),
  ])!
  highlightGradient.draw(
    fromCenter: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY + rect.height * 0.78),
    radius: rect.width * 0.05,
    toCenter: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY + rect.height * 0.78),
    radius: rect.width * 0.78,
    options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation]
  )

  // Geometry scaling.
  let scale = rect.width / IconGeometry.base
  let center = CGPoint(x: rect.midX, y: rect.midY)

  func strokeArc(
    radius: CGFloat,
    startDeg: CGFloat,
    endDeg: CGFloat,
    lineWidth: CGFloat,
    color: NSColor
  ) {
    let path = NSBezierPath()
    path.appendArc(withCenter: center, radius: radius * scale, startAngle: startDeg, endAngle: endDeg, clockwise: false)
    path.lineWidth = lineWidth * scale
    path.lineCapStyle = .round
    color.setStroke()
    path.stroke()
  }

  // Waves (outer neutral + inner accent).
  strokeArc(
    radius: IconGeometry.outerArcRadius,
    startDeg: IconGeometry.leftArcStart,
    endDeg: IconGeometry.leftArcEnd,
    lineWidth: IconGeometry.outerArcLineWidth,
    color: IconPalette.waveNeutral.withAlphaComponent(0.55)
  )
  strokeArc(
    radius: IconGeometry.outerArcRadius,
    startDeg: IconGeometry.rightArcStart,
    endDeg: IconGeometry.rightArcEnd,
    lineWidth: IconGeometry.outerArcLineWidth,
    color: IconPalette.waveNeutral.withAlphaComponent(0.55)
  )

  strokeArc(
    radius: IconGeometry.innerArcRadius,
    startDeg: IconGeometry.leftArcStart,
    endDeg: IconGeometry.leftArcEnd,
    lineWidth: IconGeometry.innerArcLineWidth,
    color: IconPalette.waveAccent.withAlphaComponent(0.88)
  )
  strokeArc(
    radius: IconGeometry.innerArcRadius,
    startDeg: IconGeometry.rightArcStart,
    endDeg: IconGeometry.rightArcEnd,
    lineWidth: IconGeometry.innerArcLineWidth,
    color: IconPalette.waveAccent.withAlphaComponent(0.88)
  )

  // Caret (with a restrained glow so it reads well at small sizes).
  let caretW = IconGeometry.caretWidth * scale
  let caretH = IconGeometry.caretHeight * scale
  let caretRect = CGRect(
    x: center.x - caretW / 2,
    y: center.y - caretH / 2,
    width: caretW,
    height: caretH
  )
  let caretPath = NSBezierPath(roundedRect: caretRect, xRadius: caretW / 2, yRadius: caretW / 2)

  let glow = NSShadow()
  glow.shadowBlurRadius = 54 * scale
  glow.shadowOffset = .zero
  glow.shadowColor = IconPalette.waveAccent.withAlphaComponent(0.35)

  NSGraphicsContext.saveGraphicsState()
  glow.set()
  IconPalette.caret.setFill()
  caretPath.fill()
  NSGraphicsContext.restoreGraphicsState()

  IconPalette.caret.setFill()
  caretPath.fill()
}

func renderBaseImage(size: Int) -> NSBitmapImageRep {
  guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  ) else {
    fatalError("Failed to allocate bitmap image rep")
  }

  guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
    fatalError("Failed to create graphics context")
  }

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = ctx

  // Ensure best downscaling quality when we later draw this image into smaller bitmaps.
  ctx.cgContext.interpolationQuality = .high
  ctx.cgContext.setAllowsAntialiasing(true)
  ctx.cgContext.setShouldAntialias(true)

  drawIcon(into: CGRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size)))

  NSGraphicsContext.restoreGraphicsState()
  return rep
}

func renderScaledPNG(from cgImage: CGImage, size: Int, url: URL) throws {
  guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  ) else {
    throw NSError(domain: "IconGen", code: 1)
  }

  guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
    throw NSError(domain: "IconGen", code: 2)
  }

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = ctx
  ctx.cgContext.interpolationQuality = .high
  ctx.cgContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size)))
  NSGraphicsContext.restoreGraphicsState()

  guard let data = rep.representation(using: .png, properties: [:]) else {
    throw NSError(domain: "IconGen", code: 3)
  }
  try data.write(to: url, options: [.atomic])
}

func main() throws {
  let outputDir = CommandLine.arguments.dropFirst().first
    .map { URL(fileURLWithPath: $0) }
    ?? URL(fileURLWithPath: "apps/macos/AIVoiceKeyboard/AIVoiceKeyboard/Assets.xcassets/AppIcon.appiconset")

  try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

  let base = renderBaseImage(size: 1024)
  guard let baseCG = base.cgImage else {
    throw NSError(domain: "IconGen", code: 4)
  }

  // macOS AppIcon set sizes.
  let outputs: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
  ]

  for (name, px) in outputs {
    try renderScaledPNG(from: baseCG, size: px, url: outputDir.appendingPathComponent(name))
  }

  // Write AppIcon Contents.json.
  let contents = """
  {
    "images" : [
      { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
      { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
      { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
      { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
      { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
      { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
      { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
      { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
      { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
      { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
    ],
    "info" : { "author" : "codex", "version" : 1 }
  }
  """

  try contents.write(to: outputDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

  print("Generated AppIcon at: \(outputDir.path)")
}

try main()
