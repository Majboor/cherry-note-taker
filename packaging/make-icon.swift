// Draws the Cherry app icon (two cherries on a cream tile) and writes an .iconset.
// Usage: swift packaging/make-icon.swift <out.iconset>   then   iconutil -c icns <out.iconset>
import AppKit
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1, tile = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    NSColor(calibratedRed: 0.99, green: 0.96, blue: 0.91, alpha: 1).setFill()
    NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225).fill()
    // stems
    let stem = NSBezierPath(); stem.lineWidth = s * 0.035; stem.lineCapStyle = .round
    stem.move(to: NSPoint(x: s * 0.36, y: s * 0.42)); stem.curve(to: NSPoint(x: s * 0.60, y: s * 0.76), controlPoint1: NSPoint(x: s * 0.40, y: s * 0.62), controlPoint2: NSPoint(x: s * 0.52, y: s * 0.72))
    stem.move(to: NSPoint(x: s * 0.64, y: s * 0.40)); stem.curve(to: NSPoint(x: s * 0.60, y: s * 0.76), controlPoint1: NSPoint(x: s * 0.64, y: s * 0.58), controlPoint2: NSPoint(x: s * 0.62, y: s * 0.70))
    NSColor(calibratedRed: 0.27, green: 0.42, blue: 0.20, alpha: 1).setStroke(); stem.stroke()
    // leaf
    let leaf = NSBezierPath(); leaf.move(to: NSPoint(x: s * 0.60, y: s * 0.76))
    leaf.curve(to: NSPoint(x: s * 0.78, y: s * 0.74), controlPoint1: NSPoint(x: s * 0.66, y: s * 0.86), controlPoint2: NSPoint(x: s * 0.76, y: s * 0.84))
    leaf.curve(to: NSPoint(x: s * 0.60, y: s * 0.76), controlPoint1: NSPoint(x: s * 0.74, y: s * 0.68), controlPoint2: NSPoint(x: s * 0.64, y: s * 0.68))
    NSColor(calibratedRed: 0.40, green: 0.62, blue: 0.27, alpha: 1).setFill(); leaf.fill()
    // cherries
    for (cx, cy) in [(0.35, 0.33), (0.64, 0.31)] {
        let r = s * 0.14, c = NSRect(x: s * cx - r, y: s * cy - r, width: 2 * r, height: 2 * r)
        NSGradient(starting: NSColor(calibratedRed: 0.93, green: 0.20, blue: 0.24, alpha: 1),
                   ending: NSColor(calibratedRed: 0.62, green: 0.05, blue: 0.12, alpha: 1))!.draw(in: NSBezierPath(ovalIn: c), relativeCenterPosition: NSPoint(x: -0.4, y: 0.4))
        NSColor(white: 1, alpha: 0.55).setFill()
        NSBezierPath(ovalIn: NSRect(x: c.minX + r * 0.45, y: c.minY + r * 1.2, width: r * 0.42, height: r * 0.3)).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
for base in [16, 32, 128, 256, 512] {
    try! draw(base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try! draw(base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
