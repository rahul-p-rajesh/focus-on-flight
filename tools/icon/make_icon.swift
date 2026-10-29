// Draws Contrail's app icon: dark satellite-field square, white plane, two contrails.
// Usage: swift make_icon.swift OUT.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments[1]
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let shape = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
shape.addClip()
NSGradient(colors: [NSColor(red: 0.16, green: 0.24, blue: 0.20, alpha: 1), NSColor(red: 0.05, green: 0.08, blue: 0.07, alpha: 1)])!
    .draw(in: rect, angle: -60)
// Field patches and roads, like farmland seen from above.
var seed: UInt64 = 7
func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1; return CGFloat((seed >> 33) % 10_000) / 10_000 }
for _ in 0..<70 {
    let w = 60 + rnd() * 160, h = 50 + rnd() * 140
    let r = NSRect(x: rect.minX + rnd() * rect.width, y: rect.minY + rnd() * rect.height, width: w, height: h)
    NSColor(red: 0.3 + rnd() * 0.2, green: 0.38 + rnd() * 0.15, blue: 0.25, alpha: 0.07 + rnd() * 0.08).setFill()
    r.fill(using: .sourceOver)
}
NSColor.white.withAlphaComponent(0.09).setStroke()
for i in 0..<5 {
    let p = NSBezierPath()
    let x = rect.minX + CGFloat(i) * 190 + 40
    p.move(to: NSPoint(x: x, y: rect.minY)); p.line(to: NSPoint(x: x + 30, y: rect.maxY)); p.lineWidth = 4; p.stroke()
}
// Contrails.
for dx in [-34.0, 34.0] {
    for i in 0..<46 {
        let t = CGFloat(i) / 46
        let r = 7 + t * 16
        let x = size / 2 + CGFloat(dx) + sin(CGFloat(i) * 0.8) * t * 6
        let y = size / 2 - 60 - CGFloat(i) * 9
        NSColor.white.withAlphaComponent(0.85 * pow(1 - t, 1.5)).setFill()
        NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2)).fill()
    }
}
// Plane, nose up.
let cfg = NSImage.SymbolConfiguration(pointSize: 300, weight: .regular).applying(.init(paletteColors: [.white]))
if let plane = NSImage(systemSymbolName: "airplane", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
    ctx.saveGState()
    ctx.translateBy(x: size / 2, y: size / 2 + 40)
    ctx.rotate(by: .pi / 2)
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.5).cgColor)
    plane.draw(in: NSRect(x: -plane.size.width / 2, y: -plane.size.height / 2, width: plane.size.width, height: plane.size.height))
    ctx.restoreGState()
}
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
