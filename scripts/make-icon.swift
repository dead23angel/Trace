// Draws the Trace app icon and writes Support/AppIcon.icns.
// Run from the repository root: swift scripts/make-icon.swift
import AppKit

func draw(size: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = size / 1024

    // macOS icon grid: an 824-point rounded square centred on a 1024 canvas.
    let tile = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = CGPath(roundedRect: tile, cornerWidth: 185 * s, cornerHeight: 185 * s, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12 * s), blur: 28 * s,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.28))
    ctx.addPath(shape)
    ctx.setFillColor(CGColor(red: 0.04, green: 0.42, blue: 0.88, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Blue gradient, lighter at the top.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let space = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 0.29, green: 0.66, blue: 1.00, alpha: 1),
        CGColor(red: 0.04, green: 0.42, blue: 0.88, alpha: 1),
        CGColor(red: 0.03, green: 0.29, blue: 0.70, alpha: 1),
    ] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: tile.midX, y: tile.maxY),
                           end: CGPoint(x: tile.midX, y: tile.minY), options: [])

    // Faint hour lines behind the trace, like the day timeline in the app.
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
    ctx.setLineWidth(6 * s)
    for i in 1...3 {
        let y = tile.minY + tile.height * CGFloat(i) / 4
        ctx.move(to: CGPoint(x: tile.minX + 96 * s, y: y))
        ctx.addLine(to: CGPoint(x: tile.maxX - 96 * s, y: y))
    }
    ctx.strokePath()
    ctx.restoreGState()

    // The pulse line: flat, up, down, up, flat.
    let points: [(CGFloat, CGFloat)] = [(2, 12), (6, 12), (9, 4), (14, 20), (17, 12), (22, 12)]
    let unit = 30 * s
    let origin = CGPoint(x: tile.midX - 12 * unit, y: tile.midY + 12 * unit)
    let path = CGMutablePath()
    for (index, p) in points.enumerated() {
        let point = CGPoint(x: origin.x + p.0 * unit, y: origin.y - p.1 * unit)
        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8 * s), blur: 18 * s,
                  color: CGColor(red: 0, green: 0.12, blue: 0.4, alpha: 0.35))
    ctx.addPath(path)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.setLineWidth(64 * s)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let fm = FileManager.default
let iconset = fm.temporaryDirectory.appendingPathComponent("Trace-\(UUID().uuidString).iconset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let rep = draw(size: CGFloat(base * scale))
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
try draw(size: 1024).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: "docs/icon.png"))

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Support/AppIcon.icns"]
try task.run()
task.waitUntilExit()
try? fm.removeItem(at: iconset)
print(task.terminationStatus == 0 ? "Wrote Support/AppIcon.icns and docs/icon.png" : "iconutil failed")
