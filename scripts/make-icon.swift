// Renders Resources/AppIcon.icns: a dark glass tile with a floating capsule.
// Usage: swift scripts/make-icon.swift   (then iconutil is run by make-icon.sh)
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // macOS icon grid: 824/1024 tile, centred.
    let inset = s * 100 / 1024
    let tile = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = tile.width * 0.225
    let tilePath = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03,
                  color: NSColor.black.withAlphaComponent(0.45).cgColor)
    ctx.addPath(tilePath)
    ctx.setFillColor(NSColor(srgbRed: 0.13, green: 0.13, blue: 0.135, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Backdrop: soft dusk landscape glow (muted sage → slate).
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let bg = CGGradient(colorsSpace: space, colors: [
        NSColor(srgbRed: 0.42, green: 0.49, blue: 0.47, alpha: 1).cgColor,
        NSColor(srgbRed: 0.17, green: 0.20, blue: 0.21, alpha: 1).cgColor,
        NSColor(srgbRed: 0.09, green: 0.09, blue: 0.10, alpha: 1).cgColor
    ] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: tile.midX, y: tile.maxY), end: CGPoint(x: tile.midX, y: tile.minY), options: [])
    let glow = CGGradient(colorsSpace: space, colors: [
        NSColor(srgbRed: 0.80, green: 0.86, blue: 0.82, alpha: 0.35).cgColor,
        NSColor(srgbRed: 0.80, green: 0.86, blue: 0.82, alpha: 0).cgColor
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: tile.midX, y: tile.minY + tile.height * 0.25), startRadius: 0,
                           endCenter: CGPoint(x: tile.midX, y: tile.minY + tile.height * 0.25), endRadius: tile.width * 0.6, options: [])

    // Glass card.
    let card = tile.insetBy(dx: tile.width * 0.14, dy: tile.height * 0.2).offsetBy(dx: 0, dy: -tile.height * 0.06)
    let cardPath = CGPath(roundedRect: card, cornerWidth: card.width * 0.16, cornerHeight: card.width * 0.16, transform: nil)
    ctx.addPath(cardPath)
    ctx.setFillColor(NSColor(srgbRed: 0.25, green: 0.26, blue: 0.27, alpha: 0.55).cgColor)
    ctx.fillPath()
    ctx.addPath(cardPath)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
    ctx.setLineWidth(max(1, s * 0.004))
    ctx.strokePath()

    // Island capsule hanging from the top edge.
    let capW = tile.width * 0.46, capH = tile.height * 0.12
    let cap = CGRect(x: tile.midX - capW / 2, y: tile.maxY - capH - tile.height * 0.1, width: capW, height: capH)
    let capPath = CGPath(roundedRect: cap, cornerWidth: capH / 2, cornerHeight: capH / 2, transform: nil)
    ctx.addPath(capPath)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.addPath(capPath)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.25).cgColor)
    ctx.strokePath()
    let dot = CGRect(x: cap.maxX - capH * 0.85, y: cap.midY - capH * 0.18, width: capH * 0.36, height: capH * 0.36)
    ctx.setShadow(offset: .zero, blur: s * 0.02, color: NSColor(srgbRed: 0.62, green: 0.82, blue: 0.76, alpha: 1).cgColor)
    ctx.setFillColor(NSColor(srgbRed: 0.66, green: 0.84, blue: 0.78, alpha: 1).cgColor)
    ctx.fillEllipse(in: dot)
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    // Lines on the card (content hint).
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.85).cgColor)
    let line1 = CGRect(x: card.minX + card.width * 0.12, y: card.midY, width: card.width * 0.42, height: card.height * 0.1)
    ctx.addPath(CGPath(roundedRect: line1, cornerWidth: line1.height / 2, cornerHeight: line1.height / 2, transform: nil))
    ctx.fillPath()
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.4).cgColor)
    let line2 = CGRect(x: line1.minX, y: line1.minY - card.height * 0.2, width: card.width * 0.62, height: card.height * 0.07)
    ctx.addPath(CGPath(roundedRect: line2, cornerWidth: line2.height / 2, cornerHeight: line2.height / 2, transform: nil))
    ctx.fillPath()
    ctx.restoreGState()

    // Edge highlight.
    ctx.addPath(tilePath)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.18).cgColor)
    ctx.setLineWidth(max(1, s * 0.003))
    ctx.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
                   ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
                   ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
print("rendered \(out)")
