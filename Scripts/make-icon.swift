import AppKit

// Flat icon: dark slate squircle, dashboard tile layout, one accent tile with a progress ring.
let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
    let ctx = NSGraphicsContext.current!.cgContext
    let inset: CGFloat = 100
    let body = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    NSColor(srgbRed: 0.11, green: 0.12, blue: 0.14, alpha: 1).setFill()
    shape.fill()
    NSColor(white: 1, alpha: 0.08).setStroke()
    shape.lineWidth = 4
    shape.stroke()

    let pad: CGFloat = 88, gap: CGFloat = 36
    let area = body.insetBy(dx: pad, dy: pad)
    let unit = (area.width - gap * 2) / 3
    func tile(_ c: Int, _ r: Int, _ w: Int, _ h: Int) -> CGRect {
        CGRect(x: area.minX + CGFloat(c) * (unit + gap), y: area.minY + CGFloat(r) * (unit + gap),
               width: CGFloat(w) * unit + CGFloat(w - 1) * gap, height: CGFloat(h) * unit + CGFloat(h - 1) * gap)
    }
    let light = NSColor(white: 0.93, alpha: 1)
    let dim = NSColor(white: 0.93, alpha: 0.35)
    // Accent tile (2x2) with ring
    let accentRect = tile(0, 0, 2, 2)
    NSColor(srgbRed: 0.20, green: 0.48, blue: 0.98, alpha: 1).setFill()
    NSBezierPath(roundedRect: accentRect, xRadius: 44, yRadius: 44).fill()
    let center = CGPoint(x: accentRect.midX, y: accentRect.midY)
    let radius = accentRect.width * 0.27
    ctx.setLineWidth(46); ctx.setLineCap(.round)
    ctx.setStrokeColor(NSColor(white: 1, alpha: 0.3).cgColor)
    ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false); ctx.strokePath()
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.addArc(center: center, radius: radius, startAngle: -.pi / 2, endAngle: -.pi / 2 + .pi * 2 * 0.68, clockwise: false); ctx.strokePath()
    // Other tiles
    light.setFill()
    NSBezierPath(roundedRect: tile(2, 0, 1, 1), xRadius: 36, yRadius: 36).fill()
    dim.setFill()
    NSBezierPath(roundedRect: tile(2, 1, 1, 1), xRadius: 36, yRadius: 36).fill()
    dim.setFill()
    NSBezierPath(roundedRect: tile(0, 2, 1, 1), xRadius: 36, yRadius: 36).fill()
    light.setFill()
    NSBezierPath(roundedRect: tile(1, 2, 2, 1), xRadius: 36, yRadius: 36).fill()
    // Prompt chevron on the wide tile (terminal hint)
    let t = tile(1, 2, 2, 1)
    let chevron = NSBezierPath()
    chevron.move(to: CGPoint(x: t.minX + 60, y: t.midY - 40))
    chevron.line(to: CGPoint(x: t.minX + 110, y: t.midY))
    chevron.line(to: CGPoint(x: t.minX + 60, y: t.midY + 40))
    chevron.lineWidth = 26; chevron.lineCapStyle = .round; chevron.lineJoinStyle = .round
    NSColor(srgbRed: 0.11, green: 0.12, blue: 0.14, alpha: 1).setStroke()
    chevron.stroke()
    let line = NSBezierPath(roundedRect: CGRect(x: t.minX + 150, y: t.midY + 24, width: 120, height: 24), xRadius: 12, yRadius: 12)
    NSColor(srgbRed: 0.11, green: 0.12, blue: 0.14, alpha: 1).setFill()
    line.fill()
    return true
}
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
img.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
