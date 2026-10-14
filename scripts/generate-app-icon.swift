import AppKit
import SwiftUI

// Run from the repository root with: swift scripts/generate-app-icon.swift
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources")
let sourceURL = resources.appendingPathComponent("AppIcon-source.png")
guard let source = NSImage(contentsOf: sourceURL) else {
  fatalError("Cannot read \(sourceURL.path)")
}
let output = root.appendingPathComponent(".cache/AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(size: Int) throws -> Data {
  guard
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: 0, bitsPerPixel: 0),
    let context = NSGraphicsContext(bitmapImageRep: bitmap)
  else { fatalError("Cannot allocate icon bitmap") }
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  defer { NSGraphicsContext.restoreGraphicsState() }
  context.cgContext.clear(CGRect(x: 0, y: 0, width: size, height: size))
  let scale = CGFloat(size) / 1024
  context.imageInterpolation = .high
  let rect = CGRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
  let path = RoundedRectangle(cornerRadius: 185 * scale, style: .continuous).path(in: rect).cgPath
  context.cgContext.saveGState()
  context.cgContext.setShadow(
    offset: CGSize(width: 0, height: -8 * scale), blur: 16 * scale,
    color: NSColor.black.withAlphaComponent(0.25).cgColor)
  context.cgContext.addPath(path)
  context.cgContext.setFillColor(NSColor.white.cgColor)
  context.cgContext.fillPath()
  context.cgContext.restoreGState()
  context.cgContext.addPath(path)
  context.cgContext.clip()
  source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
  guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Cannot encode icon PNG")
  }
  return png
}

for size in [16, 32, 128, 256, 512] {
  try render(size: size).write(to: output.appendingPathComponent("icon_\(size)x\(size).png"))
  try render(size: size * 2).write(
    to: output.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try render(size: 1024).write(to: resources.appendingPathComponent("AppIcon.png"))
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = [
  "-c", "icns", output.path, "-o", resources.appendingPathComponent("AppIcon.icns").path,
]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Generated Resources/AppIcon.png and Resources/AppIcon.icns")
