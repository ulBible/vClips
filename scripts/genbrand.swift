// Regenerates the Chakchak Works brand masters with the G1 "setting the last
// block into place" mark. The hand-lettered wordmark is reused by cropping it
// from the existing brand-logo.png so the original lettering is preserved.
//
//   swift genbrand.swift <repo-root>
import AppKit

let repo = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let imagesDir = "\(repo)/docs/images"

let ink = NSColor(calibratedRed: 0.149, green: 0.149, blue: 0.149, alpha: 1)   // #262626
let blue = NSColor(calibratedRed: 0.16, green: 0.42, blue: 0.96, alpha: 1)

func strokeLine(_ a: NSPoint, _ b: NSPoint, _ w: CGFloat, _ c: NSColor) {
    c.setStroke()
    let p = NSBezierPath()
    p.lineWidth = w
    p.lineCapStyle = .round
    p.move(to: a); p.line(to: b)
    p.stroke()
}

/// Draws the G1 mark into a 100u × 110u design box with AppKit (y-up) coords.
/// Design grid (top-down): ink blocks at (18,44) (18,78) (52,78), hairline
/// slot at (52,44), blue block at (52,18) tilted 8° CCW, two descent dashes.
func drawMark(origin o: NSPoint, unit u: CGFloat) {
    func blockPath(_ x: CGFloat, _ yTop: CGFloat) -> NSBezierPath {
        let r = NSRect(x: o.x + x * u, y: o.y + (80 - yTop) * u, width: 30 * u, height: 30 * u)
        return NSBezierPath(roundedRect: r, xRadius: 8 * u, yRadius: 8 * u)
    }
    ink.setFill()
    blockPath(18, 44).fill()
    blockPath(18, 78).fill()
    blockPath(52, 78).fill()

    let slot = blockPath(52, 44)
    slot.lineWidth = 1.3 * u
    ink.withAlphaComponent(0.3).setStroke()
    slot.stroke()

    NSGraphicsContext.current?.saveGraphicsState()
    let cx = o.x + 67 * u, cy = o.y + 77 * u
    let t = NSAffineTransform()
    t.translateX(by: cx, yBy: cy)
    t.rotate(byDegrees: 8)
    t.translateX(by: -cx, yBy: -cy)
    t.concat()
    blue.setFill()
    blockPath(52, 18).fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    let trail = ink.withAlphaComponent(0.45)
    strokeLine(NSPoint(x: o.x + 77 * u, y: o.y + 101 * u),
               NSPoint(x: o.x + 77 * u, y: o.y + 108 * u), 2.8 * u, trail)
    strokeLine(NSPoint(x: o.x + 86 * u, y: o.y + 97 * u),
               NSPoint(x: o.x + 86 * u, y: o.y + 104 * u), 2.8 * u, trail)
}

func render(width: Int, height: Int, to path: String, draw: () -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    draw()
    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

// --- avatar: square, mark only ---
render(width: 2048, height: 2048, to: "\(imagesDir)/brand-avatar.png") {
    let u: CGFloat = 12.4                       // mark 1240 × 1364
    drawMark(origin: NSPoint(x: (2048 - 100 * u) / 2, y: (2048 - 110 * u) / 2), unit: u)
}

// --- lockup: mark on top, original hand lettering below (cropped from old master) ---
// The old master is 144dpi (1600×800 px = 800×400 pt), so crop by fractions of
// NSImage.size, not pixels. Wordmark band: x 30–70 %, top-down y 70–81.5 %.
let oldPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "\(imagesDir)/brand-logo.png"
let old = NSImage(contentsOfFile: oldPath)!
render(width: 1600, height: 800, to: "\(imagesDir)/brand-logo.png") {
    let W = old.size.width, H = old.size.height
    let src = NSRect(x: 0.30 * W, y: 0.185 * H, width: 0.40 * W, height: 0.115 * H)
    let dst = NSRect(x: 480, y: 148, width: 640, height: 92)
    old.draw(in: dst, from: src, operation: .sourceOver, fraction: 1)
    let u: CGFloat = 3.9                        // mark 390 × 429
    drawMark(origin: NSPoint(x: (1600 - 100 * u) / 2, y: 296), unit: u)
}
