import AppKit
import SwiftUI

/// The menu bar icon: the app's own airliner climbing up and to the right, two contrails fading out
/// behind it. It is drawn from the in-flight plane rather than the system airplane symbol, which
/// macOS uses for Airplane Mode. A template image, so macOS tints it for light and dark menu bars.
enum MenuBarIcon {
    static let image: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let centre = CGPoint(x: 11, y: 7)
            let span: CGFloat = 14
            let heading = CGFloat.pi / 4 // clockwise from north, in this y-down space
            let ahead = CGVector(dx: sin(heading), dy: -cos(heading))
            let side = CGVector(dx: cos(heading), dy: sin(heading))

            // Contrails from the engines, fading away behind the plane.
            ctx.setLineCap(.round)
            ctx.setLineWidth(1)
            let fade = CGGradient(colorSpace: CGColorSpaceCreateDeviceGray(), colorComponents: [0, 0.85, 0, 0], locations: [0, 1], count: 2)!
            for k in [-1.0, 1.0] as [CGFloat] {
                let start = CGPoint(x: centre.x + side.dx * span * 0.18 * k - ahead.dx * span * 0.48,
                                    y: centre.y + side.dy * span * 0.18 * k - ahead.dy * span * 0.48)
                let length: CGFloat = 5.5
                let end = CGPoint(x: start.x - ahead.dx * length, y: start.y - ahead.dy * length)
                ctx.saveGState()
                ctx.move(to: start)
                ctx.addLine(to: end)
                ctx.replacePathWithStrokedPath()
                ctx.clip()
                ctx.drawLinearGradient(fade, start: start, end: end, options: [.drawsBeforeStartLocation])
                ctx.restoreGState()
            }

            // The plane itself: the 100-unit nose-up outline, scaled, turned and centred.
            var t = CGAffineTransform(translationX: centre.x, y: centre.y)
                .rotated(by: heading)
                .scaledBy(x: span / 100, y: span / 100)
                .translatedBy(x: -50, y: -50)
            guard let plane = PlaneSilhouetteView.outline.cgPath.copy(using: &t) else { return false }
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.addPath(plane)
            ctx.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Focus on Flight"
        return image
    }()
}
