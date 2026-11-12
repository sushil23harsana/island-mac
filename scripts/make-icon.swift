// Draws the Island app icon and writes a 1024×1024 PNG.
// Usage: swift scripts/make-icon.swift <output.png>   (scripts/make-icon.sh wraps this)
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}

// macOS icon grid: an 824pt rounded square centered on the 1024 canvas.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)

// Drop shadow under the tile.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0, 0, 0, 0.35))
ctx.addPath(tilePath)
ctx.setFillColor(color(0.1, 0.1, 0.2))
ctx.fillPath()
ctx.restoreGState()

// Background: a dusk-sky gradient, like a desktop wallpaper behind the island.
ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
let sky = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
    color(0.20, 0.16, 0.48), color(0.45, 0.27, 0.72), color(1.00, 0.56, 0.36),
] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(sky, start: CGPoint(x: tile.midX, y: tile.maxY),
                       end: CGPoint(x: tile.midX, y: tile.minY), options: [])

// Soft glow low on the horizon.
let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
    color(1, 0.85, 0.55, 0.55), color(1, 0.85, 0.55, 0),
] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: tile.midX, y: tile.minY + 120), startRadius: 0,
                       endCenter: CGPoint(x: tile.midX, y: tile.minY + 120), endRadius: 520, options: [])

// The island: a black pill hanging from the top edge, with rounded bottom corners.
let pillW: CGFloat = 520, pillH: CGFloat = 250, r: CGFloat = 96, ear: CGFloat = 34
let left = tile.midX - pillW / 2, right = tile.midX + pillW / 2
let top = tile.maxY, bottom = tile.maxY - pillH
let pill = CGMutablePath()
pill.move(to: CGPoint(x: left - ear, y: top))
pill.addQuadCurve(to: CGPoint(x: left, y: top - ear), control: CGPoint(x: left, y: top))
pill.addLine(to: CGPoint(x: left, y: bottom + r))
pill.addQuadCurve(to: CGPoint(x: left + r, y: bottom), control: CGPoint(x: left, y: bottom))
pill.addLine(to: CGPoint(x: right - r, y: bottom))
pill.addQuadCurve(to: CGPoint(x: right, y: bottom + r), control: CGPoint(x: right, y: bottom))
pill.addLine(to: CGPoint(x: right, y: top - ear))
pill.addQuadCurve(to: CGPoint(x: right + ear, y: top), control: CGPoint(x: right, y: top))
pill.closeSubpath()

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: color(0, 0, 0, 0.45))
ctx.addPath(pill)
ctx.setFillColor(color(0.02, 0.02, 0.03))
ctx.fillPath()
ctx.restoreGState()

// Inside the pill: a yellow note glyph on the left, an orange progress ring on the right.
let midY = bottom + pillH / 2 - 8
let yellow = color(1.00, 0.80, 0.26)
let orange = color(1.00, 0.56, 0.24)

let note = CGRect(x: left + 72, y: midY - 46, width: 104, height: 92)
ctx.addPath(CGPath(roundedRect: note, cornerWidth: 22, cornerHeight: 22, transform: nil))
ctx.setFillColor(yellow)
ctx.fillPath()
ctx.setStrokeColor(color(0.02, 0.02, 0.03))
ctx.setLineWidth(11)
ctx.setLineCap(.round)
for (i, width) in [58.0, 58.0, 34.0].enumerated() {
    let y = note.maxY - 25 - CGFloat(i) * 21
    ctx.move(to: CGPoint(x: note.minX + 23, y: y))
    ctx.addLine(to: CGPoint(x: note.minX + 23 + width, y: y))
}
ctx.strokePath()

let ringCenter = CGPoint(x: right - 124, y: midY)
ctx.setLineWidth(20)
ctx.setStrokeColor(color(1, 1, 1, 0.16))
ctx.addArc(center: ringCenter, radius: 44, startAngle: 0, endAngle: .pi * 2, clockwise: false)
ctx.strokePath()
ctx.setStrokeColor(orange)
ctx.addArc(center: ringCenter, radius: 44, startAngle: .pi / 2, endAngle: .pi / 2 - .pi * 1.3, clockwise: true)
ctx.strokePath()

ctx.restoreGState()

// Thin light rim on the tile edge.
ctx.addPath(tilePath)
ctx.setStrokeColor(color(1, 1, 1, 0.14))
ctx.setLineWidth(3)
ctx.strokePath()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
