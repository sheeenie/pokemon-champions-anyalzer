// Draws the app icon: a magnifying glass whose lens shows a golden Poké Ball.
//
// usage: swift tools/make_icon.swift
// Writes Assets/AppIcon.png (1024x1024) and Assets/AppIcon.icns, which build.sh
// copies into the app bundle.

import AppKit
import CoreGraphics

let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let assets = repo.appendingPathComponent("Assets")
let size: CGFloat = 1024
let space = CGColorSpaceCreateDeviceRGB()

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
}

func circle(_ c: CGPoint, _ r: CGFloat) -> CGRect {
    CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
}

let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
                    bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Draw in top-left coordinates.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

// MARK: Background: macOS icon grid, an 824pt rounded square centred on 1024.

let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: rgb(0x000000, 0.45))
ctx.addPath(tilePath)
ctx.setFillColor(rgb(0x121A33))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0x2B3A66), rgb(0x141C38), rgb(0x0A0F20)], [0, 0.55, 1]),
                       start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])

// Soft golden glow behind the lens.
let lensCenter = CGPoint(x: 462, y: 440)
ctx.drawRadialGradient(gradient([rgb(0xF4C44A, 0.30), rgb(0xF4C44A, 0)], [0, 1]),
                       startCenter: lensCenter, startRadius: 0,
                       endCenter: lensCenter, endRadius: 400, options: [])
ctx.restoreGState()

// Hairline edge highlight on the tile.
ctx.saveGState()
ctx.addPath(tilePath)
ctx.setStrokeColor(rgb(0xFFFFFF, 0.10))
ctx.setLineWidth(3)
ctx.strokePath()
ctx.restoreGState()

// MARK: Magnifier geometry

let outerRadius: CGFloat = 262
let ringWidth: CGFloat = 38
let innerRadius = outerRadius - ringWidth
let angle = CGFloat.pi / 4                      // handle points down and right
let direction = CGPoint(x: cos(angle), y: sin(angle))
let handleWidth: CGFloat = 92
let handleStart = CGPoint(x: lensCenter.x + direction.x * (outerRadius - 12),
                          y: lensCenter.y + direction.y * (outerRadius - 12))
let handleLength: CGFloat = 255

// MARK: Handle, with a drop shadow under the whole magnifier

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: rgb(0x000000, 0.55))
ctx.beginTransparencyLayer(auxiliaryInfo: nil)

ctx.saveGState()
ctx.translateBy(x: handleStart.x, y: handleStart.y)
ctx.rotate(by: angle)
let handleRect = CGRect(x: 0, y: -handleWidth / 2, width: handleLength, height: handleWidth)
ctx.addPath(CGPath(roundedRect: handleRect, cornerWidth: handleWidth / 2,
                   cornerHeight: handleWidth / 2, transform: nil))
ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0x6A7282), rgb(0x2C313B), rgb(0x14171D)], [0, 0.45, 1]),
                       start: CGPoint(x: 0, y: -handleWidth / 2),
                       end: CGPoint(x: 0, y: handleWidth / 2), options: [])
// Gold collar where the handle meets the ring.
let collar = CGRect(x: 0, y: -handleWidth / 2, width: 62, height: handleWidth)
ctx.saveGState()
ctx.clip(to: collar)
ctx.drawLinearGradient(gradient([rgb(0xFFE9A0), rgb(0xE2A72C), rgb(0x8E5E0C)], [0, 0.5, 1]),
                       start: CGPoint(x: 0, y: -handleWidth / 2),
                       end: CGPoint(x: 0, y: handleWidth / 2), options: [])
ctx.restoreGState()
// Grip highlight.
ctx.setFillColor(rgb(0xFFFFFF, 0.10))
ctx.fill(CGRect(x: 70, y: -handleWidth / 2 + 12, width: handleLength - 100, height: 10))
ctx.restoreGState()

// Ring: brushed silver annulus.
ctx.saveGState()
let ring = CGMutablePath()
ring.addEllipse(in: circle(lensCenter, outerRadius))
ring.addEllipse(in: circle(lensCenter, innerRadius))
ctx.addPath(ring)
ctx.clip(using: .evenOdd)
ctx.drawLinearGradient(gradient([rgb(0xFBFCFE), rgb(0xB9BFCA), rgb(0x6F7684), rgb(0xD9DDE4)],
                                [0, 0.35, 0.7, 1]),
                       start: CGPoint(x: lensCenter.x - outerRadius, y: lensCenter.y - outerRadius),
                       end: CGPoint(x: lensCenter.x + outerRadius, y: lensCenter.y + outerRadius),
                       options: [])
ctx.restoreGState()

ctx.endTransparencyLayer()
ctx.restoreGState()

// Ring edges.
ctx.setStrokeColor(rgb(0x2A2E37, 0.7))
ctx.setLineWidth(4)
ctx.strokeEllipse(in: circle(lensCenter, outerRadius - 2))
ctx.strokeEllipse(in: circle(lensCenter, innerRadius + 2))

// MARK: Golden Poké Ball inside the lens

