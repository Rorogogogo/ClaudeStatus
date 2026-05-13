// Renders the ClaudeStatus crab logo as a PNG at the requested size.
// Usage: swift gen-icon.swift <size> <output.png>
//
// The crab uses the same viewBox (66x52) as the in-app icon so the
// app icon and the README logo match.

import AppKit
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count >= 3, let size = Int(args[1]) else {
    FileHandle.standardError.write("usage: gen-icon.swift <size-px> <output.png>\n".data(using: .utf8)!)
    exit(1)
}
let outputPath = args[2]

let pixelSize = CGFloat(size)
let viewBox = CGSize(width: 66, height: 52)
let crabScale = min(pixelSize / viewBox.width, pixelSize / viewBox.height) * 0.78
let crabW = viewBox.width * crabScale
let crabH = viewBox.height * crabScale
let originX = (pixelSize - crabW) / 2
let originY = (pixelSize - crabH) / 2

let coral = CGColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1.0)
let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1.0)
let bg = CGColor(red: 0, green: 0, blue: 0, alpha: 1.0)

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: Int(pixelSize),
    height: Int(pixelSize),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write("failed to create CGContext\n".data(using: .utf8)!)
    exit(1)
}

// Rounded-rect black background (macOS app-icon style)
let radius = pixelSize * 0.22
let bgRect = CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
let bgPath = CGPath(roundedRect: bgRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
ctx.addPath(bgPath)
ctx.setFillColor(bg)
ctx.fillPath()

// Draw crab in viewBox coordinates with origin at top-left of crab area.
// CGContext origin is bottom-left, so flip vertically.
ctx.saveGState()
ctx.translateBy(x: originX, y: pixelSize - originY)
ctx.scaleBy(x: crabScale, y: -crabScale)

func fill(_ color: CGColor, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
    ctx.setFillColor(color)
    ctx.fill(CGRect(x: x, y: y, width: w, height: h))
}

// Antennae
fill(coral, 0,  13, 6, 13)
fill(coral, 60, 13, 6, 13)

// Legs
for x in [CGFloat(6), 18, 42, 54] { fill(coral, x, 39, 6, 13) }

// Body
fill(coral, 6, 0, 54, 39)

// Eyes (slightly inset)
fill(black, 12, 13, 6, 6.5)
fill(black, 48, 13, 6, 6.5)

ctx.restoreGState()

guard let image = ctx.makeImage() else {
    FileHandle.standardError.write("failed to create image\n".data(using: .utf8)!)
    exit(1)
}

let url = URL(fileURLWithPath: outputPath)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
    FileHandle.standardError.write("failed to open destination\n".data(using: .utf8)!)
    exit(1)
}
CGImageDestinationAddImage(dest, image, nil)
if !CGImageDestinationFinalize(dest) {
    FileHandle.standardError.write("failed to write png\n".data(using: .utf8)!)
    exit(1)
}
print("wrote \(outputPath) (\(size)x\(size))")
