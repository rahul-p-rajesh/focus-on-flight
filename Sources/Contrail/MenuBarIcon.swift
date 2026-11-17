import AppKit
import SwiftUI

/// The menu bar icon: pilot's wings around the app's own airliner, rather than the system airplane
/// symbol, which macOS uses for Airplane Mode. A template image, so macOS tints it for light and dark menu bars.
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 30, height: 16), flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setFillColor(NSColor.black.cgColor)
            drawWings(ctx, in: rect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Focus on Flight"
        return image
    }()

    /// Pilot's wings: a round badge with the plane cut out, three swept feathers either side.
    private static func drawWings(_ ctx: CGContext, in rect: CGRect) {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r: CGFloat = 5.6
        for side in [-1.0, 1.0] as [CGFloat] {
            for i in 0..<3 {
                let fi = CGFloat(i)
                let rootY = c.y - 3.4 + fi * 2.9
                let half = 1.15 - fi * 0.12
                let tipX = c.x + side * (r + 8.6 - fi * 2.6)
                let tipY = rootY - 2.6 + fi * 0.6
                let rootX = c.x + side * (r - 1)
                let p = CGMutablePath()
                p.move(to: CGPoint(x: rootX, y: rootY - half))
                p.addQuadCurve(to: CGPoint(x: tipX, y: tipY), control: CGPoint(x: rootX + side * 5, y: rootY - half - 0.6))
                p.addQuadCurve(to: CGPoint(x: rootX, y: rootY + half), control: CGPoint(x: rootX + side * 6, y: rootY + half + 0.2))
                p.closeSubpath()
                ctx.addPath(p)
                ctx.fillPath()
            }
        }
        // A thin gap separates the badge from the feathers.
        ctx.setBlendMode(.clear)
        ctx.fillEllipse(in: CGRect(x: c.x - r - 1, y: c.y - r - 1, width: (r + 1) * 2, height: (r + 1) * 2))
        ctx.setBlendMode(.normal)
        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        cutPlane(ctx, centre: c, span: 8.6, heading: 0)
    }

    /// Cuts the app's 100-unit nose-up plane out of what is already drawn.
    private static func cutPlane(_ ctx: CGContext, centre: CGPoint, span: CGFloat, heading: CGFloat) {
        var t = CGAffineTransform(translationX: centre.x, y: centre.y)
            .rotated(by: heading) // clockwise from north, in this y-down space
            .scaledBy(x: span / 100, y: span / 100)
            .translatedBy(x: -50, y: -50)
        guard let plane = PlaneSilhouetteView.outline.cgPath.copy(using: &t) else { return }
        ctx.saveGState()
        ctx.setBlendMode(.clear)
        ctx.addPath(plane)
        ctx.fillPath()
        ctx.restoreGState()
    }
}