func drawBall(center c: CGPoint, radius r: CGFloat) {
    ctx.saveGState()
    ctx.addEllipse(in: circle(c, r))
    ctx.clip()

    // Top half: rich gold.
    ctx.saveGState()
    ctx.clip(to: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: r))
    ctx.drawLinearGradient(gradient([rgb(0xFFEBA6), rgb(0xF3B834), rgb(0xB0740F)], [0, 0.55, 1]),
                           start: CGPoint(x: c.x, y: c.y - r), end: CGPoint(x: c.x, y: c.y), options: [])
    ctx.restoreGState()

    // Bottom half: pale gold.
    ctx.saveGState()
    ctx.clip(to: CGRect(x: c.x - r, y: c.y, width: 2 * r, height: r))
    ctx.drawLinearGradient(gradient([rgb(0xFFF7DE), rgb(0xE9CB85), rgb(0xB48C3C)], [0, 0.5, 1]),
                           start: CGPoint(x: c.x, y: c.y), end: CGPoint(x: c.x, y: c.y + r), options: [])
    ctx.restoreGState()

    // Roundness: darken towards the lower-right edge.
    let light = CGPoint(x: c.x - 0.35 * r, y: c.y - 0.35 * r)
    ctx.drawRadialGradient(gradient([rgb(0x000000, 0), rgb(0x000000, 0), rgb(0x3A2400, 0.45)],
                                    [0, 0.55, 1]),
                           startCenter: light, startRadius: 0, endCenter: c, endRadius: r * 1.05,
                           options: [])

    // Band and button.
    let band = 0.085 * r
    ctx.setFillColor(rgb(0x2E2112))
    ctx.fill(CGRect(x: c.x - r, y: c.y - band, width: 2 * r, height: 2 * band))
    ctx.fillEllipse(in: circle(c, 0.32 * r))
    ctx.saveGState()
    ctx.addEllipse(in: circle(c, 0.24 * r))
    ctx.clip()
    ctx.drawRadialGradient(gradient([rgb(0xFFFEF6), rgb(0xF2DFA6), rgb(0xC9A650)], [0, 0.6, 1]),
                           startCenter: CGPoint(x: c.x - 0.06 * r, y: c.y - 0.07 * r), startRadius: 0,
                           endCenter: c, endRadius: 0.24 * r, options: [])
    ctx.restoreGState()
    ctx.setStrokeColor(rgb(0xB8913D, 0.9))
    ctx.setLineWidth(0.022 * r)
    ctx.strokeEllipse(in: circle(c, 0.15 * r))

    // Specular highlight on the top half.
    ctx.saveGState()
    ctx.translateBy(x: c.x - 0.36 * r, y: c.y - 0.52 * r)
    ctx.rotate(by: -0.55)
    ctx.scaleBy(x: 1, y: 0.5)
    ctx.drawRadialGradient(gradient([rgb(0xFFFFFF, 0.75), rgb(0xFFFFFF, 0)], [0, 1]),
                           startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 0.36 * r,
                           options: [])
    ctx.restoreGState()

    ctx.restoreGState()

    ctx.setStrokeColor(rgb(0x2E2112))
    ctx.setLineWidth(0.035 * r)
    ctx.strokeEllipse(in: circle(c, r - 0.0175 * r))
}

// Dark glass behind the ball, visible only as a thin rim.
ctx.setFillColor(rgb(0x0C1428))
ctx.fillEllipse(in: circle(lensCenter, innerRadius))
drawBall(center: lensCenter, radius: innerRadius - 10)

// MARK: Glass: inner edge shade and glare

ctx.saveGState()
ctx.addEllipse(in: circle(lensCenter, innerRadius))
ctx.clip()
ctx.drawRadialGradient(gradient([rgb(0x000000, 0), rgb(0x000000, 0), rgb(0x000000, 0.35)],
                                [0, 0.8, 1]),
                       startCenter: lensCenter, startRadius: 0,
                       endCenter: lensCenter, endRadius: innerRadius, options: [])
ctx.restoreGState()

ctx.setLineCap(.round)
ctx.setStrokeColor(rgb(0xFFFFFF, 0.55))
ctx.setLineWidth(16)
ctx.addArc(center: lensCenter, radius: innerRadius * 0.80,
           startAngle: .pi * 1.08, endAngle: .pi * 1.36, clockwise: false)
ctx.strokePath()
ctx.setStrokeColor(rgb(0xFFFFFF, 0.35))
ctx.setLineWidth(10)
ctx.addArc(center: lensCenter, radius: innerRadius * 0.80,
           startAngle: .pi * 1.43, endAngle: .pi * 1.50, clockwise: false)
ctx.strokePath()

// MARK: Output

let master = ctx.makeImage()!
try! FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

func writePNG(_ image: CGImage, _ url: URL) {
    try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: url)
}

func scaled(_ pixels: Int) -> CGImage {
    let c = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.interpolationQuality = .high
    c.draw(master, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    return c.makeImage()!
}

writePNG(master, assets.appendingPathComponent("AppIcon.png"))

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    writePNG(scaled(base), iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    writePNG(scaled(base * 2), iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", assets.appendingPathComponent("AppIcon.icns").path]
try! iconutil.run()
iconutil.waitUntilExit()
precondition(iconutil.terminationStatus == 0, "iconutil failed")
print("Wrote Assets/AppIcon.png and Assets/AppIcon.icns")
