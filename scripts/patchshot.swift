// Patches the App Store screenshot footer hint: repaints the "Paste" label
// with the sampled footer background and draws "Copy" in the same style.
//   swift patchshot.swift <in.png> <out.png> <labelX> <labelTopY>
// labelX/labelTopY = top-left of the old "Paste" text in top-down pixel coords.
import AppKit

let a = CommandLine.arguments
guard a.count == 5, let lx = Double(a[3]), let ly = Double(a[4]) else {
    fatalError("usage: patchshot in out labelX labelTopY")
}
let image = NSImage(contentsOfFile: a[1])!
let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let W = cg.width, H = cg.height

// Read one pixel (top-down coords) by drawing the image into a 1×1 context.
func pixel(_ x: Int, _ y: Int) -> NSColor {
    var buf = [UInt8](repeating: 0, count: 4)
    let ctx = CGContext(data: &buf, width: 1, height: 1, bitsPerComponent: 8,
                        bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: -x, y: -(H - 1 - y), width: W, height: H))
    return NSColor(srgbRed: CGFloat(buf[0]) / 255, green: CGFloat(buf[1]) / 255,
                   blue: CGFloat(buf[2]) / 255, alpha: 1)
}
// Scan the old label box: the darkest pixel is the flat bar, the lightest is
// the glyph core — robust against hitting antialiased edges or chip fringes.
var bg = NSColor.white, fg = NSColor.black
var minLum = 2.0, maxLum = -1.0
for sx in stride(from: Int(lx), through: Int(lx) + 44, by: 2) {
    for sy in stride(from: Int(ly), through: Int(ly) + 20, by: 2) {
        let c = pixel(sx, sy)
        let lum = Double(0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent)
        if lum < minLum { minLum = lum; bg = c }
        if lum > maxLum { maxLum = lum; fg = c }
    }
}
print("bg:", bg, "fg:", fg)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.cgContext.interpolationQuality = .none
image.draw(in: NSRect(x: 0, y: 0, width: W, height: H))

// Cover the old label (58px wide catches "Paste" plus antialiasing fringe).
bg.setFill()
NSRect(x: lx - 3, y: CGFloat(H) - ly - 26, width: 58, height: 30).fill()

// Redraw. The shots are @2x, footer hints are 10pt → 20px.
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 20, weight: .regular),
    .foregroundColor: fg,
]
NSAttributedString(string: "Copy", attributes: attrs)
    .draw(at: NSPoint(x: lx, y: CGFloat(H) - ly - 24))

NSGraphicsContext.current?.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: a[2]))
print("wrote", a[2])
